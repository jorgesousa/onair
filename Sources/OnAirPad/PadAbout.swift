import SwiftUI

/// About ONAIR on iPad: the Mac's card without the updater (the iPad copy comes from Xcode).
struct PadAbout: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    Bars().frame(height: 120)
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in i % 2 == 0 ? Brand.bars[6 - i] : Brand.ink }
                    }
                    .frame(height: 14)
                }
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Brand.name).font(Brand.display(44)).foregroundStyle(Brand.paper).tracking(-0.8)
                        Spacer()
                        Text("v\(version)").font(Brand.mono(13, .semibold)).foregroundStyle(Brand.dim)
                            .accessibilityIdentifier("version")
                    }
                    .rise(0.05)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Brand.line1.uppercased()).font(Brand.display(18)).foregroundStyle(Brand.paper)
                        Text(Brand.promises.joined(separator: " ")).font(.system(size: 15, weight: .medium)).foregroundStyle(Brand.dim)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Brand.stance[0].uppercased()).foregroundStyle(Brand.dim)
                            Text(Brand.stance[1].uppercased()).foregroundStyle(Brand.paper)
                        }
                        .font(Brand.display(14)).padding(.top, 10)
                    }
                    .rise(0.12)
                    Rectangle().fill(Brand.line).frame(height: 1)
                    // The same pieces as the Mac's About: two links out, and Done.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { links; Spacer(); done }
                        VStack(alignment: .leading, spacing: 14) { HStack(spacing: 12) { links }; done }
                    }
                    .rise(0.2)
                    Text("MIT licence. Archivo Black by Omnibus-Type, SIL Open Font License.\nBy Jorge Sousa.")
                        .font(.system(size: 12)).foregroundStyle(Brand.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(28)
            }
        }
        .background(Brand.ink)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var links: some View {
        LinkPill(title: "Source code", symbol: "chevron.left.forwardslash.chevron.right") { openURL(ProjectPages.source) }
        LinkPill(title: "Report a problem", symbol: "exclamationmark.bubble") { openURL(ProjectPages.issues) }
    }

    private var done: some View {
        PrimaryButton(title: "Done") { dismiss() }.accessibilityIdentifier("about-done")
    }
}
