import SwiftUI

/// The bar across the top of the picture, shown for 3 s after a tap. Big targets: hands are
/// busy in a kitchen. Nothing sits top-left of the picture otherwise (that's where the score is).
struct PadControls: View {
    @Environment(PadSession.self) private var session
    let mode: PadLayoutMode
    let expanded: Bool
    let lastName: String?
    let onList: () -> Void
    let onLast: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if mode == .watch {
                control("list.bullet", label: "Channels", id: "list", action: onList)
            }
            if let lastName {
                Button(action: onLast) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 15, weight: .bold))
                        Text(lastName.uppercased()).font(Brand.display(12)).tracking(0.8).lineLimit(1)
                    }
                    .foregroundStyle(Brand.paper)
                    .padding(.horizontal, 18).frame(height: 54)
                    .background(.black.opacity(0.5), in: .capsule)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back to \(lastName)")
                .accessibilityIdentifier("last")
            }
            Spacer(minLength: 0)
            AirPlayButton()
                .frame(width: 54, height: 54)
                .background(.black.opacity(0.5), in: .circle)
            if session.pipAvailable {
                control("pip.enter", label: "Picture in Picture", id: "pip") { session.togglePictureInPicture() }
            }
            if mode == .stacked || expanded {
                control(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        label: expanded ? "Smaller picture" : "Full screen",
                        id: expanded ? "collapse" : "expand", action: onExpand)
            }
        }
    }

    private func control(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(Brand.paper)
                .frame(width: 54, height: 54)
                .background(.black.opacity(0.5), in: .circle)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
