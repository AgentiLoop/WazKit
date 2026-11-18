//
//  Guide.swift
//  WazKit
//
//  A TV guide to live television: the channels down the side, the next hours across, and each
//  channel's programmes as cells as wide as they are long. The channel column stays put while the
//  guide scrolls sideways and the times stay put while it scrolls down. What is on now is tinted and
//  plays with a click; a red line marks the time. The apps say where the listings come from and what
//  playing a programme means.
//

import SwiftUI
import Combine

/// A channel in the guide and what it airs, in time order.
public struct GuideChannel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// The logo's image (a PNG with a clear background); nil shows the channel's name instead.
    public let logo: URL?
    public var programs: [GuideProgram]

    public init(id: String, name: String, logo: URL?, programs: [GuideProgram]) {
        self.id = id
        self.name = name
        self.logo = logo
        self.programs = programs
    }
}

public struct GuideProgram: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let start: Date
    public let end: Date

    public init(id: String, title: String, subtitle: String? = nil, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.start = start
        self.end = end
    }
}

/// The guide with its loading: it asks for the listings from the half hour that is running, shows a
/// spinner only until the first answer, and asks again when the next half hour starts. The search
/// text keeps the channels whose name or programmes match. The channel that is playing (or was last)
/// is highlighted, and the guide opens scrolled to it.
public struct GuideView: View {
    @ObservedObject var search: LiveSearch
    let hours: Int
    let tint: Color
    let playing: String?
    let load: (_ start: Date, _ end: Date) async throws -> [GuideChannel]
    let onSelect: (GuideChannel, GuideProgram) -> Void
    @State private var channels: [GuideChannel]?
    @State private var error: String?
    @State private var now = Date()

    /// - Parameters:
    ///   - hours: How far ahead the guide goes.
    ///   - tint: The colour of what is on now.
    ///   - playing: The id of the channel to highlight and to open the guide at.
    ///   - load: The channels with what they air between the two times.
    ///   - onSelect: A click on a programme that is on now.
    public init(search: LiveSearch, hours: Int = 6, tint: Color = .blue, playing: String? = nil,
                load: @escaping (_ start: Date, _ end: Date) async throws -> [GuideChannel],
                onSelect: @escaping (GuideChannel, GuideProgram) -> Void) {
        self.search = search
        self.hours = hours
        self.tint = tint
        self.playing = playing
        self.load = load
        self.onSelect = onSelect
    }

    /// The half hour that is running: the guide's left edge.
    private var start: Date {
        Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 1800).rounded(.down) * 1800)
    }

    private var filtered: [GuideChannel] {
        let query = search.text.trimmingCharacters(in: .whitespaces)
        guard let channels, !query.isEmpty else { return channels ?? [] }
        return channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(query) || channel.programs.contains {
                $0.title.localizedCaseInsensitiveContains(query) || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
    }

    public var body: some View {
        Group {
            if channels != nil {
                if !filtered.isEmpty {
                    GuideGrid(channels: filtered, start: start, hours: hours, now: now, tint: tint, playing: playing, onSelect: onSelect)
                } else if search.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Nothing On Right Now", systemImage: "tv")
                } else {
                    ContentUnavailableView.search(text: search.text)
                }
            } else if let error {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: start) {
            do {
                channels = try await load(start, start.addingTimeInterval(Double(hours) * 3600))
                error = nil
            } catch {
                // A guide that is already up stays up when a later half hour's listings fail.
                if channels == nil, !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

/// The grid itself: one scroll view for both directions, with the times pinned to its top (a pinned
/// section header) and the channel column pinned to its leading edge (moved back by however far the
/// row has scrolled).
struct GuideGrid: View {
    let channels: [GuideChannel]
    let start: Date
    let hours: Int
    let now: Date
    let tint: Color
    let playing: String?
    let onSelect: (GuideChannel, GuideProgram) -> Void

    #if os(macOS)
    private let minute: CGFloat = 6, side: CGFloat = 150, row: CGFloat = 68
    #else
    private let minute: CGFloat = 5, side: CGFloat = 96, row: CGFloat = 64
    #endif
    private let ruler: CGFloat = 34

    private var end: Date { start.addingTimeInterval(Double(hours) * 3600) }
    private var width: CGFloat { CGFloat(hours) * 60 * minute }
    /// Where a time is along the row, in points from the guide's left edge.
    private func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(start) / 60) * minute }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(channels) { channel in
                                HStack(spacing: 0) {
                                    channelCell(channel).pinnedLeading().zIndex(1)
                                    programs(channel)
                                }
                            }
                        } header: {
                            times
                        }
                    }
                    .frame(width: side + width, alignment: .leading)
                    // A guide smaller than the window starts at its top left corner, not in its middle.
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                }
                // The guide opens at the channel that is playing: its row half way down, the guide's left
                // edge (now) where it was.
                .onAppear {
                    guard let playing, channels.contains(where: { $0.id == playing }) else { return }
                    DispatchQueue.main.async { proxy.scrollTo(playing, anchor: UnitPoint(x: 0, y: 0.5)) }
                }
            }
        }
    }

    private var times: some View {
        HStack(spacing: 0) {
            Text("Today").font(.caption.bold()).foregroundStyle(.secondary)
                .frame(width: side, height: ruler)
                .barBackground()
                .pinnedLeading().zIndex(1)
            HStack(spacing: 0) {
                ForEach(0..<hours * 2, id: \.self) { slot in
                    Text(start.addingTimeInterval(Double(slot) * 1800), style: .time)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .frame(width: 30 * minute, height: ruler, alignment: .leading)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Circle().fill(.red).frame(width: 8, height: 8).offset(x: x(now) - 4)
            }
        }
        .barBackground()
    }

    private func channelCell(_ channel: GuideChannel) -> some View {
        // The services' logos are drawn for a dark page, so the plate is dark in light mode too.
        ZStack {
            Color(white: 0.13)
            if let logo = channel.logo {
                ChannelLogo(url: logo).padding(.horizontal, 14).padding(.vertical, 12)
            } else {
                Text(channel.name).font(.caption.bold()).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 8)
            }
        }
        .frame(width: side - 4, height: row - 4)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if channel.id == playing { RoundedRectangle(cornerRadius: 8).strokeBorder(tint, lineWidth: 3) }
        }
        .frame(width: side, height: row)
        .background(.background)
        .help(channel.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(channel.name)
        .accessibilityAddTraits(channel.id == playing ? .isSelected : [])
    }

    /// A channel's programmes, each from its start to its end (cut off at the guide's edges). On the
    /// channel that is playing, what is on now is filled in and outlined.
    private func programs(_ channel: GuideChannel) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(channel.programs.filter { $0.end > start && $0.start < end }) { program in
                let from = max(x(program.start), 0), to = min(x(program.end), width)
                let airing = program.start <= now && now < program.end
                let highlighted = airing && channel.id == playing
                Button {
                    onSelect(channel, program)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.title).font(.callout.weight(.semibold)).lineLimit(1)
                        if let subtitle = program.subtitle, subtitle != program.title {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text("\(program.start, style: .time) – \(program.end, style: .time)")
                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: max(to - from - 4, 0), height: row - 4, alignment: .leading)
                    .background(airing ? AnyShapeStyle(tint.opacity(highlighted ? 0.6 : 0.3)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if highlighted { RoundedRectangle(cornerRadius: 8).strokeBorder(tint, lineWidth: 3) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!airing)
                .help(airing ? "Watch \(program.title) on \(channel.name)" : program.title)
                .accessibilityAddTraits(highlighted ? .isSelected : [])
                .offset(x: from + 2, y: 2)
            }
            if now >= start && now < end {
                Rectangle().fill(.red).frame(width: 2, height: row).offset(x: x(now) - 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: row, alignment: .topLeading)
    }
}

/// A channel's logo, fitted. An image server can answer a size it has not made yet with something that
/// is not an image (img.hulu.com: 200 "Submitted for processing", which URLCache would keep for 30 days),
/// so that answer is dropped and the logo asked for again until the image is there.
public struct ChannelLogo: View {
    let url: URL?
    @State private var image: PlatformImage?

    public init(url: URL?) { self.url = url }

    public var body: some View {
        Group {
            if let image {
                Image(platformImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "tv")
            }
        }
        .task(id: url) {
            guard let url else { return }
            let request = URLRequest(url: url)
            for _ in 0..<5 {
                if let (data, _) = try? await URLSession.shared.data(for: request) {
                    if let loaded = PlatformImage(data: data) { image = loaded; return }
                    URLCache.shared.removeCachedResponse(for: request)
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private extension View {
    /// Stays at the scroll view's leading edge while what it is part of scrolls sideways.
    func pinnedLeading() -> some View {
        visualEffect { content, geometry in
            content.offset(x: max(0, -geometry.frame(in: .scrollView).minX))
        }
    }
}
