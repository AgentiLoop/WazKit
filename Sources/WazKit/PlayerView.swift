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
public struct VideoPlayerView: UIViewControllerRepresentable {
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

    public func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = onClose != nil
        controller.exitsFullScreenWhenPlaybackEnds = closesAtEnd
        // The skip button goes in AVKit's content overlay (over the movie, full screen too): bottom right,
        // above where AVKit draws its scrubber.
        if let overlay = controller.contentOverlayView {
            let button = SkipButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                button.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -96),
            ])
            context.coordinator.skipButton = button
        }
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onClose = onClose
        context.coordinator.skipButton?.show(skip, onTap: onSkip)
    }

    public final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onClose: (() -> Void)?
        var skipButton: SkipButton?
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

/// The Skip Intro / Skip Recap button. AVKit's content overlay sits under AVKit's own controls, so the
/// button does not take touches itself: a tap recognizer on the window takes the taps that land on it.
final class SkipButton: UIButton, UIGestureRecognizerDelegate {
    private var onTap: (() -> Void)?
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped))

    init() {
        super.init(frame: .zero)
        var style = UIButton.Configuration.filled()
        style.cornerStyle = .capsule
        style.baseBackgroundColor = UIColor(white: 0.13, alpha: 0.85)
        style.baseForegroundColor = .white
        style.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        configuration = style
        isHidden = true
        isUserInteractionEnabled = false
        tap.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ title: String?, onTap: (() -> Void)?) {
        self.onTap = onTap
        isHidden = title == nil
        if let title { configuration?.title = title }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        tap.view?.removeGestureRecognizer(tap)
        window?.addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isHidden && bounds.contains(touch.location(in: self))
    }

    @objc private func tapped() { onTap?() }
}
#endif
