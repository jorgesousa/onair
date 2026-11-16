import Foundation
import Testing
@testable import OnAir

@Test func m3uParsesNameGroupAndURL() {
    let text = "#EXTM3U\n#EXTINF:-1 tvg-id=\"a\" group-title=\"Sport\",Sport TV\nhttp://x/1.ts"
    let channels = M3UParser.parse(text, base: nil)
    #expect(channels.count == 1)
    #expect(channels.first?.name == "Sport TV")
    #expect(channels.first?.group == "Sport")
    #expect(channels.first?.epgID == "a")
    #expect(channels.first?.url == URL(string: "http://x/1.ts"))
}

@Test func displayNameDropsCountryPrefixAndTags() {
    let c = Channel(name: "PT: RTP 1 (1080p)", group: "", logo: nil, url: URL(string: "http://x/1")!)
    #expect(c.displayName == "RTP 1")
}

@Test func aPlaylistCanSayWhereItsGuideIs() {
    let base = URL(string: "http://192.168.1.67:9191/output/m3u")!
    let dispatcharr = "#EXTM3U x-tvg-url=\"http://192.168.1.67:9191/output/epg\" url-tvg=\"http://192.168.1.67:9191/output/epg\"\n#EXTINF:-1,One\nhttp://x/1\n"
    #expect(M3UParser.guideURL(in: dispatcharr, base: base) == URL(string: "http://192.168.1.67:9191/output/epg"))
    // Several guides, comma-separated: the first. A relative one resolves against the list.
    #expect(M3UParser.guideURL(in: "#EXTM3U url-tvg=\"epg.xml,http://b/epg.xml\"\n", base: base) == URL(string: "http://192.168.1.67:9191/output/epg.xml"))
    #expect(M3UParser.guideURL(in: "#EXTM3U\n#EXTINF:-1,One\nhttp://x/1\n", base: base) == nil)
}
