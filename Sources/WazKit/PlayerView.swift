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
    let onClose: (() -> Void)?

    /// `title` is the navigation title while nothing is playing (the app's name, say).
    /// `onClose` (iPhone): the movie starts in AVKit's full screen, and its ✕ calls this.
    public init(player: PlayerController, inWindow: Bool, title: String = "", onClose: (() -> Void)? = nil) {
        self.player = player
        self.inWindow = inWindow
        self.title = title
        self.onClose = onClose
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
                #if os(macOS)
                VideoPlayerView(player: player.player)
                #else
                VideoPlayerView(player: player.player, onClose: onClose)
                #endif
            }
        }
        .navigationTitle(player.current?.title ?? title)
    }
}

/// AVKit's player view: its floating controls include full screen and Picture in Picture.
#if os(macOS)
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
#else
/// On iPhone the movie starts in AVKit's own full screen; its ✕ (closing full screen) calls `onClose`.
/// Leaving full screen for Picture in Picture does not.
public struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onClose: (() -> Void)?

    public init(player: AVPlayer, onClose: (() -> Void)? = nil) {
        self.player = player
        self.onClose = onClose
    }

    public func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = onClose != nil
        controller.exitsFullScreenWhenPlaybackEnds = true
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onClose = onClose
    }

    public final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onClose: (() -> Void)?
        private var inPictureInPicture = false

        init(onClose: (() -> Void)?) { self.onClose = onClose }

        public func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) { inPictureInPicture = true }
        public func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) { inPictureInPicture = false }

        public func playerViewController(_ controller: AVPlayerViewController,
                                         willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self, !context.isCancelled, !self.inPictureInPicture else { return }
                self.onClose?()
            }
        }
    }
}
#endif

#if os(macOS)
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
#endif
