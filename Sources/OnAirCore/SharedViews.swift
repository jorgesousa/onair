import SwiftUI

// Pure SwiftUI pieces both apps draw the same way.

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

/// The channel plays sound but no picture: say so plainly instead of leaving a black screen.
struct SoundOnlyCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 30, weight: .semibold)).foregroundStyle(Brand.paper)
            Text("SOUND ONLY").font(Brand.display(30)).foregroundStyle(Brand.paper)
            Text("This channel isn't sending a picture this Mac can show. Keep listening, or pick another channel.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.dim)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Bars().frame(width: 160, height: 5).clipShape(.capsule)
        }
        .padding(32)
    }
}

struct RailMessage: View {
    let title: String
    let detail: String?
    var busy = false
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if busy { ProgressView().controlSize(.small).tint(Brand.signal) }
            Text(title.uppercased()).font(Brand.display(20, .heavy)).foregroundStyle(Brand.paper)
            if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true) }
            if let retry {
                Button(action: retry) { Tag(text: "Try again", color: Brand.signal) }.buttonStyle(.plain).padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rise()
    }
}

struct Hairline: View {
    let value: Double
    var on: Color = Brand.signal
    var off: Color = Brand.line
    var height: CGFloat = 2
    var body: some View {
        Capsule().fill(off).frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(on).frame(width: max(height, g.size.width * value)) }
            }
            .frame(maxWidth: 220, alignment: .leading)   // updates in place once a minute: data you scan doesn't move
    }
}

struct NowBar: View {
    let channel: Channel
    let now: Programme?
    var next: Programme? = nil
    let clock: Date
    let favourite: Bool
    /// Something each app puts beside the save star (the Mac: its TV button).
    var accessory: AnyView? = nil
    /// Over the picture (window too wide and short for it to sit below): a scrim instead of the ink strip.
    var floating = false
    let toggleFavourite: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Circle().fill(.white).frame(width: 6, height: 6)
                    Text("LIVE").font(Brand.display(9)).tracking(1.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Brand.live, in: .capsule)
                Text(channel.displayName.uppercased()).font(Brand.display(11, .semibold)).tracking(1).foregroundStyle(Brand.dim)
                Spacer()
                if let accessory { accessory }
                IconButton(symbol: favourite ? "star.fill" : "star", help: favourite ? "Remove from saved" : "Save",
                           tint: favourite ? Brand.signal : Brand.dim, action: toggleFavourite)
            }
            if let now {
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    // The programme rolls over: the old title leaves upward, the new one comes from below.
                    Text(now.title).font(Brand.display(26, .heavy)).foregroundStyle(Brand.paper)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .id(now.title)
                        .transition(reduce ? .opacity : .push(from: .bottom))
                    Spacer()
                    Text(now.span).font(Brand.mono(12)).foregroundStyle(Brand.dim)
                        .contentTransition(.numericText())
                }
                .clipped()
                HStack(spacing: 16) {
                    BarsProgress(value: now.progress(at: clock), height: 4).frame(maxWidth: 320)
                    Spacer(minLength: 0)
                    if let next {
                        Text("NEXT \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                            .font(Brand.mono(12)).foregroundStyle(Brand.faint).lineLimit(1)
                            .id(next.title).transition(.opacity)
                    }
                }
            }
        }
        .animation(reduce ? Motion.fade : .easeOut(duration: 0.26), value: now?.title)
        .id(channel.id)
        .transition(reduce ? .opacity : .asymmetric(insertion: .offset(y: 18).combined(with: .opacity), removal: .opacity))
        .padding(.horizontal, 24).padding(.top, floating ? 40 : 18).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background {
            if floating {
                LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top)
            } else {
                Brand.ink.overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
        }
        .animation(reduce ? Motion.fade : Motion.enter, value: channel.id)
    }
}

struct ChannelRow: View {
    let number: Int
    let channel: Channel
    let now: Programme?
    var next: Programme? = nil
    let onAir: Bool
    let favourite: Bool
    let clock: Date
    let motion: Namespace.ID
    var compact = false
    @State private var hover = false

    /// What's on and what's next, on hover. A tooltip, so the row never changes height under the pointer.
    private var guideHelp: String {
        [now.map { "Now: \($0.title)" },
         next.map { "Next: \($0.start.formatted(date: .omitted, time: .shortened)) \($0.title)" }]
            .compactMap { $0 }.joined(separator: "\n")
    }

    private var fg: Color { onAir ? Brand.ink : Brand.paper }
    private var sub: Color { onAir ? Brand.ink.opacity(0.62) : Brand.dim }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(String(format: "%03d", number))
                .font(Brand.mono(11, .semibold))
                .foregroundStyle(onAir ? Brand.ink.opacity(0.7) : Brand.faint)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(channel.displayName.uppercased())
                        .font(Brand.display(12.5, .bold)).tracking(0.3)
                        .foregroundStyle(fg).lineLimit(1)
                    if favourite {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(onAir ? Brand.ink : Brand.signal)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                if let now, !compact {
                    // On hover the line shows what's next, like the now bar's NEXT line. Same height, so nothing moves.
                    Group {
                        if hover, let next {
                            Text("NEXT \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                                .font(Brand.mono(11))
                        } else {
                            Text(now.title).font(.system(size: 12, weight: .medium))
                        }
                    }
                    .foregroundStyle(sub).lineLimit(1)
                    .frame(height: 15, alignment: .leading)
                    Hairline(value: now.progress(at: clock), on: onAir ? Brand.ink : Brand.paper.opacity(0.7),
                             off: onAir ? Brand.ink.opacity(0.15) : Brand.line)
                }
            }
            Spacer(minLength: 8)
            AsyncImage(url: channel.logo) { img in
                img.resizable().scaledToFit()
            } placeholder: { Color.clear }
            .frame(width: 34, height: 22)
            .saturation(onAir || hover ? 1 : 0)
            .opacity(onAir || hover ? 1 : 0.55)
        }
        .padding(.horizontal, 14).padding(.vertical, compact ? 6 : 11)
        .background {
            if onAir {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.signal)
                    .matchedGeometryEffect(id: "onair", in: motion)
            } else if hover {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.raised)
            }
        }
        .padding(.horizontal, 8)
        .onHover { hover = $0 }
        .help(compact ? guideHelp : "")   // compact rows have no programme line: the guide goes in a tooltip
    }
}

struct FilterButton: View {
    let title: String
    let on: Bool
    let motion: Namespace.ID
    var group = "filter"
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Tag(text: title, color: on ? Brand.signal : (hover ? Brand.paper : Brand.dim))
                .padding(.bottom, 7)
                .overlay(alignment: .bottom) {
                    if on {
                        Bars().frame(height: 3).clipShape(.capsule)
                            .matchedGeometryEffect(id: group, in: motion)
                    }
                }
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = Brand.dim
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(hover ? Brand.paper : tint)
                .frame(width: 28, height: 28)
                .background(hover ? Brand.raised : .clear, in: .circle)
        }
        .buttonStyle(PressStyle()).help(help)
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
    }
}

struct KeyHint: View {
    let keys: String
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Text(keys).font(Brand.mono(10, .semibold)).foregroundStyle(Brand.dim)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.line))
            Text(label.uppercased()).font(Brand.display(8.5, .semibold)).tracking(1).foregroundStyle(Brand.faint)
        }
    }
}
