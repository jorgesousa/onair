import Foundation
import Network
import Testing
@testable import OnAir

/// A provider that answers every stream request with one status (403 refused, 404 off air),
/// counting how often it was asked.
final class RefusingServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var _hits = 0
    var hits: Int { lock.lock(); defer { lock.unlock() }; return _hits }
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(status: String = "403 Forbidden") throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] c in
            c.start(queue: .global())
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\r\n").first ?? ""
                if line.contains("/live/"), let self { self.lock.lock(); self._hits += 1; self.lock.unlock() }
                let reply = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                c.send(content: reply.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
            }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
    }
    deinit { listener.cancel() }
}

@MainActor private func wait(_ seconds: Double, until done: () -> Bool = { false }) async {
    let end = Date.now.addingTimeInterval(seconds)
    while Date.now < end, !done() { try? await Task.sleep(for: .milliseconds(100)) }
}

@MainActor @Test(.timeLimit(.minutes(1))) func aRefusalHoldsOffAndATapTriesNow() async throws {
    let server = try RefusingServer()
    let c = Channel(name: "One", group: "G", logo: nil,
                    url: URL(string: "http://127.0.0.1:\(server.port)/live/u/p/1.m3u8")!)
    let p = PlaybackController()
    p.play(c)
    await wait(15) { p.holdUntil != nil }
    #expect(p.holdUntil != nil)
    #expect(p.failed?.hasPrefix("Waiting for your provider") == true)

    // Held: the app asks the provider nothing more by itself.
    let held = server.hits
    await wait(8)
    #expect(server.hits == held)

    // The viewer picks the channel again: one try straight away.
    p.play(c)
    await wait(5) { server.hits > held }
    #expect(server.hits > held)
    p.release()
}

@MainActor @Test(.timeLimit(.minutes(2))) func aChannelThatSendsNothingEndsAsOffAir() async throws {
    let server = try RefusingServer(status: "404 Not Found")
    let c = Channel(name: "PPV", group: "G", logo: nil,
                    url: URL(string: "http://127.0.0.1:\(server.port)/live/u/p/9.m3u8")!)
    let p = PlaybackController()
    p.play(c)
    await wait(60) { p.failed == OffAir.message }
    #expect(p.failed == OffAir.message)
    #expect(p.isTuning == false)
    #expect(p.player.currentItem == nil)       // gave up: nothing left trying
    let tries = server.hits
    await wait(6)
    #expect(server.hits == tries)
    p.release()
}
