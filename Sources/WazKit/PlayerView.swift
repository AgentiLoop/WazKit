//
//  PlayerView.swift
//  WazKit
//
//  The TV tab and the split-out window share this: the movie, or why there is none. While the movie
//  is in its own window the tab says so and offers to bring it back.
//

import SwiftUI
import AVKit

public struct PlayerView: View {
    @ObservedObject var player: PlayerController
    let inWindow: Bool
    let title: String

    /// `title` is the navigation title while nothing is playing (the app's name, say).
    public init(player: PlayerController, inWindow: Bool, title: String = "") {
        self.player = player
        self.inWindow = inWindow
        self.title = title
    }

    public var body: some View {
        ZStack {
            Color.black
            if let error = player.error {
                ContentUnavailableView(error, systemImage: "play.slash")
                    .foregroundStyle(.white)
            } else if player.current == nil {
                ContentUnavailableView("Nothing Playing", systemImage: "tv", description: Text("Pick something to watch."))
                    .foregroundStyle(.white)
            } else if player.isSplitOut && !inWindow {
                ContentUnavailableView {
                    Label("Playing in Its Own Window", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("Close that window to bring the movie back here.")
                } actions: {
                    Button("Bring Back") { player.isSplitOut = false }
                }
                .foregroundStyle(.white)
            } else {
                VideoPlayerView(player: player.player)
            }
        }
        .navigationTitle(player.current?.title ?? title)
    }
}

/// AVKit's player view: its floating controls include full screen and Picture in Picture.
public struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    public init(player: AVPlayer) { self.player = player }

    public func makeNSView(context: Context) -> AVPlayerView {
        let view = FocusingPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    public func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

/// Takes keyboard focus as soon as it is on screen, so space/arrows drive playback instead of the sidebar.
/// SwiftUI hands focus back to the sidebar after the first attempt, so it keeps claiming it on every
/// layout pass until it actually holds it, and again whenever the window becomes key.
final class FocusingPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { true }
    private var keyObserver: NSObjectProtocol?
    private var claimsLeft = 0

    private var hasFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === self || responder.isDescendant(of: self)
    }

    private func claimFocus() {
        guard let window, !hasFocus else { return }
        window.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        claimsLeft = 10
        claimFocus()
        DispatchQueue.main.async { [weak self] in self?.claimFocus() }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.claimFocus()
        }
    }

    override func layout() {
        super.layout()
        hideLoadingIndicators(in: self)
        guard claimsLeft > 0 else { return }
        claimFocus()
        if hasFocus { claimsLeft = 0 } else { claimsLeft -= 1 }
    }

    /// AVKit draws its own buffering spinner inside the player view; walk the hierarchy and hide it.
    private func hideLoadingIndicators(in view: NSView) {
        for sub in view.subviews {
            let name = String(describing: type(of: sub))
            if sub is NSProgressIndicator || name.contains("Loading") || name.contains("Spinner") || name.contains("ProgressIndicator") {
                sub.isHidden = true
            } else {
                hideLoadingIndicators(in: sub)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        claimFocus()
        super.mouseDown(with: event)
    }

    deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }
}
