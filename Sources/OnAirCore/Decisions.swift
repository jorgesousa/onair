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
