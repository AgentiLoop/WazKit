//
//  WebSignIn.swift
//  WazKit
//
//  Signing in happens on the service's own site, in a web view sheet. The app says where to start
//  and how to tell, from the web view, that the user is in (a token in localStorage, a session cookie);
//  the sheet asks after every page load and then once a second, since the sites are single-page apps
//  that change state without navigating.
//

import SwiftUI
import WebKit

public enum WebSignIn {
    /// A web view the sites take for Safari: WebKit's default UA has no "Version/… Safari/…" tail, so add Safari's.
    public static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        config.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: config)
    }
}

public struct WebSignInView: View {
    let title: String
    let url: URL
    let size: CGSize
    let isSignedIn: @MainActor (WKWebView) async -> Bool
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - title: The sheet's heading ("Sign in to …").
    ///   - url: The site's login page.
    ///   - isSignedIn: Looks at the web view (URL, localStorage, cookies) and says whether the user is in;
    ///     it is also where the app copies the session out. Called after each page load, then once a second.
    ///   - onSignedIn: Called once, before the sheet dismisses itself.
    public init(title: String, url: URL, size: CGSize = CGSize(width: 960, height: 720),
                isSignedIn: @escaping @MainActor (WKWebView) async -> Bool, onSignedIn: @escaping () -> Void) {
        self.title = title
        self.url = url
        self.size = size
        self.isSignedIn = isSignedIn
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            SignInWebView(url: url, isSignedIn: isSignedIn) {
                onSignedIn()
                dismiss()
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct SignInWebView: NSViewRepresentable {
    let url: URL
    let isSignedIn: @MainActor (WKWebView) async -> Bool
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(isSignedIn: isSignedIn, onSignedIn: onSignedIn) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WebSignIn.makeWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let isSignedIn: @MainActor (WKWebView) async -> Bool
        let onSignedIn: () -> Void
        private var check: Task<Void, Never>?
        private var done = false

        init(isSignedIn: @escaping @MainActor (WKWebView) async -> Bool, onSignedIn: @escaping () -> Void) {
            self.isSignedIn = isSignedIn
            self.onSignedIn = onSignedIn
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The sites are single-page apps: picking a profile or finishing login can change state without
            // a navigation, so keep asking for a while after each page load.
            check?.cancel()
            check = Task { @MainActor in
                for _ in 0..<120 where !done && !Task.isCancelled {
                    if await isSignedIn(webView) {
                        done = true
                        onSignedIn()
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        deinit { check?.cancel() }
    }
}
