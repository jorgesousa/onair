import Foundation
import Testing
@testable import OnAir

@MainActor @Test func releaseWithNothingPlayingClearsState() {
    let p = PlaybackController()
    p.release()
    #expect(p.current == nil)
    #expect(p.isTuning == false)
    #expect(p.lastStopped == nil)
}

@MainActor @Test func releaseRemembersTheChannelAndFreesThePlayer() {
    let p = PlaybackController()
    let c = Channel(name: "One", group: "G", logo: nil, url: URL(string: "http://127.0.0.1:9/1.m3u8")!)
    p.play(c)
    p.release()
    #expect(p.current == nil)
    #expect(p.isTuning == false)
    #expect(p.failed == nil)
    #expect(p.player.currentItem == nil)
    #expect(p.lastStopped == c)
}
