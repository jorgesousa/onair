import SwiftUI

/// One motion vocabulary for the whole app. Fast, decisive, no wobble.
/// Everything collapses to instant when Reduce Motion is on.
enum Motion {
    static let snap = Animation.spring(duration: 0.32, bounce: 0.12)     // the on-air highlight, filters
    static let enter = Animation.spring(duration: 0.5, bounce: 0.08)     // things arriving
    static let fade = Animation.easeOut(duration: 0.35)                   // video in, states
    static let quick = Animation.easeOut(duration: 0.14)                  // hover, press

    static func `if`(_ reduce: Bool, _ a: Animation) -> Animation? { reduce ? nil : a }
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
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : distance)
            .onAppear {
                guard !reduce else { return }
                withAnimation(Motion.enter.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func rise(_ delay: Double = 0, distance: CGFloat = 14) -> some View { modifier(Rise(delay: delay, distance: distance)) }
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
                Brand.ink.frame(height: 56)
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
