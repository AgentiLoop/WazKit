//
//  MacWindow.swift
//  WazKit
//
//  The Mac apps' main window pieces: the TV tab's player view, making the `Window` scene full-screen
//  capable, and hiding the toolbar in full screen.
//
#if os(macOS)
import SwiftUI
import AVKit
/// IPTVee's AVPlayerView wrapper, singleton removed: the AVPlayer is passed in
/// (PlayerController owns it) instead of grabbed from a shared PlayerViewObservable.
/// Fullscreen and picture-in-picture come from AVKit's floating controls.
public struct PlayerContainer: NSViewRepresentable {
    let player: AVPlayer
    public init(player: AVPlayer) { self.player = player }
    public func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.layer?.backgroundColor = .clear
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }
    public func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
/// The `Window` scene's NSWindow is not full-screen capable by default, which leaves
/// View > Enter Full Screen (and AVPlayerView's fullscreen button) disabled.
public struct FullScreenCapable: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.collectionBehavior.insert(.fullScreenPrimary)
            view.window?.collectionBehavior.remove(.fullScreenAuxiliary)
            view.window?.collectionBehavior.remove(.fullScreenNone)
        }
        return view
    }
    public func updateNSView(_ nsView: NSView, context: Context) {}
}
extension View {
    /// In full screen the title bar and toolbar stay hidden until the pointer reaches the top edge (macOS 15+).
    @ViewBuilder public func hidesToolbarInFullScreen() -> some View {
        if #available(macOS 15.0, *) {
            windowToolbarFullScreenVisibility(.onHover)
        } else {
            self
        }
    }
}
#endif
