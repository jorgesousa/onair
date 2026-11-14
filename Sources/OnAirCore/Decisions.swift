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
