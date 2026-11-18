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
                PlayerContainer(controller: player)
                #else
                VideoPlayerView(player: player.player, onClose: onClose, closesAtEnd: player.onEnd == nil,
                                skip: player.skippable?.title, onSkip: { player.skipPart() })
                #endif
            }
        }
        .navigationTitle(player.current?.title ?? title)
    }
}

#if os(iOS)
/// On iPhone the movie starts in AVKit's own full screen; its ✕ (closing full screen) calls `onClose`.
/// Leaving full screen for Picture in Picture does not. `closesAtEnd`: AVKit leaves full screen when the
/// movie ends (off for an app that plays the next thing then, and closes the player itself).
/// `skip`: the title of a button to show over the movie ("Skip Intro"), nil for none; a tap calls `onSkip`.
public struct VideoPlayerView: View {
    let player: AVPlayer
    let onClose: (() -> Void)?
    let closesAtEnd: Bool
    let skip: String?
    let onSkip: (() -> Void)?

    public init(player: AVPlayer, onClose: (() -> Void)? = nil, closesAtEnd: Bool = true,
                skip: String? = nil, onSkip: (() -> Void)? = nil) {
        self.player = player
        self.onClose = onClose
        self.closesAtEnd = closesAtEnd
        self.skip = skip
        self.onSkip = onSkip
    }

    public var body: some View {
        // The skip button lies over AVKit's player, not in it: a button in AVKit's content overlay is under
        // AVKit's controls and gets no touches, and AVKit never lets a tap recognizer of ours on the window
        // fire (iOS 18, 26 and 27). Bottom right, above AVKit's controls and as far in as they are.
        GeometryReader { area in
            let insets = windowInsets(area)
            AVKitPlayer(player: player, onClose: onClose, closesAtEnd: closesAtEnd)
                .overlay(alignment: .bottomTrailing) {
                    if let skip {
                        Button { onSkip?() } label: {
                            Text(skip)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color(white: 0.13, opacity: 0.85), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, max(insets.right, 20))
                        .padding(.bottom, insets.bottom + 125)
                    }
                }
        }
    }

    /// The window's safe area (the sensor housing, the home indicator). The apps show the player edge to edge
    /// (`ignoresSafeArea`), so SwiftUI reports none in here. `area` is asked for so that a turn of the phone,
    /// which changes it, asks again.
    private func windowInsets(_ area: GeometryProxy) -> UIEdgeInsets {
        _ = area.size
        return UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }
}

/// AVKit's player (AVPlayerViewController).
struct AVKitPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let onClose: (() -> Void)?
    let closesAtEnd: Bool

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = onClose != nil
        controller.exitsFullScreenWhenPlaybackEnds = closesAtEnd
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onClose = onClose
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onClose: (() -> Void)?
        private var inPictureInPicture = false

        init(onClose: (() -> Void)?) { self.onClose = onClose }

        func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) { inPictureInPicture = true }
        func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) { inPictureInPicture = false }

        func playerViewController(_ controller: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self, !context.isCancelled, !self.inPictureInPicture else { return }
                self.onClose?()
            }
        }
    }
}
#endif

#if os(tvOS)
/// On Apple TV the movie fills the screen in AVKit's player. The remote's Back (Menu) button, once AVKit's
/// controls are hidden, calls `onClose`. `skip` shows as AVKit's own contextual action button
/// (bottom right, focusable with the remote), the tvOS way to offer "Skip Intro"; selecting it calls `onSkip`.
public struct VideoPlayerView: View {
    let player: AVPlayer
    let onClose: (() -> Void)?
    let closesAtEnd: Bool
    let skip: String?
    let onSkip: (() -> Void)?

    public init(player: AVPlayer, onClose: (() -> Void)? = nil, closesAtEnd: Bool = true,
                skip: String? = nil, onSkip: (() -> Void)? = nil) {
        self.player = player
        self.onClose = onClose
        self.closesAtEnd = closesAtEnd
        self.skip = skip
        self.onSkip = onSkip
    }

    public var body: some View {
        TVPlayer(player: player, skip: skip, onSkip: onSkip)
            .ignoresSafeArea()
            .onExitCommand { onClose?() }
    }
}

/// AVKit's player (AVPlayerViewController) with the skip button as a contextual action.
struct TVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let skip: String?
    let onSkip: (() -> Void)?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        update(controller)
    }

    private func update(_ controller: AVPlayerViewController) {
        guard let skip else {
            if !controller.contextualActions.isEmpty { controller.contextualActions = [] }
            return
        }
        if controller.contextualActions.first?.title == skip { return }
        let onSkip = onSkip
        controller.contextualActions = [UIAction(title: skip) { _ in onSkip?() }]
    }
}
#endif
