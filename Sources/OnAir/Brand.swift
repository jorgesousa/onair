import SwiftUI
import AppKit
import CoreText

/// ONAIR · "Test Card". Black and white like a broadcast monitor; the seven colour bars
/// appear only where the signal is: the mark, tuning, progress, the selected filter.
/// See docs/BRAND.md.
enum Brand {
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.063)      // #0E0E10
    static let raised = Color(red: 0.094, green: 0.094, blue: 0.106)   // #18181B
    static let line = Color.white.opacity(0.09)
    static let paper = Color(red: 0.949, green: 0.941, blue: 0.918)    // #F2F0EA
    static let dim = paper.opacity(0.55)
    static let faint = paper.opacity(0.3)
    /// What is on air: inverted to paper. Colour is kept for the bars.
    static let signal = paper
    /// LIVE only. Never used for errors.
    static let live = Color(red: 0.91, green: 0.2, blue: 0.165)        // #E8332A
    /// Colour bars, left to right.
    static let bars: [Color] = [
        Color(red: 0.949, green: 0.941, blue: 0.918),  // white   #F2F0EA
        Color(red: 0.961, green: 0.851, blue: 0.039),  // yellow  #F5D90A
        Color(red: 0.145, green: 0.839, blue: 0.898),  // cyan    #25D6E5
        Color(red: 0.169, green: 0.831, blue: 0.306),  // green   #2BD44E
        Color(red: 0.91,  green: 0.235, blue: 0.784),  // magenta #E83CC8
        Color(red: 0.91,  green: 0.2,   blue: 0.165),  // red     #E8332A
        Color(red: 0.165, green: 0.231, blue: 0.91),   // blue    #2A3BE8
    ]

    static let name = "ONAIR"
    static let line1 = "Just TV."
    static let promises = ["No ads.", "No watermarks.", "No accounts.", "No tracking."]
    /// The second half of the promise: free software doesn't get to look or feel worse.
    static let stance = ["Free and open source.", "Built like it isn't."]
    static let coda = "Open source. No compromise."

    /// Archivo Black, bundled (SIL OFL). One weight; `weight` stays so call sites read the same.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
        .custom("Archivo Black", size: size)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "ArchivoBlack", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// The colour bars, as a strip. The mark, progress and the selected filter are drawn with it.
struct Bars: View {
    var body: some View {
        HStack(spacing: 0) { ForEach(0..<Brand.bars.count, id: \.self) { Brand.bars[$0] } }
    }
}

/// Progress in bars: the elapsed part shows the bars, the rest is a hairline.
struct BarsProgress: View {
    let value: Double
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.line)
                Bars().frame(width: g.size.width)
                    .mask(alignment: .leading) { Capsule().frame(width: max(height, g.size.width * value)) }
            }
        }
        .frame(height: height)
        .animation(Motion.enter, value: value)
    }
}

/// The mark: the seven bars in a tile.
struct Mark: View {
    var size: CGFloat = 16
    var body: some View {
        Bars().frame(width: size * 1.3, height: size)
            .clipShape(.rect(cornerRadius: size * 0.2, style: .continuous))
    }
}

struct Wordmark: View {
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: size * 0.45) {
            Mark(size: size * 0.95)
            Text(Brand.name).font(Brand.display(size)).tracking(size * 0.04)
                .foregroundStyle(Brand.paper)
        }
    }
}

/// Small caps label in the display face. Used for LIVE, NOW, filters.
struct Tag: View {
    let text: String
    var color: Color = Brand.dim
    var body: some View {
        Text(text.uppercased()).font(Brand.display(9.5, .semibold)).tracking(1.2).foregroundStyle(color)
            .lineLimit(1).fixedSize()
    }
}

/// The empty stage says what this is, and nothing else.
struct Manifesto: View {
    var action: (title: String, run: () -> Void)? = nil
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { geo in
            let big = min(geo.size.width * 0.15, 112)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text("JUST")
                    .font(Brand.display(big)).foregroundStyle(Brand.paper).tracking(-big * 0.02)
                    .rise(0.0, distance: 24)
                HStack(alignment: .center, spacing: big * 0.14) {
                    Text("TV").font(Brand.display(big)).foregroundStyle(Brand.paper)
                    Bars()
                        .frame(width: big * 0.9, height: big * 0.6)
                        .clipShape(.rect(cornerRadius: big * 0.05, style: .continuous))
                        .opacity(on ? 1 : 0.6)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: on)
                }
                .padding(.top, -big * 0.28)
                .rise(0.08, distance: 24)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Brand.promises.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(size: 17, weight: .semibold)).foregroundStyle(Brand.dim)
                            .rise(0.22 + Double(i) * 0.07)
                    }
                }
                .padding(.top, 28)
                if let action {
                    Button(action: action.run) {
                        Text(action.title.uppercased()).font(Brand.display(12, .bold)).tracking(1)
                            .foregroundStyle(Brand.ink)
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .background(Brand.signal, in: .capsule)
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 32)
                    .rise(0.55)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Brand.stance[0].uppercased()).foregroundStyle(Brand.dim)
                        Text(Brand.stance[1].uppercased()).foregroundStyle(Brand.paper)
                    }
                    .font(Brand.display(min(big * 0.26, 24)))
                    Spacer()
                    Wordmark(size: 11)
                }
                .rise(0.7, distance: 8)
            }
            .padding(48)
        }
        .background(Brand.ink)
        .onAppear { if !reduce { on = true } }
    }
}
