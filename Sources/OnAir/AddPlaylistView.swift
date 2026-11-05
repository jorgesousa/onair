import SwiftUI
import UniformTypeIdentifiers

struct AddPlaylistView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    enum Kind: String, CaseIterable { case m3u = "M3U link", xtream = "Xtream Codes", free = "Free" }
    @State private var kind = Kind.m3u
    @State private var name = ""
    @State private var location = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var picking = false

    private var valid: Bool {
        kind == .m3u ? !location.trimmingCharacters(in: .whitespaces).isEmpty
                     : !(server.isEmpty || username.isEmpty || password.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TUNE IN").font(Brand.display(28, .black)).foregroundStyle(Brand.paper)
                Spacer()
                Mark(size: 18)
            }
            Text(kind == .free ? "Public lists of channels that are free to watch." : "Bring your own playlist, or start with a free one.")
                .font(.system(size: 13)).foregroundStyle(Brand.dim).padding(.top, 6)

            HStack(spacing: 6) {
                ForEach(Kind.allCases, id: \.self) { k in
                    Button { withAnimation(Motion.snap) { kind = k } } label: {
                        Text(k.rawValue.uppercased()).font(Brand.display(10, .bold)).tracking(1)
                            .foregroundStyle(kind == k ? Brand.ink : Brand.dim)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(kind == k ? Brand.signal : Brand.raised, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 24).padding(.bottom, 18)

            if kind == .free {
                freeLists
            } else {
            VStack(spacing: 10) {
                Field(label: "Name", text: $name, prompt: "My list")
                if kind == .m3u {
                    HStack(spacing: 8) {
                        Field(label: "Link or file", text: $location, prompt: "http://…/playlist.m3u")
                        Button { picking = true } label: {
                            Image(systemName: "folder").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.paper)
                                .frame(width: 46, height: 46).background(Brand.raised, in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain).help("Choose a file")
                    }
                } else {
                    Field(label: "Server", text: $server, prompt: "http://server:8080")
                    Field(label: "Username", text: $username, prompt: "")
                    Field(label: "Password", text: $password, prompt: "", secure: true)
                }
            }
            .animation(Motion.if(false, Motion.enter), value: kind)

            Text("Use only playlists you're entitled to. Passwords stay in your Keychain.")
                .font(.system(size: 11)).foregroundStyle(Brand.faint).padding(.top, 14)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain).font(Brand.display(10, .bold)).tracking(1).foregroundStyle(Brand.dim)
                    .keyboardShortcut(.cancelAction)
                if kind != .free {
                Button(action: add) {
                    Text("ADD").font(Brand.display(11, .bold)).tracking(1).foregroundStyle(Brand.ink)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Brand.signal.opacity(valid ? 1 : 0.35), in: .capsule)
                        .animation(Motion.quick, value: valid)
                }
                .buttonStyle(PressStyle()).disabled(!valid).keyboardShortcut(.defaultAction)
                .padding(.leading, 18)
                }
            }
            .padding(.top, 26)
        }
        .padding(30)
        // One size for both kinds, so switching never clips the title or the buttons.
        .frame(width: 480, height: 512, alignment: .top)
        .background(Brand.ink)
        .onAppear { if store.playlists.isEmpty { kind = .free } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.plainText, .data]) { result in
            if case .success(let url) = result { location = url.path }
        }
    }

    private var freeLists: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(FreeLists.all.enumerated()), id: \.element.id) { i, list in
                        let existing = store.playlists.first { $0.source == .m3u(location: list.url) }
                        FreeListRow(list: list, added: existing != nil) {
                            if let existing {
                                withAnimation(Motion.snap) { store.remove(existing) }   // toggle off, stay here
                            } else {
                                store.add(Playlist(name: list.name, source: .m3u(location: list.url)), password: nil)
                                dismiss()
                            }
                        }
                        .rise(Double(i) * 0.03, distance: 6)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 286)
            Text("From iptv-org and Free-TV, open projects that only list free, public streams. Some channels may be offline or blocked where you are.")
                .font(.system(size: 11)).foregroundStyle(Brand.faint).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Know another free, legal list?").font(.system(size: 11)).foregroundStyle(Brand.dim)
                Button { openURL(UpdateChecker.suggestListPage) } label: {
                    HStack(spacing: 3) {
                        Text("Suggest a list").font(.system(size: 11, weight: .bold))
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Brand.paper)
                    .underline()
                }
                .buttonStyle(PressStyle()).help("Opens a suggestion on GitHub")
            }
        }
    }

    private func add() {
        let n = name.isEmpty ? (kind == .m3u ? "Playlist" : username) : name
        if kind == .m3u {
            store.add(Playlist(name: n, source: .m3u(location: location.trimmingCharacters(in: .whitespacesAndNewlines))), password: nil)
        } else {
            store.add(Playlist(name: n, source: .xtream(server: XtreamAccount.normalized(server), username: username)), password: password)
        }
        dismiss()
    }
}

private struct Field: View {
    let label: String
    @Binding var text: String
    let prompt: String
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Tag(text: label, color: Brand.faint)
            Group {
                if secure { SecureField("", text: $text) }
                else { TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Brand.faint)) }
            }
            .textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.paper)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(Brand.raised, in: .rect(cornerRadius: 12))
    }
}

private struct FreeListRow: View {
    let list: FreeList
    let added: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name.uppercased()).font(Brand.display(12)).foregroundStyle(Brand.paper)
                    Text(list.detail).font(.system(size: 12)).foregroundStyle(Brand.dim)
                }
                Spacer()
                Text(list.source).font(Brand.mono(10)).foregroundStyle(Brand.faint)
                Image(systemName: added ? (hover ? "xmark" : "checkmark") : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(hover ? Brand.ink : Brand.paper)
                    .frame(width: 26, height: 26)
                    .background(hover ? Brand.paper : (added ? Brand.paper.opacity(0.14) : Brand.raised), in: .circle)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(hover ? Brand.raised : .clear, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .help(added ? "Remove \(list.name)" : "Add \(list.name)")
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
    }
}
