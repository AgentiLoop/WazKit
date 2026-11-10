//
//  Tiles.swift
//  WazKit
//
//  The artwork tiles the browse rows and search grids are made of. The apps' items say what to
//  show (Tile); the card draws it and takes the click and the context menu from the app.
//

import SwiftUI

/// What a card shows about an item; the apps' Item types conform.
public protocol Tile {
    var title: String { get }
    var subtitle: String? { get }
    var description: String? { get }
    /// Shows a LIVE badge.
    var isLive: Bool { get }
    /// Artwork at a pixel size; nil draws the title on a plain tile.
    func artwork(width: Int, height: Int) -> URL?
}

/// A 16:9 (or poster) tile with the title and subtitle under it.
public struct TileCard<Menu: View>: View {
    let tile: any Tile
    let vertical: Bool
    let tint: Color
    let action: () -> Void
    let menu: () -> Menu

    /// - Parameters:
    ///   - vertical: Poster-shaped (160×240) instead of 16:9 (240×135).
    ///   - tint: The second color of the gradient behind a tile with no artwork.
    ///   - action: What a click does.
    ///   - menu: The context menu's items.
    public init(_ tile: any Tile, vertical: Bool = false, tint: Color = .blue,
                action: @escaping () -> Void, @ViewBuilder menu: @escaping () -> Menu) {
        self.tile = tile
        self.vertical = vertical
        self.tint = tint
        self.action = action
        self.menu = menu
    }

    private var size: CGSize { vertical ? CGSize(width: 160, height: 240) : CGSize(width: 240, height: 135) }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Artwork(url: tile.artwork(width: Int(size.width) * 2, height: Int(size.height) * 2), title: tile.title, tint: tint)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if tile.isLive {
                        Text("LIVE").font(.caption2.bold()).padding(4).background(.red, in: RoundedRectangle(cornerRadius: 3)).padding(6)
                    }
                }
                Text(tile.title).font(.callout.bold()).lineLimit(1)
                if let subtitle = tile.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: size.width)
        }
        .buttonStyle(.plain)
        .help(tile.description ?? tile.title)
        .contextMenu(menuItems: menu)
    }
}

#if os(macOS)
public typealias PlatformImage = NSImage
#else
public typealias PlatformImage = UIImage
#endif

extension Image {
    /// An image from an NSImage on the Mac, a UIImage on iOS.
    public init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

/// A tile's image, cached. Image servers can answer an error while they render a size they haven't
/// made yet (and AsyncImage never asks again), so this retries until the image is ready, and reloads
/// when a tile comes back on screen. Items with no artwork get their name on a plain tile.
public struct Artwork: View {
    let url: URL?
    let title: String
    let tint: Color
    @State private var image: PlatformImage?

    private static let cache = NSCache<NSURL, PlatformImage>()

    public init(url: URL?, title: String, tint: Color = .blue) {
        self.url = url
        self.title = title
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if url == nil {
                LinearGradient(colors: [.indigo.opacity(0.8), tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(title).font(.title3.bold()).multilineTextAlignment(.center).padding(12)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
            image = nil
            for attempt in 0..<6 {
                if attempt > 0 { try? await Task.sleep(for: .seconds(attempt)) }
                guard !Task.isCancelled else { return }
                if let (data, _) = try? await URLSession.shared.data(from: url), let loaded = PlatformImage(data: data) {
                    Self.cache.setObject(loaded, forKey: url as NSURL)
                    image = loaded
                    return
                }
            }
        }
    }
}
