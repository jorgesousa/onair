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
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        showing = nil
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

/// What the TV shows: the picture, and on every channel change the tuner card in the brand.
struct TVScreenView: View {
    let playback: PlaybackController
    let number: (Channel) -> Int?
    @State private var osd: Channel?
    @State private var osdTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black
            VideoLayer(player: playback.player)
                .opacity(playback.isTuning ? 0 : 1)
                .animation(Motion.fade, value: playback.isTuning)
            if let c = playback.current, playback.isTuning {
                TuningView(channel: c).id(c.id).transition(.opacity)
            }
            if let c = osd {
                TVChannelOSD(channel: c, number: number(c))
                    .id(c.id)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(Motion.enter, value: osd?.id)
        .onChange(of: playback.current?.id) { _, _ in showOSD() }
        .onAppear { showOSD() }
        .onAppear { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    private func showOSD() {
        guard let c = playback.current else { return }
        osdTask?.cancel()
        osd = c
        osdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            osd = nil
        }
    }
}

/// The channel card on the TV: bars, tuner number, name, what's on. Top left, like a station ident.
struct TVChannelOSD: View {
    let channel: Channel
    let number: Int?
    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Bars().frame(height: 14)
                    HStack(alignment: .firstTextBaseline, spacing: 22) {
                        Text(number.map { String(format: "%03d", $0) } ?? "···")
                            .font(.system(size: 72, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Brand.ink)
                            .contentTransition(.numericText())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(channel.displayName.uppercased())
                                .font(Brand.display(40)).foregroundStyle(Brand.ink)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            HStack(spacing: 8) {
                                Circle().fill(Brand.live).frame(width: 10, height: 10)
                                Text("LIVE").font(Brand.display(14)).tracking(2).foregroundStyle(Brand.ink.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 34).padding(.vertical, 26)
                }
                .background(Brand.paper)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
                .frame(maxWidth: 820, alignment: .leading)
                Spacer()
            }
            Spacer()
        }
        .padding(64)
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
            .rise()
        }
    }
}
