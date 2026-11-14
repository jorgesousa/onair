import SwiftUI
import AppKit
import AVFoundation

/// "TV as a screen": the TV is connected to the Mac as a separate display (AirPlay, HDMI, any
/// display), and ONAIR shows the picture full screen on it. The Mac plays the stream, so it works
/// with every channel, keeps the provider at one connection, and changes channel instantly. The TV
/// window is ours, so it also gets the tuner transition.
@MainActor @Observable
final class TVScreen {
    /// Displays other than the one ONAIR's main window is on.
    private(set) var screens: [NSScreen] = []
    private(set) var showing: NSScreen?
    /// False while the TV picture folds away, just before the window closes.
    private(set) var powered = true
    private var window: NSWindow?

    var available: Bool { !screens.isEmpty }
    var name: String { (showing ?? screens.first)?.localizedName ?? "TV" }

    init() {
        refresh()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        let main = NSApp.mainWindow?.screen ?? NSScreen.main
        screens = NSScreen.screens.filter { $0 != main }
        // The TV went away (AirPlay display ended): close our window.
        if let s = showing, !NSScreen.screens.contains(s) { hide() }
    }

    func show<Content: View>(_ content: Content) {
        guard let screen = screens.first else { return }
        hide()
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)   // over the menu bar and Dock on the TV
        w.collectionBehavior = [.fullScreenNone, .canJoinAllSpaces]
        w.contentView = NSHostingView(rootView: content.ignoresSafeArea())
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        showing = screen
        powered = true
    }

    /// `animated`: the TV picture folds to a line first, like a set switching off.
    func hide(animated: Bool = false) {
        guard animated, let w = window else { close(); return }
        showing = nil          // the Mac takes the picture back at once
        powered = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            if window === w { close() }
        }
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        showing = nil
        powered = true
    }
}

/// The picture as a plain layer (no controls), for the TV.
struct VideoLayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        v.layer = layer
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        (v.layer as? AVPlayerLayer)?.player = player
    }
}

/// What the TV shows: the picture, and on every channel change the channel card in the brand.
struct TVScreenView: View {
    let playback: PlaybackController
    let tv: TVScreen
    let number: (Channel) -> Int?
    let programme: (Channel) -> Programme?
    @State private var osd: Channel?
    @State private var osdShown = false
    @State private var osdTask: Task<Void, Never>?
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            Color.black
            VideoLayer(player: playback.player)
                .opacity(playback.isTuning ? 0 : 1)
                .animation(reduce ? Motion.fade : Motion.fade.delay(0.12), value: playback.isTuning)
            if let c = playback.current {
                TuningOverlay(channel: c, tuning: playback.isTuning)
            }
            if let c = osd {
                ChannelCard(channel: c, number: number(c), now: programme(c), clock: .now)
                    .padding(64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // A channel change is a remote-control action, many times an evening: in at once, out in a
                    // fade. It stays in the view tree and fades by opacity: a removal would be drawn under the picture.
                    .opacity(osdShown ? 1 : 0)
            }
        }
        .animation(Motion.if(reduce, Motion.fade), value: playback.isTuning)
        // Power on from a line, and off into one.
        .scaleEffect(x: 1, y: reduce || (on && tv.powered) ? 1 : 0.006)
        .opacity(reduce && !(on && tv.powered) ? 0 : 1)
        .animation(tv.powered ? .spring(duration: 0.46, bounce: 0) : .timingCurve(0.55, 0, 1, 0.45, duration: 0.22), value: on && tv.powered)
        .background(Color.black)
        .onChange(of: playback.current?.id) { _, _ in showOSD() }
        .onAppear { on = true; showOSD(); NSCursor.setHiddenUntilMouseMoves(true) }
    }

    private func showOSD() {
        guard let c = playback.current else { return }
        osdTask?.cancel()
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { osd = c; osdShown = true }
        osdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.if(reduce, .easeOut(duration: 0.2))) { osdShown = false }
        }
    }
}

/// The channel card: bars, tuner number, name, what's on. Top left, like a station ident.
/// Full size on the TV; `scale` shrinks it for the Mac's Watch mode.
struct ChannelCard: View {
    let channel: Channel
    let number: Int?
    /// Digits being typed to change channel: shown in place of the number.
    var typed: String? = nil
    var now: Programme? = nil
    var clock: Date = .now
    var scale: CGFloat = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Bars().frame(height: 14 * scale)
            VStack(alignment: .leading, spacing: 16 * scale) {
                HStack(alignment: .center, spacing: 22 * scale) {
                    Text(typed.map { $0.padding(toLength: 3, withPad: "–", startingAt: 0) }
                         ?? number.map { String(format: "%03d", $0) } ?? "···")
                        .font(.system(size: 72 * scale, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brand.ink)
                        // Zapping fast keeps the card up and only the number ticks.
                        .contentTransition(.numericText())
                        .transaction(value: number) { t in
                            t.disablesAnimations = false
                            t.animation = .easeOut(duration: 0.2)
                        }
                    VStack(alignment: .leading, spacing: 6 * scale) {
                        Text(channel.displayName.uppercased())
                            .font(Brand.display(40 * scale)).foregroundStyle(Brand.ink)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        HStack(spacing: 8 * scale) {
                            Circle().fill(Brand.live).frame(width: 10 * scale, height: 10 * scale)
                            Text(now.map { "LIVE · \($0.span)" } ?? "LIVE")
                                .font(Brand.mono(14 * scale, .semibold)).foregroundStyle(Brand.ink.opacity(0.62))
                        }
                    }
                }
                if let now {
                    VStack(alignment: .leading, spacing: 10 * scale) {
                        Text(now.title).font(.system(size: 22 * scale, weight: .semibold)).foregroundStyle(Brand.ink)
                            .lineLimit(1)
                        Capsule().fill(Brand.ink.opacity(0.12)).frame(height: 5 * scale)
                            .overlay(alignment: .leading) {
                                GeometryReader { g in Capsule().fill(Brand.ink).frame(width: g.size.width * now.progress(at: clock)) }
                            }
                    }
                }
            }
            .padding(.horizontal, 34 * scale).padding(.vertical, 26 * scale)
        }
        .frame(minWidth: 420 * scale, maxWidth: 820 * scale, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(Brand.paper)
        .clipShape(.rect(cornerRadius: 10 * scale, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 30 * scale, y: 10 * scale)
    }
}

/// On the Mac while the picture is on the TV screen.
struct OnTVScreenView: View {
    let channel: Channel
    let screenName: String
    let stop: () -> Void
    var body: some View {
        ZStack {
            Brand.ink
            VStack(spacing: 18) {
                Image(systemName: "tv").font(.system(size: 50, weight: .semibold)).foregroundStyle(Brand.paper)
                Text("ON YOUR TV").font(Brand.display(40)).foregroundStyle(Brand.paper)
                Text("\(channel.displayName) is showing on \(screenName). Change channel here; it switches at once.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.dim)
                    .multilineTextAlignment(.center).frame(maxWidth: 440)
                Bars().frame(width: 220, height: 6).clipShape(.capsule)
                SecondaryButton(title: "Back to this Mac", action: stop).padding(.top, 8)
            }
            .rise(0.16)
        }
    }
}

/// On the Mac while the picture plays in Picture in Picture: ours instead of AVKit's grey placeholder.
struct InPictureInPictureView: View {
    let channel: Channel
    var body: some View {
        ZStack {
            Brand.ink
            VStack(spacing: 18) {
                Image(systemName: "pip").font(.system(size: 46, weight: .semibold)).foregroundStyle(Brand.paper)
                Text("IN THE SMALL WINDOW").font(Brand.display(36)).foregroundStyle(Brand.paper)
                Text("\(channel.displayName) is playing in Picture in Picture. Close the small window, or pick a channel, to bring the picture back here.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.dim)
                    .multilineTextAlignment(.center).frame(maxWidth: 440)
                Bars().frame(width: 220, height: 6).clipShape(.capsule)
            }
            .rise()
        }
        .allowsHitTesting(false)
    }
}
