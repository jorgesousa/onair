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
