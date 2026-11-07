# WazKit

The code [Waze](https://github.com/AgentiLoop/Waze) (Disney+) and [Wazu](https://github.com/AgentiLoop/Wazu)
(Hulu) have in common: a FairPlay-capable AVPlayer with its views and split-out window, the
sign-in web view sheet, and the artwork tiles. A Swift package for macOS 14+, SwiftUI/AppKit.
Personal project, not for distribution.

Everything service-specific — browsing APIs, models, how a session is kept — stays in each app.
The app plugs its API client into the player through one protocol.

## What is in it

| Type | Role |
| --- | --- |
| `StreamingService` | Protocol an app's API client adopts: `name`, `certificate(_:)`, `license(_:spc:)`, `contentIdentifier(forKeyURI:)` |
| `Playback` | What a playback call answers: stream URL, license URL, certificate URL, resume position, live flag |
| `NowPlaying` | What the player shows about the thing it is playing (id, title, subtitle) |
| `PlayerController` | `ObservableObject` around `AVPlayer` + `AVContentKeySession`: `play(_:load:)`, `stop()`, `playPause()`, `skip(_:)`, media keys / Now Playing, `isSplitOut`, `floatsOnTop` |
| `PlayerView` | The TV tab / window content: the movie, "Nothing Playing", or "Playing in Its Own Window" |
| `VideoPlayerView` | `AVPlayerView` with floating controls, full screen and PiP; claims keyboard focus so space/arrows work |
| `PlayerWindowController` | Internal. The split-out window (own full screen, Float on Top); opens while `isSplitOut` and something plays |
| `WebSignInView` | Sheet with a `WKWebView` on the service's login page; the app says how to tell the user is in |
| `WebSignIn.makeWebView()` | A web view the sites take for Safari (adds the `Version/… Safari/…` UA tail) |
| `Tile` / `TileCard` | Protocol an app's item adopts + the 16:9 / poster card with title, subtitle, LIVE badge and a context menu |
| `Artwork` | Cached tile image that retries while the image server is still rendering the size |

## Usage

### Add the package

With [xcodegen](https://github.com/yonaskolb/XcodeGen), in `project.yml`:

```yaml
packages:
  WazKit:
    path: ../WazKit          # clone WazKit next to the app
targets:
  MyApp:
    dependencies:
      - package: WazKit
```

Or point at the repo instead of a sibling checkout:

```yaml
packages:
  WazKit:
    url: https://github.com/AgentiLoop/WazKit
    branch: main
```

In Xcode without xcodegen: File > Add Package Dependencies… and add the local folder or the URL.

### Make the API client a `StreamingService`

```swift
import WazKit

actor HuluClient: StreamingService {
    nonisolated var name: String { "Hulu" }

    func certificate(_ url: URL) async throws -> Data { /* GET the .cer */ }
    func license(_ url: URL, spc: Data) async throws -> Data { /* POST SPC, return CKC bytes */ }

    /// What the license server wants as the content identifier for an "skd://…" key URI.
    nonisolated func contentIdentifier(forKeyURI uri: String) -> Data { Data(uri.utf8) }

    /// Any signature; it just has to end in a Playback.
    func playback(eab: String) async throws -> Playback { … }
}
```

Disney+ wants only the URI's host (`uri.replacingOccurrences(of: "skd://", with: "")`); Hulu
wants the whole URI. That is the one FairPlay difference between the two, and it lives here.

### Play something

```swift
let player = PlayerController(service: client)

player.play(NowPlaying(id: item.id, title: item.title, subtitle: item.subtitle)) { [client] in
    try await client.playback(eab: eab)
}
```

The closure is the service-specific call; the controller fetches the certificate, wires the
key session, seeks to `resume` and plays. `player.current`, `isPlaying`, `isLoading`, `error`
are published. `player.isSplitOut = true` moves the movie to its own window; closing that
window sets it back. `player.floatsOnTop` is the window's Float on Top.

### Show the player

```swift
PlayerView(player: app.player, inWindow: false, title: "Wazu")   // title while nothing plays
```

### Sign in

```swift
WebSignInView(title: "Sign in to Hulu", url: URL(string: "https://www.hulu.com/login")!,
              isSignedIn: { webView in
    // Look at the web view (URL, cookies, localStorage), copy the session out, say whether the user is in.
    for cookie in await webView.configuration.websiteDataStore.httpCookieStore.allCookies() {
        HTTPCookieStorage.shared.setCookie(cookie)
    }
    return webView.url?.host == "www.hulu.com" && HuluClient.isSignedIn
}, onSignedIn: { app.session += 1 })
```

`isSignedIn` runs after every page load and then once a second for up to two minutes (the sites
are single-page apps that change state without navigating). The sheet dismisses itself once it
returns true.

### Tiles

```swift
extension Item: Tile {}   // title, subtitle, description, isLive, artwork(width:height:)

TileCard(item, vertical: row.isPoster, tint: .teal) {
    app.open(item)
} menu: {
    Button("Play") { app.play(item) }
}
```

## Build

```sh
swift build
```

Both apps build against a sibling checkout (`../WazKit`); after changing the package, rebuild
the app — Xcode picks the change up without `xcodegen generate`.

## Layout

| File | Role |
| --- | --- |
| `Sources/WazKit/StreamingService.swift` | `StreamingService`, `Playback`, `NowPlaying`, `PlayerError` |
| `Sources/WazKit/Player.swift` | `PlayerController` and the `AVContentKeySessionDelegate` |
| `Sources/WazKit/PlayerView.swift` | `PlayerView`, `VideoPlayerView`, focus-claiming `AVPlayerView` |
| `Sources/WazKit/PlayerWindow.swift` | The split-out window controller |
| `Sources/WazKit/WebSignIn.swift` | `WebSignInView`, `WebSignIn.makeWebView()` |
| `Sources/WazKit/Tiles.swift` | `Tile`, `TileCard`, `Artwork` |
