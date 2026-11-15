import SwiftUI

/// The channel list: playlist menu, search, filters, rows. The Mac's rail, sized for fingers.
struct PadRail: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Binding var filter: SidebarItem
    @Binding var search: String
    @Binding var compact: Bool
    let selection: Channel.ID?
    let firstLoad: Bool
    let clock: Date
    let motion: Namespace.ID
    let onPick: (Channel) -> Void
    let onAdd: () -> Void
    let onAbout: () -> Void
    var onSearchFocus: (Bool) -> Void = { _ in }
    /// Under the picture (portrait): one toolbar row instead of the header, search and footer.
    var condensed = false
    @State private var searchOpen = false
    /// The pick came from a tap here: that row is already in view, so don't scroll to it
    /// (in the peek the list is sliding away at the same time; two motions fight).
    @State private var tapped = false
    @FocusState private var searchFocused: Bool
    @AppStorage(PadSession.autoPiPKey) private var autoPiP = true

    private var visible: [Channel] { store.items(for: filter, search: search) }

    var body: some View {
        Group {
            if condensed { condensedBody } else { fullBody }
        }
        .background(Brand.ink)
        .animation(Motion.if(reduce, Motion.fade), value: store.isLoading)
        .animation(Motion.if(reduce, Motion.fade), value: filter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rail")
        .onChange(of: searchFocused) { _, f in onSearchFocus(f) }
    }

    /// One 44 pt row: filters, category, search and the playlist menu. Search opens in its place.
    private var condensedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if searchOpen || !search.isEmpty {
                    HStack(spacing: 8) {
                        searchField
                        Button("Cancel") {
                            search = ""; searchFocused = false
                            withAnimation(Motion.if(reduce, Motion.quick)) { searchOpen = false }
                        }
                        .font(Brand.display(11)).tracking(0.8).foregroundStyle(Brand.dim)
                        .frame(minWidth: 64, minHeight: 44)
                    }
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                } else {
                    HStack(spacing: 6) {
                        filterBar.frame(maxWidth: .infinity)
                        Button {
                            withAnimation(Motion.if(reduce, Motion.quick)) { searchOpen = true }
                            searchFocused = true
                        } label: {
                            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Brand.dim).frame(width: 44, height: 44).contentShape(.rect)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Search channels")
                        playlistMenu
                    }
                    .padding(.leading, 20).padding(.trailing, 8)
                    .transition(.opacity)
                }
            }
            .frame(height: 60)
            Rectangle().fill(Brand.line).frame(height: 1)
            listArea
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Wordmark(size: 17)
                Spacer()
                playlistMenu
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Brand.dim)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Add playlist")
            }
            .padding(.leading, 22).padding(.trailing, 10).padding(.top, 14).padding(.bottom, 12)

            searchField.padding(.horizontal, 16)
            filterBar.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 10)
            Rectangle().fill(Brand.line).frame(height: 1)
            listArea
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.faint)
            TextField("", text: $search, prompt: Text("Search channels").foregroundStyle(Brand.faint))
                .textFieldStyle(.plain).font(.system(size: 17, weight: .medium)).foregroundStyle(Brand.paper)
                .focused($searchFocused)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("search")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Brand.faint)
                        .frame(width: 36, height: 36).contentShape(.rect)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16).padding(.trailing, 6).frame(height: 48)
        .background(Brand.raised, in: .capsule)
        .overlay(Capsule().strokeBorder(Brand.signal.opacity(searchFocused ? 0.7 : 0), lineWidth: 1))
        .animation(Motion.quick, value: searchFocused)
    }

    private var playlistMenu: some View {
        Menu {
            ForEach(store.playlists) { p in
                Button { store.selectedPlaylistID = p.id } label: {
                    if p.id == store.selectedPlaylistID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
            Divider()
            Button("Add playlist…", action: onAdd)
            Button("Reload") { Task { await store.reload() } }
            Toggle("Compact list", isOn: $compact)
            Toggle("Picture in Picture when you leave", isOn: $autoPiP)
            Button("About ONAIR", action: onAbout)
            if let p = store.selectedPlaylist {
                Button("Remove “\(p.name)”", role: .destructive) { store.remove(p) }
            }
        } label: {
            HStack(spacing: 5) {
                Text((store.selectedPlaylist?.name ?? "No playlist").uppercased())
                    .font(Brand.display(11, .semibold)).tracking(1).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
            .foregroundStyle(Brand.dim)
            .frame(minHeight: 44).contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("playlist-menu")
    }

    private var filterBar: some View {
        HStack(alignment: .top, spacing: 22) {
            FilterButton(title: "All", on: filter == .all, motion: motion) { pick(.all) }
            FilterButton(title: "Saved", on: filter == .favorites, motion: motion) { pick(.favorites) }
            FilterButton(title: "Recent", on: filter == .recents, motion: motion) { pick(.recents) }
            Spacer()
            if store.groups.count > 1 {
                let picked: String? = { if case .group(let g) = filter { g } else { nil } }()
                Menu {
                    ForEach(store.groups, id: \.self) { g in Button(g) { pick(.group(g)) } }
                } label: {
                    HStack(spacing: 5) {
                        Tag(text: picked ?? "Category", color: picked != nil ? Brand.signal : Brand.dim)
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .black))
                            .foregroundStyle(picked != nil ? Brand.signal : Brand.dim)
                    }
                    .padding(.bottom, 7)
                    .overlay(alignment: .bottom) {
                        if picked != nil {
                            Bars().frame(height: 3).clipShape(.capsule).matchedGeometryEffect(id: "filter", in: motion)
                        }
                    }
                }
                .menuIndicator(.hidden).fixedSize()
            }
        }
        .frame(minHeight: 30)
    }

    private func pick(_ f: SidebarItem) {
        withAnimation(Motion.if(reduce, Motion.snap)) { filter = f }
    }

    @ViewBuilder private var listArea: some View {
        let list = visible
        if store.isLoading || (!store.hasLoaded && store.error == nil && !store.playlists.isEmpty) {
            RailMessage(title: "Tuning in", detail: nil, busy: true).transition(.identity)
        } else if let e = store.error {
            RailMessage(title: "No signal", detail: e) { Task { await store.reload() } }
        } else if store.playlists.isEmpty {
            RailMessage(title: "Nothing to tune", detail: "Add an M3U playlist or an Xtream Codes account.")
        } else if list.isEmpty {
            RailMessage(title: search.isEmpty ? "Nothing here yet" : "No match",
                        detail: search.isEmpty ? nil : "Nothing called “\(search)”.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                            ChannelRow(number: i + 1, channel: c,
                                       now: store.nowPlaying(c, at: clock), next: store.upNext(c, at: clock),
                                       onAir: c.id == selection, favourite: store.favorites.contains(c.id),
                                       clock: clock, motion: motion, compact: compact)
                                .frame(minHeight: compact ? 44 : 58)
                                .rise(Double(i) * 0.03, distance: 8, active: firstLoad && i < 24,
                                      animation: .timingCurve(0.23, 1, 0.32, 1, duration: 0.3))
                                .id(c.id)
                                .contentShape(.rect)
                                .onTapGesture { searchFocused = false; tapped = true; onPick(c) }
                                .contextMenu {
                                    Button(store.favorites.contains(c.id) ? "Remove from saved" : "Save",
                                           systemImage: store.favorites.contains(c.id) ? "star.slash" : "star") {
                                        store.toggleFavorite(c)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("channel-\(c.displayName)")
                        }
                    }
                    .padding(.vertical, 6)
                    .id(filter)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .scrollIndicators(.never)
                .scrollDismissesKeyboard(.immediately)
                .onAppear { if let selection { proxy.scrollTo(selection, anchor: .center) } }
                .onChange(of: selection) { _, id in
                    if tapped { tapped = false; return }
                    guard let id else { return }
                    withAnimation(Motion.if(reduce, .easeOut(duration: 0.2))) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .transition(.identity)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(visible.count)").font(Brand.mono(12, .semibold)).foregroundStyle(Brand.dim)
                .contentTransition(.numericText())
            Text(" channels").font(Brand.mono(12)).foregroundStyle(Brand.faint)
            Spacer()
        }
        .animation(Motion.if(reduce, Motion.snap), value: visible.count)
        .padding(.horizontal, 22).frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}
