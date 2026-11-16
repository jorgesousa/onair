import SwiftUI

/// One motion vocabulary for the whole app. Fast, decisive, no wobble.
/// Everything collapses to instant when Reduce Motion is on.
enum Motion {
    static let snap = Animation.spring(duration: 0.32, bounce: 0.12)     // the on-air highlight, filters
    static let enter = Animation.spring(duration: 0.5, bounce: 0.08)     // things arriving
    static let fade = Animation.easeOut(duration: 0.35)                   // video in, states
    static let quick = Animation.easeOut(duration: 0.14)                  // hover, press
    static let swap = Animation.spring(duration: 0.26, bounce: 0)         // text changing in place (zapping)

    static func `if`(_ reduce: Bool, _ a: Animation) -> Animation? { reduce ? nil : a }
}

/// Text replaced in place: a cross-fade through a light blur, so the old and new
/// lines read as one change rather than two overlapping.
struct BlurFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.opacity(active ? 0 : 1).blur(radius: active ? 3 : 0)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

/// Press feedback for every custom button: a short dip, no colour change.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Fades and lifts content in on first appearance, with an optional stagger.
struct Rise: ViewModifier {
    var delay: Double = 0
    var distance: CGFloat = 14
    var active = true
    var animation: Animation? = nil
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce || !active ? 1 : 0)
            .offset(y: shown || reduce || !active ? 0 : distance)
            .onAppear {
                guard !reduce, active else { return }
                withAnimation((animation ?? Motion.enter).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func rise(_ delay: Double = 0, distance: CGFloat = 14, active: Bool = true, animation: Animation? = nil) -> some View {
        modifier(Rise(delay: delay, distance: distance, active: active, animation: animation))
    }
}

/// The test card switching off like an old set: it folds to a bright line, then goes.
struct CRTOff: ViewModifier, Animatable {
    var amount: Double   // 0 = card, 1 = gone
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        let fold = min(1, amount / 0.7)               // first 70%: fold to a line
        content
            .scaleEffect(x: 1 - 0.7 * max(0, amount - 0.7) / 0.3, y: 1 - 0.988 * fold)
            .brightness(0.8 * fold)
            .opacity(amount < 0.7 ? 1 : 1 - (amount - 0.7) / 0.3)
    }
}

/// The test card over the stage while tuning. When the picture arrives it folds into a bright line and
/// goes (a fade under Reduce Motion). It stays in the view tree while it folds: SwiftUI draws a view that
/// is being removed underneath AppKit's picture view, so a removal transition would fold out of sight.
struct TuningOverlay: View {
    let channel: Channel
    let tuning: Bool
    @State private var shown = false
    @State private var fold = 0.0
    @State private var fade = 0.0
    @State private var task: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            if shown {
                TuningView(channel: channel).id(channel.id)
                    .modifier(CRTOff(amount: fold))
                    .opacity(1 - fade)
            }
        }
        .allowsHitTesting(false)
        .onAppear { if tuning { begin() } }
        .onChange(of: tuning) { _, t in t ? begin() : end() }
    }

    /// Fades in (proposal 02: opacity insertion), in the same 0.35 s as the picture fades out under it.
    private func begin() {
        task?.cancel()
        var t = Transaction(); t.disablesAnimations = true
        let fresh = !shown || fade > 0 || fold > 0
        withTransaction(t) { if fresh { fade = 1 }; fold = 0; shown = true }
        withAnimation(Motion.fade) { fade = 0 }
    }

    private func end() {
        guard shown else { return }
        task?.cancel()
        if reduce {
            withAnimation(.easeOut(duration: 0.2)) { fade = 1 }
        } else {
            withAnimation(.timingCurve(0.55, 0, 1, 0.45, duration: 0.26)) { fold = 1 }
        }
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { shown = false; fold = 0; fade = 0 }
        }
    }
}

/// Shown between picking a channel and the first frame, and while a stream stalls:
/// a test card with the channel name across it.
struct TuningView: View {
    let channel: Channel
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Bars()
                HStack(spacing: 0) {   // the reversed strip under the bars, as on a real card
                    ForEach(0..<7, id: \.self) { i in i % 2 == 0 ? Brand.bars[6 - i] : Brand.ink }
                }
                .frame(height: 22)
            }
            VStack(spacing: 10) {
                Text("TUNING IN").font(Brand.display(10)).tracking(2.4).foregroundStyle(Brand.ink.opacity(0.6))
                Text(channel.displayName.uppercased())
                    .font(Brand.display(38)).foregroundStyle(Brand.ink)
                    .lineLimit(1).minimumScaleFactor(0.4)
                GeometryReader { g in
                    Capsule().fill(Brand.ink.opacity(0.14))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Brand.ink).frame(width: g.size.width * 0.3)
                                .offset(x: sweep ? g.size.width * 0.7 : 0)
                        }
                }
                .frame(width: 180, height: 3)
            }
            .padding(.horizontal, 30).padding(.vertical, 20)
            .background(Brand.paper, in: .rect(cornerRadius: 4))
            .padding(.horizontal, 24)
            .rise(0.02, distance: 8)
        }
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

/// A channel that isn't broadcasting: the same test card as tuning, gone grey and dim like a
/// station off the air, with the same paper card saying so. Picking the channel again retries.
struct OffAirView: View {
    let channel: Channel
    var body: some View { EndCard(label: OffAir.label, channel: channel, line: OffAir.line) }
}

/// The channel's video is in a format this device can't show: the same card as off air.
struct CantPlayView: View {
    let channel: Channel
    var body: some View { EndCard(label: CantPlay.label, channel: channel, line: CantPlay.line) }
}

/// A final state (off air, can't play): the tuning test card gone grey and dim, with the same
/// paper card as tuning in. Passing states (reconnecting, waiting) stay as the notice pill.
struct EndCard: View {
    let label: String
    let channel: Channel
    let line: String

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Bars()
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in i % 2 == 0 ? Brand.bars[6 - i] : Brand.ink }
                }
                .frame(height: 22)
            }
            .grayscale(1)
            .opacity(0.32)
            .background(Brand.ink)
            VStack(spacing: 10) {
                Text(label).font(Brand.display(10)).tracking(2.4).foregroundStyle(Brand.ink.opacity(0.6))
                Text(channel.displayName.uppercased())
                    .font(Brand.display(38)).foregroundStyle(Brand.ink)
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text(line)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30).padding(.vertical, 20)
            .background(Brand.paper, in: .rect(cornerRadius: 4))
            .padding(.horizontal, 24)
            .rise(0.02, distance: 8)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(channel.displayName): \(label.capitalized). \(line)")
    }
}

/// A title too long for its space glides to its end and back, like the Companion Clock:
/// 2.5 s still, a 45 pt/s ease-in-out glide (a little past the end), 2.5 s still, back.
/// The right edge fades while it can scroll. Reduce Motion: still, cut with "…".
struct Marquee: View {
    /// The text, possibly in more than one font (each run's own font wins over `font`).
    let content: AttributedString
    let font: Font
    var color: Color = Brand.paper

    init(text: String, font: Font, color: Color = Brand.paper) {
        self.content = AttributedString(text); self.font = font; self.color = color
    }

    init(_ content: AttributedString, font: Font, color: Color = Brand.paper) {
        self.content = content; self.font = font; self.color = color
    }

    private var text: String { String(content.characters) }
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var x: CGFloat = 0

    private var overflow: CGFloat { textWidth - boxWidth }
    private var scrolls: Bool { overflow > 4 && !reduce }

    var body: some View {
        // The box takes the space it's offered (a one-line title's height, the row's width);
        // the full-length title is drawn and measured in overlays, which never size the box.
        Text(content).font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background(alignment: .leading) {
                Text(content).font(font).lineLimit(1).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    Text(content).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
                        .offset(x: x)
                } else {
                    Text(content).font(font).foregroundStyle(color).lineLimit(1).truncationMode(.tail)
                }
            }
            .clipped()
            .mask {
                if scrolls {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: max(0, 1 - 28 / max(boxWidth, 1))),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
        .accessibilityLabel(text)
        .task(id: "\(text)|\(Int(textWidth))|\(Int(boxWidth))|\(reduce)") {
            x = 0
            guard scrolls else { return }
            let distance = overflow + 30
            let run = Double(distance / 45)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: run)) { x = -distance }
                try? await Task.sleep(for: .seconds(run + 2.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: run)) { x = 0 }
                try? await Task.sleep(for: .seconds(run))
            }
        }
    }
}
