import Foundation
import Testing
@testable import OnAir

/// Home (a Dispatcharr playlist): one TV, several screens.
@Suite struct FollowTests {
    let home = Playlist(name: "Home", source: .m3u(location: "http://192.168.1.67:9191/output/m3u?output_format=hls"))
    let personal = Playlist(name: "Personal", source: .m3u(location: "http://example.test:8080/get.php?username=u&password=p&type=m3u_plus"))

    @Test func onlyADispatcharrPlaylistIsShared() {
        #expect(Follow.isShared(home))
        #expect(!Follow.isShared(personal))
        #expect(!Follow.isShared(nil))
    }

    @Test func theSameStreamHasTheSameKeyOnEveryDevice() {
        let mac = Channel(name: "RTP 1", group: "PT", logo: nil, url: URL(string: "http://127.0.0.1:9191/proxy/ts/stream/73e7?output_format=hls")!)
        let phone = Channel(name: "RTP 1", group: "PT", logo: nil, url: URL(string: "http://192.168.1.67:9191/proxy/ts/stream/73e7?output_format=hls")!)
        #expect(Follow.key(mac) == Follow.key(phone))
        #expect(Follow.key(mac) == "/proxy/ts/stream/73e7")
    }

    @Test func aScreenFollowsAnotherScreensNewerChange() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let m = Follow.Message(from: "phone", key: "/b", at: t0.addingTimeInterval(5))
        #expect(Follow.adopt(m, me: "mac", shared: true, current: "/a", lastChange: t0))
        // Its own echo, a channel already on, an older change, or not on Home: stay.
        #expect(!Follow.adopt(m, me: "phone", shared: true, current: "/a", lastChange: t0))
        #expect(!Follow.adopt(m, me: "mac", shared: true, current: "/b", lastChange: t0))
        #expect(!Follow.adopt(m, me: "mac", shared: true, current: "/a", lastChange: t0.addingTimeInterval(9)))
        #expect(!Follow.adopt(m, me: "mac", shared: false, current: "/a", lastChange: t0))
        #expect(Follow.adopt(m, me: "mac", shared: true, current: nil, lastChange: nil))
    }

    @Test func messagesSurviveTheWire() throws {
        let m = Follow.Message(from: "a", key: "/k", at: Date(timeIntervalSince1970: 1234.5), ask: true)
        #expect(try Follow.decode(Follow.encode(m)) == m)
    }
}

@Suite struct PatienceTests {
    @Test func dispatcharrChannelsGetLongerToShowTheFirstPicture() {
        let home = Channel(name: "RTP 1", group: "PT", logo: nil, url: URL(string: "http://192.168.1.67:9191/proxy/ts/stream/73e7?output_format=hls")!)
        let direct = Channel(name: "RTP 1", group: "PT", logo: nil, url: URL(string: "http://example.test:8080/live/u/p/1.m3u8")!)
        #expect(Patience.firstPicture(home) == 40)
        #expect(Patience.firstPicture(direct) == 15)
        #expect(Patience.firstPicture(nil) == 15)
    }
}
