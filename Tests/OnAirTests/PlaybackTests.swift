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

/// Between two attempts (nothing loaded, a channel still picked) the card must stay up.
@MainActor @Test(.timeLimit(.minutes(1))) func tuningStaysOnBetweenAttempts() async throws {
    let server = try RefusingServer(status: "503 Service Unavailable")
    let c = Channel(name: "Busy", group: "G", logo: nil,
                    url: URL(string: "http://127.0.0.1:\(server.port)/live/u/p/7.m3u8")!)
    let p = PlaybackController()
    p.play(c)
    var dropped = 0
    let end = Date.now.addingTimeInterval(10)
    while Date.now < end {
        try? await Task.sleep(for: .milliseconds(50))
        if !p.isTuning, p.failed == nil { dropped += 1 }
    }
    #expect(server.hits >= 2)        // it did retry
    #expect(dropped == 0)            // and the card never went away
    p.release()
}
