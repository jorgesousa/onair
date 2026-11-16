import Foundation

/// The programme guide, saved after it's read: a big guide takes a while to read on an older
/// iPad, so the next launch shows what's on at once and refreshes quietly behind it.
enum GuideCache {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Guide", isDirectory: true)
    }

    /// Only what's on now and in the next 24 hours: all the app ever shows.
    static func trimmed(_ guide: [String: [Programme]], around now: Date = .now) -> [String: [Programme]] {
        let horizon = now.addingTimeInterval(24 * 3600)
        var out: [String: [Programme]] = [:]
        for (id, list) in guide {
            let kept = list.filter { $0.end > now && $0.start < horizon }
            if !kept.isEmpty { out[id] = kept }
        }
        return out
    }

    static func save(_ guide: [String: [Programme]], key: String, in dir: URL = directory) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(guide).write(to: file(key, dir), options: .atomic)
    }

    static func load(key: String, in dir: URL = directory) -> [String: [Programme]]? {
        guard let d = try? Data(contentsOf: file(key, dir)) else { return nil }
        return try? JSONDecoder().decode([String: [Programme]].self, from: d)
    }

    /// One file per account, named by a hash (no server or username in file names).
    private static func file(_ key: String, _ dir: URL) -> URL {
        var h: UInt64 = 1469598103934665603
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return dir.appendingPathComponent(String(h, radix: 16) + ".json")
    }
}
