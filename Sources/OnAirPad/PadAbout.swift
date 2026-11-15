import SwiftUI

/// About ONAIR on iPad: the Mac's card without the updater (the iPad copy comes from Xcode).
struct PadAbout: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let source = URL(string: "https://github.com/jorgesousa/onair")!

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
                    HStack(spacing: 12) {
                        Button { openURL(source) } label: {
                            Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(Brand.display(11)).tracking(0.8).foregroundStyle(Brand.paper)
                                .padding(.horizontal, 18).frame(minHeight: 44)
                                .background(Brand.raised, in: .capsule)
                        }
                        .buttonStyle(PressStyle())
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(Brand.display(12)).foregroundStyle(Brand.ink)
                            .padding(.horizontal, 22).frame(minHeight: 44)
                            .background(Brand.paper, in: .capsule)
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("about-done")
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
}
