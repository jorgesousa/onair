import Foundation
import Network
import AVFoundation
import Testing
@testable import OnAir

/// A Dispatcharr stand-in: answers the stream request with the next scripted status line,
/// redirecting to an HLS playlist when it says 302.
final class ScriptedServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var script: [String]
    private(set) var asked = 0
    private(set) var paths: [String] = []
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(_ script: [String]) throws {
        self.script = script
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] c in
            c.start(queue: .global())
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                guard let self else { return }
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                self.lock.lock(); self.paths.append(line.components(separatedBy: "?")[0]); let status = self.script.isEmpty ? "404 Not Found" : self.script.removeFirst(); self.asked += 1; self.lock.unlock()
                let extra = status.hasPrefix("302") ? "Location: /proxy/hls/TOKEN/index.m3u8\r\n" : ""
                let reply = "HTTP/1.1 \(status)\r\n\(extra)Content-Length: 0\r\nConnection: close\r\n\r\n"
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

@Suite struct DispatcharrAskTests {
    @Test func aRedirectGivesThePlaylistAddress() async throws {
        let s = try ScriptedServer(["302 Found"])
        let url = URL(string: "http://127.0.0.1:\(s.port)/proxy/ts/stream/abc?output_format=hls")!
        #expect(await PlaybackController.ask(url, headers: nil) == .playlist(URL(string: "http://127.0.0.1:\(s.port)/proxy/hls/TOKEN/index.m3u8")!))
    }

    @Test func busyAndNotReadyAreBusy() async throws {
        let s = try ScriptedServer(["503 Service Unavailable", "500 Internal Server Error"])
        let url = URL(string: "http://127.0.0.1:\(s.port)/proxy/ts/stream/abc?output_format=hls")!
        #expect(await PlaybackController.ask(url, headers: nil) == .busy)
        #expect(await PlaybackController.ask(url, headers: nil) == .busy)
    }

    @Test func noAnswerAtAllIsBusyToo() async {
        // Nothing listens on port 9: the request fails outright.
        #expect(await PlaybackController.ask(URL(string: "http://127.0.0.1:9/proxy/ts/stream/abc")!, headers: nil) == .busy)
    }

    @Test func anythingElseIsAFailure() async throws {
        let s = try ScriptedServer(["404 Not Found"])
        let url = URL(string: "http://127.0.0.1:\(s.port)/proxy/ts/stream/abc?output_format=hls")!
        #expect(await PlaybackController.ask(url, headers: nil) == .failed)
    }
}

/// While Dispatcharr is busy, ONAIR asks again quietly (one request each time) and only hands
/// the player the playlist once it has one.
@MainActor @Test(.timeLimit(.minutes(1))) func dispatcharrIsAskedOnceAtATimeUntilItAnswers() async throws {
    let s = try ScriptedServer(["503 Service Unavailable", "503 Service Unavailable", "302 Found"])
    let c = Channel(name: "Home", group: "G", logo: nil,
                    url: URL(string: "http://127.0.0.1:\(s.port)/proxy/ts/stream/abc?output_format=hls")!)
    let p = PlaybackController()
    p.play(c)
    let end = Date.now.addingTimeInterval(12)
    while Date.now < end, s.asked < 4 { try? await Task.sleep(for: .milliseconds(100)) }
    // Three asks for the channel (busy, busy, redirect), then the player goes to the playlist.
    #expect(Array(s.paths.prefix(4)) == ["/proxy/ts/stream/abc", "/proxy/ts/stream/abc", "/proxy/ts/stream/abc",
                                         "/proxy/hls/TOKEN/index.m3u8"])
    p.release()
}
