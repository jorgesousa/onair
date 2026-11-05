import SwiftUI

extension Notification.Name {
    static let nextChannel = Notification.Name("OnAir.nextChannel")
    static let previousChannel = Notification.Name("OnAir.previousChannel")
}

extension Channel {
    /// "PT: RTP 1" → "RTP 1". Country prefixes are noise once you've picked a list.
    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        var out = n
        if let r = out.range(of: #"^[A-Z]{2,4}\s*[:|\-]\s*"#, options: .regularExpression) { out = String(out[r.upperBound...]) }
        // Trailing tags lists add for machines: "(1080p)", "[Not 24/7]", "[Geo-blocked]".
        out = out.replacingOccurrences(of: #"(\s*(\(\d{3,4}[pi]\)|\[[^\]]*\]))+\s*$"#, with: "", options: .regularExpression)
        return out.isEmpty ? n : out
    }
}

struct ContentView: View {
    /// Movies and series are hidden for now; the code stays. Set to true to bring them back.
    static let showsLibraries = false

    @Environment(Store.self) private var store
    @Environment(UpdateChecker.self) private var updates
    @State private var showUpdate = false
    @State private var playback = PlaybackController()
    @State private var filter: SidebarItem = .all
    @State private var search = ""
    @State private var selection: Channel.ID?
    @State private var openSeries: Series?
    @State private var showAdd = false
    @State private var clock = Date.now
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool
    @Namespace private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var visible: [Channel] { store.items(for: filter, search: search) }

    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 360)
            Rectangle().fill(Brand.line).frame(width: 1)
            stage
        }
        .background(Brand.ink)
        .ignoresSafeArea()
        .sheet(isPresented: $showAdd) { AddPlaylistView() }
        .sheet(isPresented: $showUpdate) {
            if let r = updates.available { UpdateSheet(release: r, current: updates.currentVersion) }
        }
        .animation(Motion.if(reduce, Motion.enter), value: updates.available)
        .sheet(item: $openSeries) { s in
            EpisodesView(series: s) { ep in
                playback.play(Channel(name: "\(s.name) · S\(ep.season) E\(ep.number)", group: s.group, logo: s.cover, url: ep.url))
                openSeries = nil
            }
        }
        .onChange(of: store.selectedPlaylistID) { _, _ in
            store.reset(); filter = .all; selection = nil
            Task { await store.loadIfNeeded() }
        }
        .onChange(of: store.library) { _, _ in
            filter = .all; selection = nil; search = ""
            Task { await store.loadIfNeeded() }
        }
        .task { await store.loadIfNeeded() }
        .onChange(of: selection) { _, id in
            guard let id, let c = store.items.first(where: { $0.id == id }) else { return }
            if store.library == .series, let sid = Int(c.url.absoluteString.dropFirst(7)),
               let s = store.series.first(where: { $0.id == sid }) {
                openSeries = s
            } else {
                playback.play(c)
                store.markPlayed(c)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextChannel)) { _ in step(1) }
        .onReceive(NotificationCenter.default.publisher(for: .previousChannel)) { _ in step(-1) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                clock = .now
                await store.loadGuide()
            }
        }
    }

    private func step(_ delta: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : list.count)
        withAnimation(Motion.if(reduce, Motion.snap)) {
            selection = list[(i + delta + list.count) % list.count].id
        }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Wordmark(size: 15)
                Spacer()
                playlistMenu
                IconButton(symbol: "plus", help: "Add playlist") { showAdd = true }
            }
            .padding(.leading, 22).padding(.trailing, 14)
            .padding(.top, 46).padding(.bottom, 18)

            if Self.showsLibraries, store.account != nil { libraryBar }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.faint)
                TextField("", text: $search, prompt: Text("Search channels").foregroundStyle(Brand.faint))
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.paper)
                    .focused($searchFocused)
                if !search.isEmpty {
                    IconButton(symbol: "xmark", help: "Clear") { search = "" }
                }
            }
            .padding(.horizontal, 14).frame(height: 36)
            .background(Brand.raised, in: .capsule)
            .overlay(Capsule().strokeBorder(Brand.signal.opacity(searchFocused ? 0.7 : 0), lineWidth: 1))
            .animation(Motion.quick, value: searchFocused)
            .padding(.horizontal, 16)

            filterBar.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 10)
            Rectangle().fill(Brand.line).frame(height: 1)
            listArea
            footer
        }
        .background(Brand.ink)
        .animation(Motion.if(reduce, Motion.fade), value: store.isLoading)
        .animation(Motion.if(reduce, Motion.fade), value: filter)
    }

    private var playlistMenu: some View {
        Menu {
            ForEach(store.playlists) { p in
                Button { store.selectedPlaylistID = p.id } label: {
                    if p.id == store.selectedPlaylistID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
            Divider()
            Button("Add playlist…") { showAdd = true }
            Button("Reload") { Task { await store.reload() } }
            if let p = store.selectedPlaylist {
                Button("Remove “\(p.name)”", role: .destructive) { store.remove(p) }
            }
        } label: {
            Text((store.selectedPlaylist?.name ?? "No playlist").uppercased())
                .font(Brand.display(9.5, .semibold)).tracking(1).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(Brand.dim)
        .fixedSize()
        .disabled(store.playlists.isEmpty)
    }

    private var libraryBar: some View {
        HStack(spacing: 18) {
            ForEach(Library.allCases) { l in
                FilterButton(title: l.rawValue, on: store.library == l, motion: motion, group: "library") { store.library = l }
            }
        }
        .padding(.horizontal, 22).padding(.bottom, 14)
    }

    private var filterBar: some View {
        HStack(alignment: .top, spacing: 18) {
            FilterButton(title: "All", on: filter == .all, motion: motion) { withAnimation(Motion.if(reduce, Motion.snap)) { filter = .all } }
            FilterButton(title: "Saved", on: filter == .favorites, motion: motion) { withAnimation(Motion.if(reduce, Motion.snap)) { filter = .favorites } }
            FilterButton(title: "Recent", on: filter == .recents, motion: motion) { withAnimation(Motion.if(reduce, Motion.snap)) { filter = .recents } }
            Spacer()
            if store.groups.count > 1 {
                let picked: String? = { if case .group(let g) = filter { g } else { nil } }()
                Menu {
                    ForEach(store.groups, id: \.self) { g in
                        Button(g) { withAnimation(Motion.if(reduce, Motion.snap)) { filter = .group(g) } }
                    }
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
                .menuStyle(.button).buttonStyle(PressStyle()).menuIndicator(.hidden).fixedSize()
            }
        }
    }

    @ViewBuilder private var listArea: some View {
        let list = visible
        if store.isLoading {
            RailMessage(title: "Tuning in", detail: nil, busy: true)
        } else if let e = store.error {
            RailMessage(title: "No signal", detail: e) { Task { await store.reload() } }
        } else if store.playlists.isEmpty {
            RailMessage(title: "Nothing to tune", detail: "Add an M3U playlist or an Xtream Codes account.")
        } else if list.isEmpty {
            RailMessage(title: search.isEmpty ? "Nothing here yet" : "No match", detail: search.isEmpty ? nil : "Nothing called “\(search)”.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                            ChannelRow(number: i + 1, channel: c,
                                       now: store.library == .live ? store.nowPlaying(c, at: clock) : nil,
                                       onAir: c.id == selection,
                                       favourite: store.favorites.contains(c.id), clock: clock, motion: motion)
                                .id(c.id)
                                .contentShape(.rect)
                                .onTapGesture {
                                    withAnimation(Motion.if(reduce, Motion.snap)) { selection = c.id }
                                    listFocused = true
                                }
                                .contextMenu {
                                    Button(store.favorites.contains(c.id) ? "Remove from saved" : "Save") {
                                        store.toggleFavorite(c)
                                    }
                                    if store.library != .series {
                                        Button("Copy stream URL") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(c.url.absoluteString, forType: .string)
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                    .id(filter)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .scrollIndicators(.never)
                .focusable()
                .focused($listFocused)
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { step(1); return .handled }
                .onKeyPress(.upArrow) { step(-1); return .handled }
                .onKeyPress(.return) {
                    guard playback.current != nil else { return .ignored }
                    NSApp.keyWindow?.toggleFullScreen(nil)
                    return .handled
                }
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(visible.count)").font(Brand.mono(11, .semibold)).foregroundStyle(Brand.dim)
                    .contentTransition(.numericText())
                Text(store.library == .live ? " channels" : store.library == .movies ? " films" : " series")
                    .font(Brand.mono(11)).foregroundStyle(Brand.faint)
            }
            .lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            if let r = updates.available {
                // a new version takes the place of the key hints
                Button { showUpdate = true } label: { UpdateTag(version: r.version) }
                    .buttonStyle(PressStyle()).help("ONAIR \(r.version) is out. Click for how to update.")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                KeyHint(keys: "↑↓", label: "Zap")
                KeyHint(keys: "⏎", label: "Full")
            }
        }
        .animation(Motion.if(reduce, Motion.snap), value: visible.count)
        .padding(.horizontal, 22).frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    // MARK: Stage

    @ViewBuilder private var stage: some View {
        if let c = playback.current {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Color.black
                    PlayerView(player: playback.player)
                        .opacity(playback.isTuning ? 0 : 1)
                    if playback.isTuning {
                        TuningView(channel: c).id(c.id)
                            .transition(.opacity)
                    }
                    if let f = playback.failed {
                        HStack(spacing: 10) {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Brand.ink)
                            Text(f).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.ink)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Brand.signal, in: .capsule)
                        .padding(20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(Motion.if(reduce, Motion.fade), value: playback.isTuning)
                .animation(Motion.if(reduce, Motion.enter), value: playback.failed)
                NowBar(channel: c, now: store.nowPlaying(c, at: clock), clock: clock,
                       favourite: store.favorites.contains(c.id)) { store.toggleFavorite(c) }
            }
            .transition(.opacity)
        } else {
            Manifesto(action: store.playlists.isEmpty ? ("Add a playlist", { showAdd = true }) : nil)
        }
    }
}

// MARK: Pieces

struct ChannelRow: View {
    let number: Int
    let channel: Channel
    let now: Programme?
    let onAir: Bool
    let favourite: Bool
    let clock: Date
    let motion: Namespace.ID
    @State private var hover = false

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
                if let now {
                    Text(now.title).font(.system(size: 12, weight: .medium)).foregroundStyle(sub).lineLimit(1)
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
        .padding(.horizontal, 14).padding(.vertical, 11)
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
        .animation(.easeOut(duration: 0.14), value: hover)
        .animation(Motion.snap, value: onAir)
    }
}

struct NowBar: View {
    let channel: Channel
    let now: Programme?
    let clock: Date
    let favourite: Bool
    let toggleFavourite: () -> Void

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
                IconButton(symbol: favourite ? "star.fill" : "star", help: favourite ? "Remove from saved" : "Save",
                           tint: favourite ? Brand.signal : Brand.dim, action: toggleFavourite)
            }
            if let now {
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    Text(now.title).font(Brand.display(26, .heavy)).foregroundStyle(Brand.paper)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.opacity)
                    Spacer()
                    Text(now.span).font(Brand.mono(12)).foregroundStyle(Brand.dim)
                }
                BarsProgress(value: now.progress(at: clock), height: 4).frame(maxWidth: 320)
            }
        }
        .id(channel.id)
        .transition(.asymmetric(insertion: .offset(y: 18).combined(with: .opacity), removal: .opacity))
        .padding(.horizontal, 24).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(Brand.ink)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
        .animation(Motion.enter, value: channel.id)
        .animation(Motion.fade, value: now)
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
            .animation(Motion.enter, value: value)
            .frame(maxWidth: 220, alignment: .leading)
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

struct EpisodesView: View {
    let series: Series
    let onPlay: (Episode) -> Void
    @Environment(Store.self) private var store
    @Environment(UpdateChecker.self) private var updates
    @State private var showUpdate = false
    @Environment(\.dismiss) private var dismiss
    @State private var episodes: [Episode] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: series.cover) { $0.resizable().scaledToFit() } placeholder: { Brand.raised }
                    .frame(width: 80, height: 116).clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 8) {
                    Text(series.name.uppercased()).font(Brand.display(20, .heavy)).foregroundStyle(Brand.paper)
                    if let p = series.plot, !p.isEmpty { Text(p).font(.system(size: 13)).foregroundStyle(Brand.dim).lineLimit(5) }
                }
                Spacer()
                IconButton(symbol: "xmark", help: "Close") { dismiss() }
            }
            .padding(24)
            Rectangle().fill(Brand.line).frame(height: 1)
            if loading {
                ProgressView().tint(Brand.signal).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                RailMessage(title: "No episodes", detail: error)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Dictionary(grouping: episodes, by: \.season).keys.sorted(), id: \.self) { season in
                            Tag(text: "Season \(season)").padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 6)
                            ForEach(episodes.filter { $0.season == season }) { ep in
                                Button { onPlay(ep) } label: {
                                    HStack(spacing: 14) {
                                        Text(String(format: "%02d", ep.number)).font(Brand.mono(11, .semibold)).foregroundStyle(Brand.faint)
                                        Text(ep.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.paper).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(Brand.signal)
                                    }
                                    .padding(.horizontal, 24).padding(.vertical, 10).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 540, height: 580)
        .background(Brand.ink)
        .task {
            defer { loading = false }
            guard let a = store.account else { error = "This needs an Xtream Codes account."; return }
            do {
                episodes = try await a.episodes(of: series.id)
                if episodes.isEmpty { error = "This series has no episodes." }
            } catch { self.error = error.localizedDescription }
        }
    }
}
