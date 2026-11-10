//
//  MacWindow.swift
//  WazKit
//
//  The Mac apps' main window pieces: making the `Window` scene full-screen capable, and hiding the
//  toolbar in full screen. (The TV tab's player, PlayerContainer, is in MacPlayer.swift.)
//
#if os(macOS)
import SwiftUI
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
