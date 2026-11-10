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

extension View {
    /// In full screen the sidebar hides; the pointer at the left edge of the screen slides it out, and it
    /// hides again once the pointer moves away from it. Leaving full screen puts it back how it was.
    public func fullScreenSidebar(_ columns: Binding<NavigationSplitViewVisibility>) -> some View {
        modifier(FullScreenSidebar(columns: columns))
    }
}

private struct FullScreenSidebar: ViewModifier {
    @Binding var columns: NavigationSplitViewVisibility
    @State private var window: NSWindow?
    @State private var fullScreen = false
    @State private var before: NavigationSplitViewVisibility?
    /// Shown by the left-edge hover (not by the user), so it hides again on its own.
    @State private var peeking = false

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window in
                self.window = window
                if window?.styleMask.contains(.fullScreen) == true { enter() }
            })
            .overlay(alignment: .leading) {
                if fullScreen && columns == .detailOnly {
                    Color.clear.frame(width: 4).frame(maxHeight: .infinity).contentShape(Rectangle())
                        .onHover { inside in
                            guard inside else { return }
                            peeking = true
                            withAnimation { columns = .all }
                        }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
                if let window, note.object as? NSWindow === window { enter() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
                guard let window, note.object as? NSWindow === window, fullScreen else { return }
                fullScreen = false
                peeking = false
                withAnimation { columns = before ?? .automatic }
                before = nil
            }
            .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
                guard peeking, fullScreen, let window else { return }
                if NSEvent.mouseLocation.x - window.frame.minX > 320 {
                    peeking = false
                    withAnimation { columns = .detailOnly }
                }
            }
    }

    private func enter() {
        guard !fullScreen else { return }
        fullScreen = true
        before = columns
        withAnimation { columns = .detailOnly }
    }
}

/// Hands the hosting NSWindow to the callback once the view is in it.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { found(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
