import AVFoundation
import CoreGraphics
import Foundation

/// Changing channel like a remote: step through the visible list, or type its number.
enum Zap {
    /// The next or previous channel, wrapping around. With no current channel (or one not in
    /// the list), going forward starts at the first and going back at the last.
    static func step(from current: Channel.ID?, in list: [Channel.ID], by delta: Int) -> Channel.ID? {
        guard !list.isEmpty else { return nil }
        let i = current.flatMap { list.firstIndex(of: $0) } ?? (delta > 0 ? -1 : list.count)
        let n = list.count
        return list[((i + delta) % n + n) % n]
    }

    /// Tune at three digits, or as soon as another digit could not make a valid number.
    static func shouldCommit(typed: String, count: Int) -> Bool {
        let n = Int(typed) ?? 0
        return typed.count >= 3 || n * 10 > count
    }

    /// Like `step`, but nil when it would land on the channel already on (a one-channel
    /// list): re-tuning it would reopen the provider's only connection for nothing.
    static func move(from current: Channel.ID?, in list: [Channel.ID], by delta: Int) -> Channel.ID? {
        guard let next = step(from: current, in: list, by: delta), next != current else { return nil }
        return next
    }

    /// The channel with that 1-based number, if there is one.
    static func channel(forTyped typed: String, in list: [Channel.ID]) -> Channel.ID? {
        guard let n = Int(typed), n >= 1, n <= list.count else { return nil }
        return list[n - 1]
    }
}

enum PadLayoutMode: Equatable { case rail, watch, stacked }

/// iPad: what the screen shows is decided by the window's shape, not the device orientation.
enum PadLayout {
    static func mode(size: CGSize, playing: Bool, expanded: Bool) -> PadLayoutMode {
        guard playing else { return .rail }
        return expanded || size.width > size.height ? .watch : .stacked
    }
}

enum ScenePhaseLike { case active, inactive, background }

/// The provider allows one connection. The iPad keeps it only while there is a picture:
/// the app on screen, or Picture in Picture that is actually playing.
enum ConnectionPolicy {
    static let pausedGrace: TimeInterval = 10

    /// One more second of pause, or back to zero. Only a pause you chose counts: a stream
    /// stalling (waiting to play) is the reconnect logic's job, not a reason to let go.
    static func pausedFor(after seconds: TimeInterval, status: AVPlayer.TimeControlStatus) -> TimeInterval {
        status == .paused ? seconds + 1 : 0
    }

    static func keep(phase: ScenePhaseLike, pip: Bool, pausedFor: TimeInterval) -> Bool {
        switch phase {
        case .active, .inactive: return true
        case .background: return pip && pausedFor < pausedGrace
        }
    }
}

/// iPad: swiping on the picture changes channel, like the Mac's ↑↓.
enum Swipe {
    /// A swipe changes channel past 60 pt of travel, or on a flick faster than 500 pt/s.
    static let distance: CGFloat = 60
    static let velocity: CGFloat = 500

    /// +1 next channel (finger moved up), -1 previous (down), 0 nothing.
    static func step(travel: CGFloat, velocity v: CGFloat) -> Int {
        if travel <= -distance || v <= -velocity { return 1 }
        if travel >= distance || v >= velocity { return -1 }
        return 0
    }

    /// The picture follows the finger, with growing resistance past `limit`.
    static func rubberBand(_ travel: CGFloat, limit: CGFloat = 80) -> CGFloat {
        let a = abs(travel)
        guard a > limit else { return travel }
        let over = a - limit
        let damped = limit + (over * limit * 0.55) / (limit + 0.55 * over)
        return travel < 0 ? -damped : damped
    }
}

/// Why a stream stopped, as far as what to do next is concerned.
enum PlaybackFailure: Equatable {
    /// The provider said no (usually: the one connection is in use). Retrying straight away
    /// only counts as another connection.
    case refused
    /// This device can't decode the channel's video. Retrying won't change that.
    case unsupported
    /// The server is up but can't serve it yet (HTTP 503 / 500): Dispatcharr still holding the
    /// previous channel, or this one not started in time. Worth a quick retry.
    case busy
    /// Anything else: network, a dropped session. Worth retrying.
    case other

    static func of(_ error: Error?) -> PlaybackFailure {
        var e = error as NSError?
        while let n = e {
            if [-12863, -11833].contains(n.code) { return .unsupported }
            if [-16849, -16847].contains(n.code) { return .busy }
            if [401, 403, -1102, -12660].contains(n.code) { return .refused }
            if n.localizedDescription.localizedCaseInsensitiveContains("permission") { return .refused }
            e = n.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return .other
    }
}

/// After a refusal the app stops trying by itself for a while: the provider keeps a session
/// for about two minutes after it's left. A tap from the viewer always gets one try now.
enum Retry {
    static let holdAfterRefusal: TimeInterval = 120

    static func remaining(until: Date?, at now: Date) -> TimeInterval {
        guard let until else { return 0 }
        return max(0, until.timeIntervalSince(now))
    }
}

/// iPhone: full screen means turning the picture sideways, like the TV app. The button turns
/// the screen and holds it there until the phone is held that way; then the phone leads again,
/// so turning it back upright leaves full screen. The iPad doesn't turn (it sits on a table).
enum FullScreenTurn {
    enum Way: Equatable { case portrait, landscape }

    /// Where the full-screen button turns the screen, or nil to stay put.
    static func target(phone: Bool, wide: Bool) -> Way? {
        guard phone else { return nil }
        return wide ? .portrait : .landscape
    }

    /// Let the phone lead again once it's held the way the button turned the screen.
    static func release(lockedTo: Way?, held: Way?) -> Bool {
        guard let lockedTo, let held else { return false }
        return lockedTo == held
    }
}

/// A channel this device can't decode (the format, not the stream): final, like off air.
enum CantPlay {
    static let label = "CAN'T PLAY"
    @MainActor static var line: String { "This \(Platform.device) can't show this channel's video. Pick another channel." }
}

/// A channel that isn't broadcasting (a PPV between events, a feed the provider has dropped)
/// would otherwise sit on "Tuning in" / "Reconnecting" forever, which looks like ONAIR's fault.
/// Give up and say "off air" after a few tries that never showed a thing — but not before 20 s
/// (Dispatcharr can say "busy" for ~12 s after a channel change), and never for a refusal
/// (the provider's connection in use has its own wait). A tap on the channel tries again.
enum OffAir {
    /// One wording for the state, wherever it shows (stage, TV, notice, VoiceOver).
    static let label = "OFF AIR"
    static let line = "Not broadcasting right now. Pick it again to retry."
    static let message = "Off air · not broadcasting right now"

    /// While the server says "busy", give it 45 s (Dispatcharr frees the previous channel within
    /// ~12 s, then needs to start this one).
    static func giveUp(failures: Int, seconds: TimeInterval, everPlayed: Bool, refused: Bool, busy: Bool = false) -> Bool {
        !everPlayed && !refused && failures >= 3 && seconds >= (busy ? 45 : 20)
    }
}
