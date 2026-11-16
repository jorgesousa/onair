import Foundation
import ImageIO
import SwiftUI

/// Channel logos, kept in memory once seen. A lazy list drops rows that scroll away and
/// rebuilds them on the way back; without this every logo downloads and pops in again.
@MainActor
final class LogoCache {
    static let shared = LogoCache()
    private final class Box { let image: CGImage; init(_ i: CGImage) { image = i } }
    private let cache = NSCache<NSURL, Box>()
    private var inFlight: [URL: Task<CGImage?, Never>] = [:]

    init() { cache.countLimit = 600 }

    func cached(_ url: URL) -> CGImage? { cache.object(forKey: url as NSURL)?.image }

    func load(_ url: URL, pixelHeight: Int = 64) async -> CGImage? {
        if let hit = cached(url) { return hit }
        if let running = inFlight[url] { return await running.value }
        let task = Task<CGImage?, Never>.detached(priority: .utility) {
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            // Decoded small, once: a logo is drawn 22 pt high.
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceThumbnailMaxPixelSize: pixelHeight * 3,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(Box(image), forKey: url as NSURL) }
        return image
    }
}

/// A channel logo from the cache: there at once when seen before, faded in the first time.
struct CachedLogo: View {
    let url: URL?
    @State private var image: CGImage?

    init(url: URL?) {
        self.url = url
        var hit: CGImage?
        if let url { hit = MainActor.assumeIsolated { LogoCache.shared.cached(url) } }
        _image = State(initialValue: hit)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 3).resizable().scaledToFit().transition(.opacity)
            }
        }
        .task(id: url) {
            guard image == nil, let url else { return }
            let loaded = await LogoCache.shared.load(url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
