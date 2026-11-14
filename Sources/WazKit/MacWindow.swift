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
/// Full screen is also remembered: an app quit in full screen comes back in full screen.
public struct FullScreenCapable: NSViewRepresentable {
    public init() {}
    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            view.window?.collectionBehavior.insert(.fullScreenPrimary)
            view.window?.collectionBehavior.remove(.fullScreenAuxiliary)
            view.window?.collectionBehavior.remove(.fullScreenNone)
            if let window = view.window { coordinator.remember(window) }
        }
        return view
    }
    public func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    public final class Coordinator {
        private var observers: [NSObjectProtocol] = []
        private var quitting = false

        /// Saves whether `window` is full screen as that changes, and puts it back in full screen now if it
        /// was when the app was last quit. A window that leaves full screen while the app is quitting
        /// does not count as the user leaving it.
        func remember(_ window: NSWindow) {
            let center = NotificationCenter.default, key = "mainFullScreen"
            observers = [
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
                    UserDefaults.standard.set(true, forKey: key)
                },
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if self?.quitting != true { UserDefaults.standard.set(false, forKey: key) } }
                },
                center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.quitting = true }
                },
            ]
            if UserDefaults.standard.bool(forKey: key), !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
    }
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
    /// The sidebar was hidden outside full screen: the next launch starts with it hidden too.
    @AppStorage("sidebarHidden") private var sidebarHidden = false

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
            .onAppear {
                guard sidebarHidden else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { columns = .detailOnly }
            }
            // Full screen hides the sidebar by itself (and puts it back after), so only what it is set to
            // outside full screen is the user's choice.
            .onChange(of: columns) { _, columns in
                if !fullScreen { sidebarHidden = columns == .detailOnly }
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
