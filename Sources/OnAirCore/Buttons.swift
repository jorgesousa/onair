import SwiftUI

/// The three buttons ONAIR uses everywhere — Mac, iPad and iPhone. Titles of the two action
/// buttons are always set in the display face in capitals; links stay in the system face with
/// an arrow (they leave the app). On touch screens they grow to a 44 pt target.
private var touchScale: CGFloat { Platform.touch > 0 ? 1.2 : 1 }

/// The action that moves you on: Done, Add, Update.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title.uppercased()).font(Brand.display(10 * touchScale)).tracking(1).foregroundStyle(Brand.ink)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 16 * touchScale).padding(.vertical, 9)
                .frame(minHeight: Platform.touch)
                .background(Brand.paper, in: .capsule)
        }
        .buttonStyle(PressStyle())
    }
}

/// The quieter choice beside it: Cancel, Not now.
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title.uppercased()).font(Brand.display(10 * touchScale)).tracking(1).foregroundStyle(hover ? Brand.paper : Brand.dim)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 14 * touchScale).padding(.vertical, 8)
                .frame(minHeight: Platform.touch)
                .overlay(Capsule().strokeBorder(Brand.line, lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
    }
}

/// A link that leaves the app (the source code, reporting a problem).
struct LinkPill: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11 * touchScale, weight: .semibold))
                Text(title).font(.system(size: 12 * touchScale, weight: .semibold)).lineLimit(1).fixedSize()
                Image(systemName: "arrow.up.right").font(.system(size: 9 * touchScale, weight: .bold)).opacity(0.6)
            }
            .foregroundStyle(hover ? Brand.paper : Brand.dim)
            .padding(.horizontal, 12 * touchScale).padding(.vertical, 8)
            .frame(minHeight: Platform.touch)
            .background(hover ? Brand.raised : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(Brand.line, lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
    }
}

/// The project's pages, for About on every device.
enum ProjectPages {
    static let source = URL(string: "https://github.com/jorgesousa/onair")!
    static let issues = source.appendingPathComponent("issues")
}

/// The playlist menu's label (HOME ⌄): the same on Mac, iPad and iPhone, sized to where it sits.
struct PlaylistLabel: View {
    let name: String
    var size: CGFloat = 9.5
    var body: some View {
        // One Text, chevron inside it: a macOS menu moves a separate icon to the left of its label.
        (Text(name.uppercased()).font(Brand.display(size, .semibold)).tracking(1.2)
            + Text("  ")
            + Text(Image(systemName: "chevron.down")).font(.system(size: size * 0.8, weight: .black)))
        .lineLimit(1)
        .foregroundStyle(Brand.dim)
        .fixedSize()
    }
}
