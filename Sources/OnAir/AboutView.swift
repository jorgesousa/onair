import SwiftUI

/// About ONAIR: the promise, the version, updates, and where the code lives.
struct AboutView: View {
    @Environment(UpdateChecker.self) private var updates
    @Environment(\.openURL) private var openURL
    @State private var showUpdate = false

    var body: some View {
        @Bindable var updates = updates
        VStack(alignment: .leading, spacing: 0) {
            // The card, edge to edge.
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
                    Text("v\(updates.currentVersion)").font(Brand.mono(12, .semibold)).foregroundStyle(Brand.dim)
                }
                .rise(0.05)

                VStack(alignment: .leading, spacing: 6) {
                    Text(Brand.line1.uppercased()).font(Brand.display(18)).foregroundStyle(Brand.paper)
                    Text(Brand.promises.joined(separator: " ")).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.dim)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Brand.stance[0].uppercased()).foregroundStyle(Brand.dim)
                        Text(Brand.stance[1].uppercased()).foregroundStyle(Brand.paper)
                    }
                    .font(Brand.display(13)).padding(.top, 10)
                }
                .rise(0.12)

                updateBlock.rise(0.2)

                Rectangle().fill(Brand.line).frame(height: 1)

                HStack(spacing: 10) {
                    LinkPill(title: "Source code", symbol: "chevron.left.forwardslash.chevron.right") { openURL(UpdateChecker.repoPage) }
                    LinkPill(title: "Report a problem", symbol: "exclamationmark.bubble") { openURL(UpdateChecker.issuesPage) }
                }
                .rise(0.26)

                Text("MIT licence. Archivo Black by Omnibus-Type, SIL Open Font License.\nBy Jorge Sousa.")
                    .font(.system(size: 11)).foregroundStyle(Brand.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
        }
        .frame(width: 480)
        .background(Brand.ink)
        .preferredColorScheme(.dark)
        .task { await updates.checkIfStale() }
        .sheet(isPresented: $showUpdate) {
            if let r = updates.available { UpdateSheet(release: r, current: updates.currentVersion) }
        }
    }

    @ViewBuilder private var updateBlock: some View {
        @Bindable var updates = updates
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let r = updates.available {
                    VStack(alignment: .leading, spacing: 6) {
                        UpdateTag(version: r.version)
                        Text("Version \(r.version) is out.").font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.paper)
                    }
                    Spacer()
                    PrimaryButton(title: "Update") { showUpdate = true }
                } else {
                    Text(updates.checking ? "Checking…" : (updates.lastResult ?? "Updates are checked once a day."))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.dim)
                        .contentTransition(.opacity)
                    Spacer()
                    SecondaryButton(title: "Check now") { Task { await updates.check() } }
                        .disabled(updates.checking)
                }
            }
            .animation(Motion.fade, value: updates.checking)
            .animation(Motion.enter, value: updates.available)
            Toggle(isOn: $updates.automatic) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates automatically").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.paper)
                    Text("One request to GitHub a day, with nothing about you in it.").font(.system(size: 11)).foregroundStyle(Brand.faint)
                }
            }
            .toggleStyle(.switch).controlSize(.small).tint(Brand.bars[3])
        }
        .padding(16)
        .background(Brand.raised, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// How to get the new version, for the way this copy was installed.
struct UpdateSheet: View {
    let release: UpdateChecker.Release
    let current: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Homebrew keeps the app under …/Cellar/onair/<version>/OnAir.app (reached through opt/ or a link).
    private var viaHomebrew: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path.contains("/Cellar/onair/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("UPDATE TO \(release.version)").font(Brand.display(26)).foregroundStyle(Brand.paper)
                Spacer()
                Text("you have \(current)").font(Brand.mono(11)).foregroundStyle(Brand.dim)
            }
            Bars().frame(height: 4).clipShape(.capsule)
            if viaHomebrew {
                Text("ONAIR was installed with Homebrew. Quit ONAIR, then run this in Terminal:")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.paper)
                    .fixedSize(horizontal: false, vertical: true)
                Command(label: "Terminal", text: "brew update\nbrew upgrade onair")
                Text("Then open ONAIR again. Your lists, saved channels and passwords are kept. Homebrew in a separate admin account? Run both commands from that account.")
                    .font(.system(size: 12)).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This copy was built from source. Quit ONAIR, then run this in Terminal, in the folder where you cloned it:")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.paper)
                    .fixedSize(horizontal: false, vertical: true)
                Command(label: "Terminal", text: "git pull\nscripts/build-app.sh --install")
                Text("Prefer updates in one command? Install with Homebrew instead: brew install jorgesousa/tap/onair")
                    .font(.system(size: 12)).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                SecondaryButton(title: "What's new") { openURL(release.page) }
                Spacer()
                PrimaryButton(title: "Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Brand.ink)
    }
}

struct UpdateTag: View {
    let version: String
    var body: some View {
        HStack(spacing: 6) {
            Mark(size: 9)
            Text("UPDATE \(version)").font(Brand.display(9)).tracking(1.2).foregroundStyle(Brand.ink)
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Brand.paper, in: .capsule)
    }
}

private struct Command: View {
    let label: String
    let text: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Tag(text: label, color: Brand.faint)
            HStack {
                Text(text).font(Brand.mono(12, .semibold)).foregroundStyle(Brand.paper).textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(Motion.quick) { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.4)); withAnimation(Motion.fade) { copied = false } }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copied ? Brand.paper : Brand.dim).frame(width: 24, height: 24)
                }
                .buttonStyle(PressStyle()).help("Copy")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Brand.raised, in: .rect(cornerRadius: 10, style: .continuous))
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title.uppercased()).font(Brand.display(10)).tracking(1).foregroundStyle(Brand.ink)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Brand.paper, in: .capsule)
        }
        .buttonStyle(PressStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title.uppercased()).font(Brand.display(10)).tracking(1).foregroundStyle(hover ? Brand.paper : Brand.dim)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(Brand.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
    }
}

private struct LinkPill: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).opacity(0.6)
            }
            .foregroundStyle(hover ? Brand.paper : Brand.dim)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(hover ? Brand.raised : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(Brand.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
    }
}
