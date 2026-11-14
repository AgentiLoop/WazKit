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
                VideoPlayerView(player: player.player, onClose: onClose, closesAtEnd: player.onEnd == nil)
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
public struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onClose: (() -> Void)?
    let closesAtEnd: Bool

    public init(player: AVPlayer, onClose: (() -> Void)? = nil, closesAtEnd: Bool = true) {
        self.player = player
        self.onClose = onClose
        self.closesAtEnd = closesAtEnd
    }

    public func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = onClose != nil
        controller.exitsFullScreenWhenPlaybackEnds = closesAtEnd
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
