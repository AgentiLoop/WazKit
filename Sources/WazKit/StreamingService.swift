//
//  StreamingService.swift
//  WazKit
//
//  What the player needs from a streaming service's API client: the FairPlay certificate and
//  license calls, and how that service wants key URIs turned into content identifiers. The apps'
//  clients (Disney+, Hulu) conform; browsing and sign-in stay in each app.
//

import Foundation

public protocol StreamingService: Sendable {
    /// The service's name ("Disney+", "Hulu"): the Now Playing "artist" when an item has no subtitle.
    var name: String { get }
    /// The FairPlay application certificate (DER) at the URL the playback answer named.
    func certificate(_ url: URL) async throws -> Data
    /// SPC in, CKC out, both raw bytes (the client does any base64 the server wants).
    func license(_ url: URL, spc: Data) async throws -> Data
    /// The content identifier the license server expects for a key URI ("skd://…").
    func contentIdentifier(forKeyURI uri: String) -> Data
}

/// What a playback call answers: the HLS stream and where to get its FairPlay keys.
public struct Playback: Sendable {
    public let streamURL: URL
    public let licenseURL: URL
    public let certificateURL: URL
    /// Where to resume, in seconds (0 to start over; live has none).
    public let resume: Double
    public let isLive: Bool

    public init(streamURL: URL, licenseURL: URL, certificateURL: URL, resume: Double, isLive: Bool) {
        self.streamURL = streamURL
        self.licenseURL = licenseURL
        self.certificateURL = certificateURL
        self.resume = resume
        self.isLive = isLive
    }
}

/// What the player shows about the thing it is playing.
public struct NowPlaying: Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

public enum PlayerError: LocalizedError {
    /// A key request the delegate could not serve (no identifier, no certificate, no SPC…).
    case keyRequest(String)
    /// No FairPlay here (the iOS Simulator).
    case noFairPlay

    public var errorDescription: String? {
        switch self {
        case .keyRequest(let what): "Could not get a playback key (\(what))."
        case .noFairPlay: "Protected video needs a real iPhone or iPad; the Simulator has no FairPlay."
        }
    }
}
