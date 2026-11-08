import SwiftUI
import AVKit

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = true
        v.allowsPictureInPicturePlayback = true
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

@MainActor @Observable
final class PlaybackController {
    let player = AVPlayer()
    var current: Channel?
    /// A message for the stage: reconnecting, or why a stream won't play.
    var failed: String?
    /// True from the moment a channel is picked until frames are moving, and whenever
    /// the stream is stalled or being reconnected.
    var isTuning = false
    /// Playing, but no picture has arrived: the channel sends sound only, or a video format the
    /// Mac can't decode. Shown on the stage instead of a black screen.
    var soundOnly = false

    /// Each start gets a number; callbacks from an older start are ignored.
    private var generation = 0
    private var attempt = 0
    private var stuckSince: Date?
    private var playingSince: Date?
    private var lastTime: Double = -1
    private var lastTimeMoved = Date()
    private var observations: [NSKeyValueObservation] = []
    private var itemTokens: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?
    private var watchdog: Timer?
    /// The provider's session URL for the current channel. Reusing it reconnects without
    /// opening a new session, which matters on accounts limited to one connection.
    private var session: (channel: String, url: URL)?
    /// The server refused us (usually: too many connections). Wait for a free slot before a new session.
    private var refused = false
    /// Taps the decoded picture, only to know whether any frame has arrived (see `soundOnly`).
    private var videoOutput: AVPlayerItemVideoOutput?
    private var sawFrame = false

    init() {
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in self?.statusChanged(status) }
        })
        // The Mac slept, or the network came back: the old stream is dead, start a fresh one.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconnectNow(reason: "wake") }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHealth() }
        }
    }

    /// AVFoundation plays HLS, not raw MPEG-TS. Xtream-style servers serve every live
    /// channel as HLS at /live/<user>/<pass>/<id>.m3u8, so map the TS forms onto that.
    nonisolated static func playableURL(_ url: URL) -> URL {
        let ext = url.pathExtension.lowercased()
        guard ext.isEmpty || ext == "ts" else { return url }
        var parts = url.path.split(separator: "/").map(String.init)
        if parts.count == 3 { parts.insert("live", at: 0) }          // /user/pass/id
        // Only Xtream-shaped links: /live/<user>/<pass>/<numeric id>.
        guard parts.count == 4, parts[0] == "live",
              Int((parts[3] as NSString).deletingPathExtension) != nil,
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let id = (parts[3] as NSString).deletingPathExtension
        c.path = "/live/\(parts[1])/\(parts[2])/\(id).m3u8"
        return c.url ?? url
    }

    // MARK: Picking a channel

    /// Switching closes the old stream first and waits a moment before opening the new one:
    /// IPTV accounts usually allow one connection, and the server needs time to free it.
    func play(_ c: Channel) {
        current = c; failed = nil; isTuning = true; attempt = 0; refused = false; soundOnly = false
        let hadStream = player.currentItem != nil
        stop()
        start(c, delay: hadStream ? 0.6 : 0, fresh: true)
    }

    private func stop() {
        task?.cancel(); task = nil
        generation += 1
        observations.removeSubrange(1...)        // keep the player's own observation
        itemTokens.forEach(NotificationCenter.default.removeObserver)
        itemTokens = []
        player.replaceCurrentItem(with: nil)
        stuckSince = nil; playingSince = nil; lastTime = -1
    }

    private func start(_ c: Channel, delay: Double, fresh: Bool) {
        let gen = generation
        if !fresh, let s = session, s.channel == c.id {
            // Same session, new player item: no new connection on the provider's side.
            task = Task { [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard let self, !Task.isCancelled, gen == self.generation else { return }
                self.attach(c, url: s.url, gen: gen)
            }
            return
        }
        task = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            // Refused before? Wait until the provider has let go of the old session.
            if let self, self.refused, let account = c.xtreamAccount {
                self.failed = "Waiting for your provider to free the connection…"
                await Self.waitForFreeSlot(account)
                guard !Task.isCancelled, gen == self.generation else { return }
                self.failed = "Reconnecting…"
            }
            // Many providers answer a channel link with a redirect to a session URL. AVFoundation
            // keeps re-requesting the original link on every playlist refresh, which opens a new
            // session each time and starves the stream after ~30 s. Resolve it once, play the result.
            let url = await Self.resolve(Self.playableURL(c.url), headers: c.headers)
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.session = (c.id, url)
            self.attach(c, url: url, gen: gen)
        }
    }

    /// Ask the provider how many connections it is counting; wait (up to 2 min) until one is free.
    /// Some providers don't answer this (auth 0 on the API while streams still play): then give the
    /// old session a few seconds to close and try, instead of waiting blind for two minutes.
    nonisolated static func waitForFreeSlot(_ a: XtreamAccount) async {
        for _ in 0..<24 {
            guard let (active, max) = await a.connections() else {
                try? await Task.sleep(for: .seconds(4))
                return
            }
            if active < max { return }
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
        }
    }

    private func attach(_ c: Channel, url: URL, gen: Int) {
        var options: [String: Any] = [:]
        if let h = c.headers { options["AVURLAssetHTTPHeaderFieldsKey"] = h }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        item.preferredForwardBufferDuration = 20
        observations.append(item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let err = item.error
            Task { @MainActor in self?.problem(gen: gen, error: err) }
        })
        let nc = NotificationCenter.default
        itemTokens.append(nc.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] n in
            let err = n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in self?.problem(gen: gen, error: err) }
        })
        // A live stream never really ends: if it does, the server dropped us. A film just finished.
        itemTokens.append(nc.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in if c.isLive { self?.problem(gen: gen, error: nil, ended: true) } }
        })
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(out)
        videoOutput = out; sawFrame = false
        player.replaceCurrentItem(with: item)
        player.play()
        lastTimeMoved = .now
    }

    // MARK: Staying on air

    private func statusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard current != nil else { isTuning = false; return }
        switch status {
        case .playing:
            stuckSince = nil
            if playingSince == nil { playingSince = .now }
            refused = false
            isTuning = false
            if failed == "Reconnecting…" || failed?.hasPrefix("Waiting for your provider") == true { failed = nil }
        case .waitingToPlayAtSpecifiedRate:
            if stuckSince == nil { stuckSince = .now }
            isTuning = failed == nil || failed == "Reconnecting…"
        default:
            stuckSince = nil      // paused by the viewer: not a problem
            isTuning = false
        }
    }

    /// Every 2 s: is the picture actually moving? If not for too long, reconnect.
    private func checkHealth() {
        // Nothing attached means we're between attempts (waiting or resolving): nothing to judge.
        guard current != nil, player.currentItem != nil else { return }
        // Healthy for a while: forget earlier failures.
        if let since = playingSince, Date.now.timeIntervalSince(since) > 30 { attempt = 0 }
        let t = player.currentTime().seconds
        if player.timeControlStatus == .playing {
            if t.isFinite, abs(t - lastTime) > 0.01 { lastTime = t; lastTimeMoved = .now }
            // Sound has been playing for a while and still no picture.
            if !sawFrame, let out = videoOutput,
               out.hasNewPixelBuffer(forItemTime: out.itemTime(forHostTime: CACurrentMediaTime())) {
                sawFrame = true
            }
            let noPicture = !sawFrame
            if let since = playingSince, Date.now.timeIntervalSince(since) > 6, current?.isLive == true {
                if soundOnly != noPicture { soundOnly = noPicture }
            }
            // "Playing" but the clock hasn't moved: frozen picture.
            if Date.now.timeIntervalSince(lastTimeMoved) > 10 { reconnectNow(reason: "frozen") }
            return
        }
        if let since = stuckSince, Date.now.timeIntervalSince(since) > (playingSince == nil ? 15 : 8) {
            reconnectNow(reason: "stalled")
        }
    }

    private func problem(gen: Int, error: Error?, ended: Bool = false) {
        guard gen == generation, current != nil else { return }
        if let error, Self.isDenied(error) {
            // The session is no good any more, and opening another one straight away is what
            // gets an account over its connection limit. Wait for a free slot, then a fresh session.
            refused = true
            session = nil
            if attempt >= 6 {
                failed = "The server refused the stream. The account may be in use on another device. Retrying…"
            }
        }
        reconnectNow(reason: ended ? "ended" : "failed")
    }

    /// Start the same channel again, waiting longer after each failure (1, 2, 4, 8, 15, 30 s).
    /// It never gives up while the channel is picked.
    /// Gentlest first: nudge the player to the live edge on the same item; then a new item on the
    /// same session; only then a new session (after a free slot, if the server refused us).
    /// Waits grow 1 s → 30 s and it never gives up while the channel is picked.
    private func reconnectNow(reason: String) {
        guard let c = current else { return }
        let stalled = reason == "stalled" || reason == "frozen"
        if stalled, attempt == 0, let item = player.currentItem, let live = item.seekableTimeRanges.last?.timeRangeValue {
            attempt = 1
            stuckSince = .now; lastTimeMoved = .now
            let edge = CMTimeSubtract(CMTimeRangeGetEnd(live), CMTime(seconds: 3, preferredTimescale: 600))
            item.seek(to: edge, completionHandler: nil)
            player.play()
            return
        }
        let waits: [Double] = [1, 1, 3, 8, 15, 30]
        let wait = waits[min(attempt, waits.count - 1)]
        attempt += 1
        if failed == nil, attempt > 2 { failed = "Reconnecting…" }
        isTuning = true
        stop()
        let fresh = refused || reason == "wake" || attempt > 3 || session?.channel != c.id
        start(c, delay: reason == "wake" ? 1 : (refused ? max(wait, 5) : wait), fresh: fresh)
    }

    /// Ask where the playlist really lives, without going there: read the redirect's Location
    /// and stop. Following it would already count as a connection on the provider's side,
    /// and the player opens its own a moment later, which puts 1-connection accounts over the limit.
    nonisolated static func resolve(_ url: URL, headers: [String: String]?) async -> URL {
        guard url.scheme?.hasPrefix("http") == true, url.pathExtension.lowercased() == "m3u8" else { return url }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if req.value(forHTTPHeaderField: "User-Agent") == nil { req.setValue("OnAir/1.0", forHTTPHeaderField: "User-Agent") }
        // One hop: if the link redirects, hand the player the target untouched.
        guard let (_, resp) = try? await URLSession.shared.data(for: req, delegate: NoRedirect.shared),
              let http = resp as? HTTPURLResponse, (300..<400).contains(http.statusCode),
              let loc = http.value(forHTTPHeaderField: "Location"),
              let next = URL(string: loc, relativeTo: url)?.absoluteURL else { return url }
        return next
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        static let shared = NoRedirect()
        func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse,
                        newRequest: URLRequest) async -> URLRequest? { nil }
    }

    private static func isDenied(_ error: Error?) -> Bool {
        var e = error as NSError?
        while let n = e {
            if [401, 403, -1102, -12660].contains(n.code) { return true }
            if n.localizedDescription.localizedCaseInsensitiveContains("permission") { return true }
            e = n.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

extension Channel {
    /// Live channels have no end; films and episodes do.
    var isLive: Bool { !(url.path.contains("/movie/") || url.path.contains("/series/")) }
}
