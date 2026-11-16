import Foundation
import AVFoundation
import Observation

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
    /// The channel isn't broadcasting: the stage shows the off-air card instead of a notice.
    var offAir = false
    /// This device can't decode the channel's video: the stage shows the can't-play card.
    var cantPlay = false
    /// After a refusal: when the app will try again by itself (shown as a countdown).
    /// A tap from the viewer doesn't wait for it.
    var holdUntil: Date?
    /// For "off air": since this channel was picked, did anything ever play, how many tries
    /// failed, and when was it picked.
    private var everPlayed = false
    /// Dispatcharr said "busy" last time (still freeing the previous channel): retry every 2 s.
    private var busy = false
    private var failuresWithoutPicture = 0
    private var pickedAt = Date()
    /// The channel `release()` stopped, for "resume".
    var lastStopped: Channel?

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

    init() {
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in self?.statusChanged(status) }
        })
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
        current = c; failed = nil; isTuning = true; attempt = 0; refused = false; soundOnly = false; holdUntil = nil
        everPlayed = false; failuresWithoutPicture = 0; pickedAt = .now; busy = false; offAir = false; cantPlay = false
        let hadStream = player.currentItem != nil
        stop()
        start(c, delay: hadStream ? 0.6 : 0, fresh: true)
    }

    /// Stop and let go of the provider's connection, remembering the channel so it can be
    /// resumed with one tap. The session URL is kept: resuming reuses it when the provider allows.
    func release() {
        if let c = current { lastStopped = c }
        current = nil; failed = nil; isTuning = false; soundOnly = false; attempt = 0; holdUntil = nil; offAir = false; cantPlay = false
        stop()
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
            // Refused before? Open nothing until the provider has let go of the old session:
            // every refused try counts as one more connection and keeps the slot full.
            if let self, self.refused {
                self.failed = "Waiting for your provider to free the connection"
                await Self.waitForFreeSlot(c.xtreamAccount, until: self.holdUntil ?? .now)
                guard !Task.isCancelled, gen == self.generation else { return }
                self.holdUntil = nil
                self.failed = "Reconnecting…"
            }
            // Dispatcharr: ask for the channel's HLS session ourselves, one request at a time, and
            // hand the player the playlist. The player asking for the channel link itself makes
            // several requests that Dispatcharr counts as viewers, drops as ghosts, and sometimes
            // restarts the channel over. While it's still freeing the previous channel ("busy"),
            // ask again every 2 s with the tuning card up.
            if let self, Patience.firstPicture(c) > 15 {
                while true {
                    let answer = await Self.ask(c.url, headers: c.headers)
                    guard !Task.isCancelled, gen == self.generation else { return }
                    switch answer {
                    case .playlist(let playlist):
                        self.session = nil              // a session token, not worth reusing
                        self.attach(c, url: playlist, gen: gen)
                        return
                    case .busy:
                        self.busy = true
                        self.failuresWithoutPicture += 1
                        if OffAir.giveUp(failures: self.failuresWithoutPicture, seconds: Date.now.timeIntervalSince(self.pickedAt),
                                         everPlayed: self.everPlayed, refused: false, busy: true) {
                            self.goOffAir(); return
                        }
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled, gen == self.generation else { return }
                    case .failed:
                        self.attach(c, url: c.url, gen: gen)    // let the player try it the usual way
                        return
                    }
                }
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

    /// Wait until `until`, or sooner if the provider says a connection is free. Providers that
    /// don't answer (auth 0 on the API while streams still play) get the whole wait.
    nonisolated static func waitForFreeSlot(_ a: XtreamAccount?, until: Date) async {
        while !Task.isCancelled, Retry.remaining(until: until, at: .now) > 0 {
            if let a, let (active, max) = await a.connections(), active < max { return }
            let left = Retry.remaining(until: until, at: .now)
            try? await Task.sleep(for: .seconds(min(5, left)))
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
            refused = false; holdUntil = nil; everPlayed = true
            isTuning = false
            if failed == "Reconnecting…" || failed?.hasPrefix("Waiting for your provider") == true { failed = nil }
        case .waitingToPlayAtSpecifiedRate:
            if stuckSince == nil { stuckSince = .now }
            isTuning = failed == nil || failed == "Reconnecting…"
        default:
            stuckSince = nil      // paused by the viewer: not a problem
            // No item means between two attempts (the old one taken down, the next one coming):
            // still tuning, so the "tuning in" card stays up instead of flashing to black.
            if player.currentItem != nil || failed != nil { isTuning = false }
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
            let noPicture = player.currentItem?.presentationSize == .zero
            if let since = playingSince, Date.now.timeIntervalSince(since) > 6, current?.isLive == true {
                if soundOnly != noPicture { soundOnly = noPicture }
            }
            // "Playing" but the clock hasn't moved: frozen picture.
            if Date.now.timeIntervalSince(lastTimeMoved) > 10 { reconnectNow(reason: "frozen") }
            return
        }
        if let since = stuckSince, Date.now.timeIntervalSince(since) > (playingSince == nil ? Patience.firstPicture(current) : 8) {
            reconnectNow(reason: "stalled")
        }
    }

    private func problem(gen: Int, error: Error?, ended: Bool = false) {
        guard gen == generation, current != nil else { return }
        switch PlaybackFailure.of(error) {
        case .unsupported:
            // Retrying won't help and would only hold the provider's connection: stop and say so.
            stop()
            isTuning = false; soundOnly = false
            failed = CantPlay.line
            cantPlay = true
            return
        case .refused:
            // The session is no good any more, and opening another one straight away is what
            // gets an account over its connection limit. Hold off, then one fresh session.
            refused = true
            session = nil
            holdUntil = .now.addingTimeInterval(Retry.holdAfterRefusal)
        case .busy:
            // Only Dispatcharr gets quick retries: at the provider itself each try could count as
            // one more connection, so a direct channel keeps the usual back-off.
            busy = Patience.firstPicture(current) > 15
        case .other:
            busy = false
        }
        reconnectNow(reason: ended ? "ended" : "failed")
    }

    /// Start the same channel again, waiting longer after each failure (1, 2, 4, 8, 15, 30 s).
    /// It never gives up while the channel is picked.
    /// Gentlest first: nudge the player to the live edge on the same item; then a new item on the
    /// same session; only then a new session (after a free slot, if the server refused us).
    /// Waits grow 1 s → 30 s and it never gives up while the channel is picked.
    /// Also called by each app's own triggers: the Mac waking, the iPad back in front.
    func reconnectNow(reason: String) {
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
        // Never showed a thing after a few tries: the channel isn't broadcasting. Say so and stop.
        if !everPlayed, reason != "wake" { failuresWithoutPicture += 1 }
        if OffAir.giveUp(failures: failuresWithoutPicture, seconds: Date.now.timeIntervalSince(pickedAt),
                         everPlayed: everPlayed, refused: refused, busy: busy) {
            goOffAir()
            return
        }
        let waits: [Double] = [1, 1, 3, 8, 15, 30]
        let wait = busy ? 2 : waits[min(attempt, waits.count - 1)]
        attempt += 1
        // Dispatcharr still freeing the previous channel is part of tuning in: the "tuning in"
        // card stays up, with no notice over it.
        if !busy, failed == nil, attempt > 2 { failed = "Reconnecting…" }
        isTuning = true
        stop()
        let fresh = refused || reason == "wake" || attempt > 3 || session?.channel != c.id
        // Refused: the wait is the hold in `start`, not this back-off.
        start(c, delay: reason == "wake" ? 1 : (refused ? 0 : wait), fresh: fresh)
    }

    private func goOffAir() {
        stop()
        isTuning = false; soundOnly = false
        failed = OffAir.message
        offAir = true
    }

    /// What Dispatcharr says when asked for a channel's HLS session.
    enum DispatcharrAnswer: Equatable { case playlist(URL), busy, failed }

    /// One request for the channel's HLS session: its playlist address (the redirect), "busy"
    /// (503: still freeing the previous channel; 500: not started in time; no answer at all),
    /// or a failure (any other answer, a 404 say).
    nonisolated static func ask(_ url: URL, headers: [String: String]?) async -> DispatcharrAnswer {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        // No answer at all (Wi-Fi blip, Dispatcharr restarting): ask again shortly, like "busy",
        // rather than handing the player the channel link (which brings back the stray viewers).
        guard let (_, resp) = try? await URLSession.shared.data(for: req, delegate: NoRedirect.shared),
              let http = resp as? HTTPURLResponse else { return .busy }
        if (300..<400).contains(http.statusCode), let loc = http.value(forHTTPHeaderField: "Location"),
           let next = URL(string: loc, relativeTo: url)?.absoluteURL { return .playlist(next) }
        if http.statusCode == 503 || http.statusCode == 500 { return .busy }
        return .failed
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

}

extension Channel {
    /// Live channels have no end; films and episodes do.
    var isLive: Bool { !(url.path.contains("/movie/") || url.path.contains("/series/")) }
}
