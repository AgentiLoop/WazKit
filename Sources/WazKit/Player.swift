//
//  Player.swift
//  WazKit
//
//  AVPlayer with FairPlay: the key session asks for each key, the delegate makes the SPC with the
//  service's certificate, posts it to the license server, and hands back the CKC. Media keys come
//  through MPRemoteCommandCenter. The controller also owns the split-out player window.
//

import AVFoundation
import MediaPlayer
import Combine

@MainActor
public final class PlayerController: ObservableObject {
    public let player = AVPlayer()
    public let service: any StreamingService
    @Published public private(set) var current: NowPlaying?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isLoading = false
    @Published public var error: String?
    /// The movie plays in its own window (PlayerWindowController) instead of the app's TV tab (macOS).
    @Published public var isSplitOut = false
    /// Float on Top: the split-out player window stays above other windows (macOS).
    @Published public var floatsOnTop = false {
        didSet {
            #if os(macOS)
            windowController.isFloating = floatsOnTop
            #endif
        }
    }

    /// FairPlay exists only on real devices: the iOS Simulator throws on creating the session, so it has none there.
    #if targetEnvironment(simulator)
    private let keySession: AVContentKeySession? = nil
    #else
    private let keySession: AVContentKeySession? = AVContentKeySession(keySystem: .fairPlayStreaming)
    #endif
    private let keys: KeyDelegate
    private var observers: [NSKeyValueObservation] = []
    #if os(macOS)
    private lazy var windowController = PlayerWindowController(player: self)
    #endif

    public init(service: any StreamingService) {
        self.service = service
        keys = KeyDelegate(service: service)
        keySession?.setDelegate(keys, queue: DispatchQueue(label: "wazkit.fairplay"))
        #if os(iOS)
        // Sound with the ring/silent switch on, and keep playing in the background and in Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
        observers = [
            player.observe(\.rate, options: .new) { [weak self] player, _ in
                MainActor.assumeIsolated {
                    self?.isPlaying = player.rate > 0
                    self?.updateNowPlayingInfo()
                }
            },
        ]
        installRemoteCommands()
    }

    private var loadTask: Task<Void, Never>?
    private var itemWatch: Set<AnyCancellable> = []
    /// Asks the service for the current stream again (what `play` was given).
    private var reload: (@Sendable () async throws -> Playback)?
    /// Restreams in a row; a stream that then plays for a minute clears the count.
    private var restreams = 0
    private var started = Date()

    /// Plays `what`; `load` asks the service for the stream (the app knows which call that is).
    public func play(_ what: NowPlaying, load: @escaping @Sendable () async throws -> Playback) {
        #if os(macOS)
        _ = windowController
        #endif
        current = what
        reload = load
        restreams = 0
        start(load)
    }

    /// Loads the stream and plays it. `position` is set when restreaming: where the stopped stream was, in seconds.
    private func start(_ load: @escaping @Sendable () async throws -> Playback, restreamingAt position: Double? = nil) {
        loadTask?.cancel()
        itemWatch = []
        player.pause()
        player.replaceCurrentItem(with: nil)
        isLoading = true
        error = nil
        loadTask = Task {
            do {
                // The first restream is immediate; the next ones give the network a little longer each time.
                if restreams > 1 { try await Task.sleep(for: .seconds(5 * (restreams - 1))) }
                let playback = try await load()
                guard let keySession else { throw PlayerError.noFairPlay }
                let certificate = try await service.certificate(playback.certificateURL)
                try Task.checkCancellation()
                keys.prepare(licenseURL: playback.licenseURL, certificate: certificate)
                let asset = AVURLAsset(url: playback.streamURL)
                keySession.addContentKeyRecipient(asset)
                let playerItem = AVPlayerItem(asset: asset)
                // Disney+ marks its ad breaks as HLS interstitials whose ad list ("app://…") only its own player can
                // fetch. Left on, AVPlayer parks the buffer at the marker waiting for it and can run dry there.
                playerItem.automaticallyHandlesInterstitialEvents = false
                watch(playerItem)
                player.replaceCurrentItem(with: playerItem)
                started = Date()
                // A restream carries on where the stream stopped; live rejoins at the live edge.
                var resume = playback.resume
                if let position, position > 0, !playback.isLive { resume = position }
                if resume > 0 {
                    player.seek(to: CMTime(seconds: resume, preferredTimescale: 1000), completionHandler: { _ in })
                }
                player.play()
            } catch {
                if Task.isCancelled { return }
                if let position {
                    restream(at: position, because: error.localizedDescription)
                    return
                }
                self.error = error.localizedDescription
                current = nil
            }
            isLoading = false
        }
    }

    public func stop() {
        loadTask?.cancel()
        loadTask = nil
        itemWatch = []
        reload = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isLoading = false
        updateNowPlayingInfo()
    }

    /// Seconds in a row the current stream has not kept up (see `check`).
    private var starved = 0
    private var lastTime = 0.0

    /// Called when what is playing reaches its end. The app plays the next thing or stops; an app that
    /// sets this also closes the iPhone's full-screen player itself (see `VideoPlayerView`).
    public var onEnd: (() -> Void)?

    /// A stream that stops by itself is restreamed: the item failed (bad key, dead stream, network gone),
    /// or it stopped keeping up (checked once a second). One that plays to its end calls `onEnd`.
    private func watch(_ item: AVPlayerItem) {
        starved = 0
        itemWatch = [
            item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] status in
                guard status == .failed else { return }
                MainActor.assumeIsolated { self?.stopped(item, because: item.error?.localizedDescription ?? "Playback failed") }
            },
            NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
                .receive(on: DispatchQueue.main).sink { [weak self] note in
                    let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    MainActor.assumeIsolated { self?.stopped(item, because: error?.localizedDescription ?? "Playback failed") }
                },
            NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
                .receive(on: DispatchQueue.main).sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.player.currentItem === item else { return }
                        self.onEnd?()
                    }
                },
            Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                MainActor.assumeIsolated { self?.check(item) }
            },
        ]
    }

    /// Is the stream keeping up? AVPlayer can say it is playing with nothing coming out: its clock runs on
    /// past the end of what it has loaded, and no stall is ever posted. So this looks at the buffer itself:
    /// wanting to play for ten seconds in a row with nothing loaded ahead of the playhead, or with the
    /// playhead not moving, is a stopped stream.
    private func check(_ item: AVPlayerItem) {
        guard player.currentItem === item, player.timeControlStatus != .paused else {
            starved = 0
            return
        }
        let time = item.currentTime()
        let loaded = item.loadedTimeRanges.map(\.timeRangeValue).first { $0.containsTime(time) }
        let ahead = loaded.map { $0.end.seconds - time.seconds } ?? 0
        let moved = time.seconds != lastTime
        lastTime = time.seconds
        starved = ahead > 0 && moved ? 0 : starved + 1
        if starved >= 10 {
            starved = 0
            stopped(item, because: nil)
        }
    }


    private func stopped(_ item: AVPlayerItem, because message: String?) {
        guard player.currentItem === item else { return }
        if Date().timeIntervalSince(started) > 60 { restreams = 0 }
        let position = item.currentTime().seconds
        restream(at: position.isFinite ? position : 0, because: message)
    }

    /// Asks the service for the stream again and plays on from `position`. After five tries in a row the
    /// error shows (a stall has none: the player just keeps waiting).
    private func restream(at position: Double, because message: String?) {
        guard current != nil, let reload else { return }
        guard restreams < 5 else {
            if let message {
                error = message
                isLoading = false
            }
            return
        }
        restreams += 1
        start(reload, restreamingAt: position)
    }


    public func playPause() {
        isPlaying ? player.pause() : player.play()
    }

    public func skip(_ seconds: Double) {
        let target = CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 1000))
        player.seek(to: CMTimeMaximum(target, .zero))
    }

    // MARK: Media keys

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.player.play(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.player.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.playPause(); return .success }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in self?.skip(10); return .success }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(-10); return .success }
    }

    /// The system only routes media keys to an app that is "now playing", so say so.
    private func updateNowPlayingInfo() {
        let info = MPNowPlayingInfoCenter.default()
        guard let current else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        info.nowPlayingInfo = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: current.subtitle ?? service.name]
        info.playbackState = isPlaying ? .playing : .paused
    }
}

/// Answers AVContentKeySession's key requests; the service says what part of the "skd://…" URI
/// its license server wants as the content identifier.
private final class KeyDelegate: NSObject, AVContentKeySessionDelegate {
    private let service: any StreamingService
    private var licenseURL: URL?
    private var certificate: Data?

    init(service: any StreamingService) { self.service = service }

    func prepare(licenseURL: URL, certificate: Data) {
        self.licenseURL = licenseURL
        self.certificate = certificate
    }

    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        handle(keyRequest)
    }

    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        handle(keyRequest)
    }

    private func handle(_ keyRequest: AVContentKeyRequest) {
        guard let identifier = keyRequest.identifier as? String, let licenseURL, let certificate else {
            keyRequest.processContentKeyResponseError(PlayerError.keyRequest("key request"))
            return
        }
        keyRequest.makeStreamingContentKeyRequestData(forApp: certificate, contentIdentifier: service.contentIdentifier(forKeyURI: identifier),
                                                      options: [AVContentKeyRequestProtocolVersionsKey: [1]]) { spc, error in
            guard let spc else {
                keyRequest.processContentKeyResponseError(error ?? PlayerError.keyRequest("SPC"))
                return
            }
            Task {
                do {
                    let ckc = try await self.service.license(licenseURL, spc: spc)
                    keyRequest.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc))
                } catch {
                    keyRequest.processContentKeyResponseError(error)
                }
            }
        }
    }
}
