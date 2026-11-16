import Foundation

struct Channel: Identifiable, Hashable, Codable {
    var id: String { url.absoluteString }
    let name: String
    let group: String
    let logo: URL?
    let url: URL
    /// XMLTV channel id (tvg-id / epg_channel_id), used to find what is on.
    var epgID: String? = nil
    /// HTTP headers some streams require (from the list's http-user-agent / http-referrer).
    var headers: [String: String]? = nil
    /// Xtream stream id, used for the programme guide.
    var streamID: Int? { Int((url.lastPathComponent as NSString).deletingPathExtension) }
}

struct Series: Identifiable, Hashable {
    let id: Int
    let name: String
    let group: String
    let cover: URL?
    let plot: String?
}

struct Episode: Identifiable, Hashable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let url: URL
}

struct Programme: Hashable, Sendable, Codable {
    let title: String
    let start: Date
    let end: Date

    func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        return total > 0 ? min(1, max(0, date.timeIntervalSince(start) / total)) : 0
    }

    var span: String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

enum PlaylistSource: Codable, Hashable {
    case m3u(location: String)                 // http(s) URL or file path
    case xtream(server: String, username: String) // password kept in Keychain
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var source: PlaylistSource
}

enum Library: String, CaseIterable, Identifiable {
    case live = "Live", movies = "Films", series = "Series"
    var id: String { rawValue }
}

enum SidebarItem: Hashable {
    case all
    case favorites
    case recents
    case group(String)
}

extension Channel {
    /// Xtream-style stream links (/[live/]user/pass/id) carry the account; use it to ask the
    /// provider about connections.
    var xtreamAccount: XtreamAccount? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var parts = url.path.split(separator: "/").map(String.init)
        if parts.first == "live" { parts.removeFirst() }
        guard parts.count == 3, Int((parts[2] as NSString).deletingPathExtension) != nil else { return nil }
        let server = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        return XtreamAccount(server: server, username: parts[0], password: parts[1])
    }
}

extension Channel {
    /// "PT: RTP 1" → "RTP 1". Country prefixes are noise once you've picked a list.
    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        var out = n
        if let r = out.range(of: #"^[A-Z]{2,4}\s*[:|\-]\s*"#, options: .regularExpression) { out = String(out[r.upperBound...]) }
        // Trailing tags lists add for machines: "(1080p)", "[Not 24/7]", "[Geo-blocked]".
        out = out.replacingOccurrences(of: #"(\s*(\(\d{3,4}[pi]\)|\[[^\]]*\]))+\s*$"#, with: "", options: .regularExpression)
        return out.isEmpty ? n : out
    }
}
