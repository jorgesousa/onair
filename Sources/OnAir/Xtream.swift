import Foundation

/// One Xtream Codes account. Live, movies, series and the short programme guide.
struct XtreamAccount: Hashable {
    let base: String
    let username: String
    let password: String

    init(server: String, username: String, password: String) {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        base = s; self.username = username; self.password = password
    }

    /// A `get.php?username=…&password=…` playlist link is an Xtream account in disguise.
    init?(playlistURL: URL) {
        guard playlistURL.lastPathComponent == "get.php",
              let c = URLComponents(url: playlistURL, resolvingAgainstBaseURL: false),
              let u = c.queryItems?.first(where: { $0.name == "username" })?.value,
              let p = c.queryItems?.first(where: { $0.name == "password" })?.value,
              let scheme = c.scheme, let host = c.host else { return nil }
        self.init(server: "\(scheme)://\(host)" + (c.port.map { ":\($0)" } ?? ""), username: u, password: p)
    }

    static func normalized(_ server: String) -> String { XtreamAccount(server: server, username: "", password: "").base }

    // MARK: API

    private func api(_ action: String, _ extra: [URLQueryItem] = []) throws -> URL {
        var c = URLComponents(string: base + "/player_api.php")
        c?.queryItems = [.init(name: "username", value: username),
                         .init(name: "password", value: password),
                         .init(name: "action", value: action)] + extra
        guard let u = c?.url else { throw URLError(.badURL) }
        return u
    }

    private func get<T: Decodable>(_ type: T.Type, _ action: String, _ extra: [URLQueryItem] = []) async throws -> T {
        let data = try await Net.data(try api(action, extra))
        if let auth = try? JSONDecoder().decode(AuthOnly.self, from: data), auth.user_info?.auth == 0 {
            throw NSError(domain: "OnAir", code: 401, userInfo: [NSLocalizedDescriptionKey:
                "The server refused this account. It may be suspended, expired, or blocked for a few minutes."])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func categories(_ action: String) async -> [String: String] {
        let cats = (try? await get([Category].self, action)) ?? []
        return Dictionary(cats.map { ($0.category_id.string, $0.category_name) }, uniquingKeysWith: { a, _ in a })
    }

    private func path(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s }
    private func streamURL(_ kind: String, _ id: String, _ ext: String) -> URL? {
        URL(string: "\(base)/\(kind)/\(path(username))/\(path(password))/\(id).\(ext)")
    }

    func live() async throws -> [Channel] {
        async let names = categories("get_live_categories")
        let streams = try await get([Stream].self, "get_live_streams")
        let n = await names
        return streams.compactMap { s in
            guard let id = s.stream_id?.string, let url = streamURL("live", id, "m3u8") else { return nil }
            return Channel(name: s.name ?? "Channel \(id)", group: n[s.category_id?.string ?? ""] ?? "Uncategorised",
                           logo: s.stream_icon.flatMap(URL.init(string:)), url: url,
                           epgID: s.epg_channel_id.flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    /// The account's full programme guide (XMLTV).
    var xmltvURL: URL? {
        var c = URLComponents(string: base + "/xmltv.php")
        c?.queryItems = [.init(name: "username", value: username), .init(name: "password", value: password)]
        return c?.url
    }

    func movies() async throws -> [Channel] {
        async let names = categories("get_vod_categories")
        let streams = try await get([Stream].self, "get_vod_streams")
        let n = await names
        return streams.compactMap { s in
            guard let id = s.stream_id?.string,
                  let url = streamURL("movie", id, s.container_extension ?? "mp4") else { return nil }
            return Channel(name: s.name ?? "Film \(id)", group: n[s.category_id?.string ?? ""] ?? "Uncategorised",
                           logo: s.stream_icon.flatMap(URL.init(string:)), url: url)
        }
    }

    func series() async throws -> [Series] {
        async let names = categories("get_series_categories")
        let list = try await get([SeriesDTO].self, "get_series")
        let n = await names
        return list.compactMap { s in
            guard let id = s.series_id?.int else { return nil }
            return Series(id: id, name: s.name ?? "Series \(id)", group: n[s.category_id?.string ?? ""] ?? "Uncategorised",
                          cover: s.cover.flatMap(URL.init(string:)), plot: s.plot)
        }
    }

    func episodes(of series: Int) async throws -> [Episode] {
        let info = try await get(SeriesInfo.self, "get_series_info", [.init(name: "series_id", value: String(series))])
        return (info.episodes ?? [:]).flatMap { season, eps in
            eps.compactMap { e -> Episode? in
                guard let id = e.id?.string, let url = streamURL("series", id, e.container_extension ?? "mp4") else { return nil }
                let num = e.episode_num?.int ?? 0
                return Episode(id: id, season: e.season?.int ?? Int(season) ?? 0, number: num,
                               title: e.title ?? "Episode \(num)", url: url)
            }
        }
        .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
    }

    /// What is on now and next. Titles come base64-encoded.
    func guide(streamID: Int) async throws -> [Programme] {
        let r = try await get(ShortEPG.self, "get_short_epg", [.init(name: "stream_id", value: String(streamID)),
                                                               .init(name: "limit", value: "3")])
        return (r.epg_listings ?? []).compactMap { l in
            guard let s = l.start_timestamp?.int, let e = l.stop_timestamp?.int else { return nil }
            let raw = l.title ?? ""
            let title = Data(base64Encoded: raw).flatMap { String(data: $0, encoding: .utf8) } ?? raw
            return Programme(title: title, start: Date(timeIntervalSince1970: TimeInterval(s)),
                             end: Date(timeIntervalSince1970: TimeInterval(e)))
        }
        .filter { $0.end > .now }
    }

    // MARK: DTOs (Xtream panels mix numbers and strings freely)

    private struct AuthOnly: Decodable { struct U: Decodable { let auth: Int? }; let user_info: U? }
    private struct Category: Decodable { let category_id: Flex; let category_name: String }
    private struct Stream: Decodable {
        let name: String?; let stream_id: Flex?; let stream_icon: String?
        let category_id: Flex?; let container_extension: String?; let epg_channel_id: String?
    }
    private struct SeriesDTO: Decodable {
        let series_id: Flex?; let name: String?; let cover: String?; let plot: String?; let category_id: Flex?
    }
    private struct SeriesInfo: Decodable {
        struct E: Decodable {
            let id: Flex?; let episode_num: Flex?; let season: Flex?; let title: String?; let container_extension: String?
        }
        let episodes: [String: [E]]?
        enum CodingKeys: String, CodingKey { case episodes }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            episodes = try? c.decode([String: [E]].self, forKey: .episodes)   // some panels send [] when empty
        }
    }
    private struct ShortEPG: Decodable {
        struct L: Decodable { let title: String?; let start_timestamp: Flex?; let stop_timestamp: Flex? }
        let epg_listings: [L]?
    }
}

/// A JSON value that may be a number or a string.
struct Flex: Decodable, Hashable {
    let string: String
    var int: Int? { Int(string) }
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let i = try? c.decode(Int.self) { string = String(i) }
        else if let x = try? c.decode(Double.self) { string = String(Int(x)) }
        else { string = try c.decode(String.self) }
    }
}

enum Net {
    static func data(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue("OnAir/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw NSError(domain: "OnAir", code: h.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "The server answered with error \(h.statusCode)."])
        }
        return data
    }
}
