import Foundation

/// Home: one TV, several screens. The provider allows one connection, so every screen at home
/// watches the same channel through Dispatcharr; changing channel on one changes it on all.
/// Only a Dispatcharr playlist follows — the others stay independent on each device.
enum Follow {
    /// One screen telling the others what's on (or, with `ask`, asking them).
    struct Message: Codable, Equatable {
        let from: String
        let key: String
        let at: Date
        var ask = false
    }

    /// A playlist served by Dispatcharr (its address ends in /output/m3u), whatever it's called.
    static func isShared(_ p: Playlist?) -> Bool {
        guard case .m3u(let location)? = p?.source, let url = URL(string: location) else { return false }
        return url.path.hasSuffix("/output/m3u")
    }

    /// The stream, without the address each device reaches Dispatcharr by
    /// (127.0.0.1 on the Mac, the Mac's network address elsewhere).
    static func key(_ c: Channel) -> String { c.url.path }

    /// Switch to what another screen just put on? Only a newer change, from someone else,
    /// to a different channel, while this screen is on Home.
    static func adopt(_ m: Message, me: String, shared: Bool, current: String?, lastChange: Date?) -> Bool {
        guard shared, m.from != me, !m.key.isEmpty, m.key != current else { return false }
        return lastChange.map { m.at > $0 } ?? true
    }

    static func encode(_ m: Message) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        return try e.encode(m) + Data("\n".utf8)
    }

    static func decode(_ d: Data) throws -> Message {
        let e = JSONDecoder(); e.dateDecodingStrategy = .secondsSince1970
        let line = d.split(separator: UInt8(ascii: "\n")).first ?? d[...]
        return try e.decode(Message.self, from: Data(line))
    }
}

/// How long a stream gets to show its first picture before it's started again.
/// Dispatcharr builds HLS from scratch (a few 4-second segments, ~15 s), so restarting at 15 s
/// would loop forever; its channels get 40 s. Everything else keeps the usual 15 s.
enum Patience {
    static func firstPicture(_ c: Channel?) -> TimeInterval {
        guard let c else { return 15 }
        return c.url.path.hasPrefix("/proxy/ts/stream/") ? 40 : 15
    }
}
