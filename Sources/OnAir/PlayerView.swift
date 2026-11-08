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
        current = c; failed = nil; isTuning = true; attempt = 0
        let hadStream = player.currentItem != nil
        stop()
        start(c, delay: hadStream ? 0.6 : 0)
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

    private func start(_ c: Channel, delay: Double) {
        let gen = generation
        task = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            // Many providers answer a channel link with a redirect to a session URL. AVFoundation
            // keeps re-requesting the original link on every playlist refresh, which opens a new
            // session each time and starves the stream after ~30 s. Resolve it once, play the result.
            let url = await Self.resolve(Self.playableURL(c.url), headers: c.headers)
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.attach(c, url: url, gen: gen)
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
            isTuning = false
            if failed == "Reconnecting…" { failed = nil }
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
        if let error, Self.isDenied(error), attempt >= 4 {
            failed = "The server refused the stream. The account may be in use on another device, or blocked for a few minutes. Retrying…"
        }
        reconnectNow(reason: ended ? "ended" : "failed")
    }

    /// Start the same channel again, waiting longer after each failure (1, 2, 4, 8, 15, 30 s).
    /// It never gives up while the channel is picked.
    private func reconnectNow(reason: String) {
        guard let c = current else { return }
        let waits: [Double] = [1, 2, 4, 8, 15, 30]
        let wait = waits[min(attempt, waits.count - 1)]
        attempt += 1
        if attempt > 1, failed == nil { failed = "Reconnecting…" }
        isTuning = true
        stop()
        start(c, delay: reason == "wake" ? 1 : wait)
    }

    /// Follow redirects once and return where the playlist really lives.
    nonisolated static func resolve(_ url: URL, headers: [String: String]?) async -> URL {
        guard url.scheme?.hasPrefix("http") == true, url.pathExtension.lowercased() == "m3u8" else { return url }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if req.value(forHTTPHeaderField: "User-Agent") == nil { req.setValue("OnAir/1.0", forHTTPHeaderField: "User-Agent") }
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = http.url else { return url }
        return final
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
