import Foundation
import Observation

@MainActor @Observable
final class Store {
    var playlists: [Playlist] = [] { didSet { save() } }
    var selectedPlaylistID: UUID? { didSet { defaults.set(selectedPlaylistID?.uuidString, forKey: "selected") } }
    var favorites: Set<String> = [] { didSet { defaults.set(Array(favorites), forKey: "favorites") } }
    var recents: [String] = [] { didSet { defaults.set(recents, forKey: "recents") } }

    var library: Library = .live
    var channels: [Channel] = []
    var movies: [Channel] = []
    var series: [Series] = []
    private var loaded: Set<Library> = []

    /// What's on, by lower-cased XMLTV channel id.
    var guide: [String: [Programme]] = [:]
    private var guideLoadedAt: Date?

    var isLoading = false
    var error: String?

    private let defaults = UserDefaults.standard

    init() {
        // Carry over lists, favourites and recents from the app's first name, SousaTV.
        if defaults.data(forKey: "playlists") == nil, let old = UserDefaults(suiteName: "com.sousalab.sousatv") {
            for k in ["playlists", "favorites", "recents", "selected"] {
                if let v = old.object(forKey: k) { defaults.set(v, forKey: k) }
            }
        }
        if let d = defaults.data(forKey: "playlists"),
           let p = try? JSONDecoder().decode([Playlist].self, from: d) { playlists = p }
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        recents = defaults.stringArray(forKey: "recents") ?? []
        selectedPlaylistID = defaults.string(forKey: "selected").flatMap(UUID.init(uuidString:)) ?? playlists.first?.id
    }

    var selectedPlaylist: Playlist? { playlists.first { $0.id == selectedPlaylistID } }

    /// The Xtream account behind the selected playlist, if any. Unlocks movies, series and the guide.
    var account: XtreamAccount? {
        guard let p = selectedPlaylist else { return nil }
        switch p.source {
        case .xtream(let server, let username):
            return XtreamAccount(server: server, username: username, password: Keychain.get(p.id.uuidString) ?? "")
        case .m3u(let location):
            return URL(string: location).flatMap(XtreamAccount.init(playlistURL:))
        }
    }

    /// Items of the current library as rows (series are shown by their cover).
    var items: [Channel] {
        switch library {
        case .live: channels
        case .movies: movies
        case .series: series.map { Channel(name: $0.name, group: $0.group, logo: $0.cover,
                                           url: URL(string: "series:\($0.id)")!) }
        }
    }

    var groups: [String] {
        var seen = Set<String>(); var out: [String] = []
        for c in items where seen.insert(c.group).inserted { out.append(c.group) }
        return out
    }

    func items(for item: SidebarItem, search: String) -> [Channel] {
        let all = items
        let base: [Channel]
        switch item {
        case .all: base = all
        case .favorites: base = all.filter { favorites.contains($0.id) }
        case .recents:
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            base = recents.compactMap { byID[$0] }
        case .group(let g): base = all.filter { $0.group == g }
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    func toggleFavorite(_ c: Channel) {
        if favorites.contains(c.id) { favorites.remove(c.id) } else { favorites.insert(c.id) }
    }

    func markPlayed(_ c: Channel) {
        recents.removeAll { $0 == c.id }
        recents.insert(c.id, at: 0)
        if recents.count > 50 { recents.removeLast(recents.count - 50) }
    }

    func add(_ p: Playlist, password: String?) {
        if let password { Keychain.set(password, for: p.id.uuidString) }
        playlists.append(p)
        selectedPlaylistID = p.id
    }

    func remove(_ p: Playlist) {
        Keychain.delete(p.id.uuidString)
        playlists.removeAll { $0.id == p.id }
        if selectedPlaylistID == p.id { selectedPlaylistID = playlists.first?.id }
    }

    /// Drops everything loaded for the previous playlist.
    func reset() {
        channels = []; movies = []; series = []; loaded = []; error = nil
        guide = [:]; guideLoadedAt = nil
        library = .live
    }

    func reload() async {
        loaded.remove(library)
        await loadIfNeeded()
    }

    func loadIfNeeded() async {
        guard let p = selectedPlaylist, !loaded.contains(library), !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        let lib = library
        do {
            switch lib {
            case .live:
                if let a = account, case .xtream = p.source {
                    channels = try await a.live()
                } else if case .m3u(let location) = p.source {
                    let url = location.hasPrefix("/") ? URL(fileURLWithPath: location) : URL(string: location)
                    guard let url else { throw URLError(.badURL) }
                    channels = M3UParser.parse(String(decoding: try await Net.data(url), as: UTF8.self), base: url)
                }
                if channels.isEmpty { error = "This playlist has no channels." }
                Task { await loadGuide() }
            case .movies:
                guard let a = account else { throw Self.needsXtream }
                movies = try await a.movies()
                if movies.isEmpty { error = "This account has no films." }
            case .series:
                guard let a = account else { throw Self.needsXtream }
                series = try await a.series()
                if series.isEmpty { error = "This account has no series." }
            }
            loaded.insert(lib)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func nowPlaying(_ c: Channel, at date: Date = .now) -> Programme? {
        guard let id = c.epgID?.lowercased() else { return nil }
        return guide[id]?.first { $0.start <= date && $0.end > date }
    }

    /// Downloads the account's XMLTV guide at most every 3 hours.
    func loadGuide(force: Bool = false) async {
        guard let url = account?.xmltvURL else { return }
        if !force, let t = guideLoadedAt, t.timeIntervalSinceNow > -3 * 3600 { return }
        guideLoadedAt = .now
        guard let data = try? await Net.data(url) else { guideLoadedAt = nil; return }
        let parsed = await Task.detached(priority: .utility) { XMLTV.parse(data) }.value
        if !parsed.isEmpty { guide = parsed }
    }

    private static let needsXtream = NSError(domain: "OnAir", code: 0, userInfo: [NSLocalizedDescriptionKey:
        "Films and series need an Xtream Codes account."])

    private func save() {
        if let d = try? JSONEncoder().encode(playlists) { defaults.set(d, forKey: "playlists") }
    }
}
