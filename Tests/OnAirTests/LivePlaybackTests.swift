import Foundation
import Testing
@testable import OnAir

/// Plays a real HLS test stream through the shared PlaybackController. Needs the network;
/// runs only with ONAIR_LIVE=1 so the normal suite stays offline.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ONAIR_LIVE"] == "1"))
func livePlaybackReachesPlaying() async throws {
    let p = PlaybackController()
    let c = Channel(name: "Mux", group: "Test", logo: nil,
                    url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!)
    p.play(c)
    for _ in 0..<60 where p.player.timeControlStatus != .playing {
        try await Task.sleep(for: .milliseconds(250))
    }
    #expect(p.player.timeControlStatus == .playing)
    #expect(p.isTuning == false)
    p.release()
    #expect(p.player.currentItem == nil)
    #expect(p.lastStopped == c)
}
