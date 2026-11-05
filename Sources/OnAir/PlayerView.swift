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
    /// True from the moment a channel is picked until frames are actually moving,
    /// and again whenever the stream stalls to buffer.
    var isTuning = false
    private var statusObservation: NSKeyValueObservation?

    init() {
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let playing = p.timeControlStatus == .playing
            Task { @MainActor in
                guard let self else { return }
                self.isTuning = !playing && self.current != nil && self.failed == nil
            }
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

    let player = AVPlayer()
    var current: Channel?
    var failed: String?
    private var observation: NSKeyValueObservation?

    private var retryTask: Task<Void, Never>?
    private var switchTask: Task<Void, Never>?

    /// Switching closes the old stream first and waits a moment before opening the new one:
    /// IPTV accounts usually allow one connection, and the server needs time to free it.
    func play(_ c: Channel) {
        current = c; failed = nil; isTuning = true
        retryTask?.cancel(); switchTask?.cancel()
        observation = nil
        let hadStream = player.currentItem != nil
        player.replaceCurrentItem(with: nil)
        switchTask = Task { [weak self] in
            if hadStream { try? await Task.sleep(for: .milliseconds(600)) }
            guard !Task.isCancelled else { return }
            self?.start(c, attempt: 0)
        }
    }

    private func start(_ c: Channel, attempt: Int) {
        var options: [String: Any] = [:]
        if let h = c.headers { options["AVURLAssetHTTPHeaderFieldsKey"] = h }
        let item = AVPlayerItem(asset: AVURLAsset(url: Self.playableURL(c.url), options: options))
        observation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let err = item.error
            Task { @MainActor in self?.handleFailure(err, channel: c, attempt: attempt) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func handleFailure(_ error: Error?, channel c: Channel, attempt: Int) {
        guard current == c else { return }
        let denied = Self.isDenied(error)
        if attempt < 3 {
            failed = attempt == 0 ? nil : "Reconnecting…"
            player.replaceCurrentItem(with: nil)
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(denied ? 3 : 1.5))
                guard !Task.isCancelled else { return }
                self?.start(c, attempt: attempt + 1)
            }
        } else {
            isTuning = false
            failed = denied
                ? "The server refused the stream. The account may be in use on another device, or blocked for a few minutes."
                : (error?.localizedDescription ?? "This stream won't play.")
        }
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
