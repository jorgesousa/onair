import Foundation

/// Public playlists of channels that are free to watch, from two open projects that only list
/// legal, free-to-air or publicly offered streams. ONAIR still ships no channels: these are links
/// to lists other people maintain, added only when you pick one.
struct FreeList: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let source: String
    let url: String
}

enum FreeLists {
    private static let org = "https://iptv-org.github.io/iptv/"

    static let all: [FreeList] = [
        .init(id: "pt", name: "Portugal", detail: "Free channels from Portugal", source: "iptv-org", url: org + "countries/pt.m3u"),
        .init(id: "por", name: "In Portuguese", detail: "Portugal, Brazil, Angola and more", source: "iptv-org", url: org + "languages/por.m3u"),
        .init(id: "freetv", name: "Free-TV", detail: "Hand-checked free-to-air channels, worldwide", source: "Free-TV", url: "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8"),
        .init(id: "news", name: "News", detail: "News channels, worldwide", source: "iptv-org", url: org + "categories/news.m3u"),
        .init(id: "sports", name: "Sports", detail: "Sports channels, worldwide", source: "iptv-org", url: org + "categories/sports.m3u"),
        .init(id: "movies", name: "Movies", detail: "Film channels, worldwide", source: "iptv-org", url: org + "categories/movies.m3u"),
        .init(id: "music", name: "Music", detail: "Music channels, worldwide", source: "iptv-org", url: org + "categories/music.m3u"),
        .init(id: "kids", name: "Kids", detail: "Children's channels, worldwide", source: "iptv-org", url: org + "categories/kids.m3u"),
        .init(id: "docs", name: "Documentary", detail: "Documentary channels, worldwide", source: "iptv-org", url: org + "categories/documentary.m3u"),
        .init(id: "everything", name: "Everything", detail: "All of iptv-org: over 11,000 channels", source: "iptv-org", url: org + "index.m3u"),
    ]
}
