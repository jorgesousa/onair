import Foundation
import Testing
@testable import OnAir

/// Two screens on the same network (here, the same process): one changes channel, the other hears it.
@MainActor @Suite(.serialized) struct HomeLinkTests {
    private func waitFor(_ seconds: Double, _ done: () -> Bool) async {
        let end = Date.now.addingTimeInterval(seconds)
        while Date.now < end, !done() { try? await Task.sleep(for: .milliseconds(100)) }
    }

    @Test(.timeLimit(.minutes(1))) func aChangeOnOneScreenReachesTheOther() async {
        let a = HomeLink(me: "test-a-\(UUID().uuidString.prefix(6))")
        let b = HomeLink(me: "test-b-\(UUID().uuidString.prefix(6))")
        var heard: [Follow.Message] = []
        // Only what `a` said: a real ONAIR on the same network may be talking too.
        b.onMessage = { m in if m.from == a.me { heard.append(m) } }
        a.start(); b.start()
        await waitFor(10) { a.peerNames.contains(b.me) && b.peerNames.contains(a.me) }
        #expect(a.peerNames.contains(b.me))

        a.announce("/proxy/ts/stream/one")
        await waitFor(5) { !heard.isEmpty }
        #expect(heard.first?.key == "/proxy/ts/stream/one")
        #expect(heard.first?.from == a.me)

        // The same channel again is not news.
        a.announce("/proxy/ts/stream/one")
        try? await Task.sleep(for: .seconds(1))
        #expect(heard.count == 1)
        a.stop(); b.stop()
    }

    @Test(.timeLimit(.minutes(1))) func aScreenThatJoinsLateAsksWhatIsOn() async {
        let a = HomeLink(me: "test-c-\(UUID().uuidString.prefix(6))")
        let b = HomeLink(me: "test-d-\(UUID().uuidString.prefix(6))")
        a.start()
        a.announce("/proxy/ts/stream/two")
        b.start()
        await waitFor(10) { b.peerNames.contains(a.me) }
        let answer = await b.ask()
        #expect(answer?.key == "/proxy/ts/stream/two")
        a.stop(); b.stop()
    }
}
