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
    /// The movie plays in its own window (PlayerWindowController) instead of the app's TV tab.
    @Published public var isSplitOut = false
    /// Float on Top: the split-out player window stays above other windows.
    @Published public var floatsOnTop = false { didSet { windowController.isFloating = floatsOnTop } }

    private let keySession = AVContentKeySession(keySystem: .fairPlayStreaming)
    private let keys: KeyDelegate
    private var observers: [NSKeyValueObservation] = []
    private lazy var windowController = PlayerWindowController(player: self)

    public init(service: any StreamingService) {
        self.service = service
        keys = KeyDelegate(service: service)
        keySession.setDelegate(keys, queue: DispatchQueue(label: "wazkit.fairplay"))
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
    private var itemObserver: NSKeyValueObservation?

    /// Plays `what`; `load` asks the service for the stream (the app knows which call that is).
    public func play(_ what: NowPlaying, load: @escaping @Sendable () async throws -> Playback) {
        _ = windowController
        loadTask?.cancel()
        itemObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = what
        isLoading = true
        error = nil
        loadTask = Task {
            do {
                let playback = try await load()
                let certificate = try await service.certificate(playback.certificateURL)
                try Task.checkCancellation()
                keys.prepare(licenseURL: playback.licenseURL, certificate: certificate)
                let asset = AVURLAsset(url: playback.streamURL)
                keySession.addContentKeyRecipient(asset)
                let playerItem = AVPlayerItem(asset: asset)
                watch(playerItem)
                player.replaceCurrentItem(with: playerItem)
                if playback.resume > 0 {
                    player.seek(to: CMTime(seconds: playback.resume, preferredTimescale: 1000), completionHandler: { _ in })
                }
                player.play()
            } catch {
                if Task.isCancelled { return }
                self.error = error.localizedDescription
                current = nil
            }
            isLoading = false
        }
    }

    public func stop() {
        loadTask?.cancel()
        loadTask = nil
        itemObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isLoading = false
        updateNowPlayingInfo()
    }

    /// A failed item (bad key, dead stream) would otherwise leave the player spinning forever.
    private func watch(_ item: AVPlayerItem) {
        itemObserver = item.observe(\.status, options: .new) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, item.status == .failed, self.player.currentItem === item else { return }
                self.error = item.error?.localizedDescription ?? "Playback failed"
                self.isLoading = false
            }
        }
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
