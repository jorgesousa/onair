import SwiftUI

extension Notification.Name {
    static let nextChannel = Notification.Name("OnAir.nextChannel")
    static let previousChannel = Notification.Name("OnAir.previousChannel")
}

struct ContentView: View {
    /// Movies and series are hidden for now; the code stays. Set to true to bring them back.
    static let showsLibraries = false

    @Environment(Store.self) private var store
    @Environment(UpdateChecker.self) private var updates
    @State private var showUpdate = false
    @State private var playback = PlaybackController()
    @State private var tv = TVScreen()
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

    // Watch mode: full screen, the list and the now bar step aside.
    @State private var watching = false
    @State private var peek = false                 // the list back over the picture, from the left edge
    @State private var peekTask: Task<Void, Never>?
    @State private var chrome = false               // channel card / floating bar, woken by the mouse or a zap
    @State private var chromeTask: Task<Void, Never>?
    @State private var typed = ""                   // digits typed to zap by number
    @State private var typedTask: Task<Void, Never>?
    @State private var lastChannel: Channel.ID?     // ⌫ flips back to it
    @State private var keyed = false                // selection changed from the keyboard: no slide, no scroll animation
    @State private var firstLoad = false            // rows rise in once, when a list first arrives
    @State private var armFirstLoad = false         // set by adding or switching a playlist; never on launch, reload, filters or search
    @State private var hostWindow: NSWindow?
    @State private var keyMonitor: Any?
    @AppStorage("compactList") private var compact = false
    @State private var pip = false                  // the picture is in Picture in Picture
    @State private var controlsAwake = false        // AVKit's controls in Watch mode: the mouse only, not a zap

    private var visible: [Channel] { store.items(for: filter, search: search) }
    /// Watch mode hides the list only once something is on: with nothing playing you need it to pick.
    private var listAside: Bool { watching && playback.current != nil }

    var body: some View {
        HStack(spacing: 0) {
            if !listAside {
                HStack(spacing: 0) {
                    rail.frame(width: 360)
                    Rectangle().fill(Brand.line).frame(width: 1)
                }
                .transition(.move(edge: .leading))     // leaves to the left, comes back from the left
            }
            stage
        }
        .animation(Motion.if(reduce, .easeOut(duration: 0.22)), value: listAside)
        .overlay(alignment: .leading) { peekLayer }
        .background(Brand.ink)
        .background(WindowReader { w in
            hostWindow = w
            // macOS can reopen the window already in full screen: that is Watch mode too.
            if w.styleMask.contains(.fullScreen) { watching = true }
        })
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
            armFirstLoad = true
            store.reset(); filter = .all; selection = nil
            Task { await store.loadIfNeeded() }
        }
        .onChange(of: store.library) { _, _ in
            filter = .all; selection = nil; search = ""
            Task { await store.loadIfNeeded() }
        }
        .task { await store.loadIfNeeded() }
        .onChange(of: selection) { old, id in
            if let old, old != id { lastChannel = old }
            if watching, peek { closePeek(after: 0) }
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
        // Full screen is Watch mode. Once the window has grown, the list and the bar step aside;
        // on the way out they come back as the window starts to shrink.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { n in
            guard n.object as? NSWindow === hostWindow else { return }
            peek = false
            withAnimation(Motion.if(reduce, .easeOut(duration: 0.22))) { watching = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { n in
            guard n.object as? NSWindow === hostWindow else { return }
            peek = false; chrome = false
            withAnimation(Motion.if(reduce, .easeOut(duration: 0.22))) { watching = false }
        }
        .onChange(of: playback.current?.id) { _, _ in wake(instant: true) }
        // Home (Dispatcharr): one TV, several screens. Picking goes through the selection, as a click does.
        .followsHome(playback: playback) { c in withAnimation(Motion.if(reduce, Motion.snap)) { selection = c.id } }
        // Armed when loading starts, so the rows already know it when they first appear.
        .onChange(of: store.isLoading) { _, loading in
            if loading {
                if armFirstLoad { firstLoad = true; armFirstLoad = false }
                return
            }
            Task { @MainActor in try? await Task.sleep(for: .seconds(1.2)); firstLoad = false }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                MainActor.assumeIsolated { handleKey(e) } ? nil : e
            }
        }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
        // The Mac slept, or the network came back: the old stream is dead, start a fresh one.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            playback.reconnectNow(reason: "wake")
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                clock = .now
                await store.loadGuide()
            }
        }
    }

    private func step(_ delta: Int) {
        guard let id = Zap.step(from: selection, in: visible.map(\.id), by: delta) else { return }
        select(id, keyed: true)
    }

    /// Clicks slide the on-air highlight; keys (↑↓, numbers, ⌫) jump, because they repeat all evening.
    private func select(_ id: Channel.ID?, keyed byKey: Bool) {
        keyed = byKey
        if byKey {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { selection = id }
        } else {
            withAnimation(Motion.if(reduce, Motion.snap)) { selection = id }
        }
    }

    /// Keys that work anywhere in the window, except while typing in a field or a sheet is open.
    private func handleKey(_ e: NSEvent) -> Bool {
        guard let w = hostWindow, e.window === w, w.attachedSheet == nil else { return false }
        if searchFocused { return false }
        if let r = w.firstResponder as? NSText, r.isFieldEditor { return false }
        guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch e.keyCode {
        case 53 where watching:                       // esc
            if peek { closePeek(after: 0) } else { w.toggleFullScreen(nil) }
            return true
        case 36 where !peek && playback.current != nil:   // return: Watch mode on and off
            w.toggleFullScreen(nil); return true
        case 125 where watching && !peek: step(1); return true    // ↓
        case 126 where watching && !peek: step(-1); return true   // ↑
        case 51:                                      // ⌫: back to the last channel
            guard let last = lastChannel else { return false }
            select(last, keyed: true); return true
        default:
            guard let d = e.charactersIgnoringModifiers, d.count == 1, let n = Int(d) else { return false }
            type(n); return true
        }
    }

    /// Typing 0, 1, 5 tunes 015, like a remote. Waits a moment for more digits, or tunes at three.
    private func type(_ digit: Int) {
        typedTask?.cancel()
        typed += String(digit)
        if watching { wake(instant: true) }     // the card shows the digits as you type
        if Zap.shouldCommit(typed: typed, count: visible.count) { commitTyped(); return }
        typedTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            commitTyped()
        }
    }

    private func commitTyped() {
        if let id = Zap.channel(forTyped: typed, in: visible.map(\.id)) { select(id, keyed: true) }
        typed = ""
    }

    /// Shows the channel card (Watch mode) or the floating now bar, then hides it after 3 s.
    /// A zap shows it at once; the mouse fades it in.
    private func wake(instant: Bool) {
        chromeTask?.cancel()
        if !instant { controlsAwake = true }
        if !chrome {
            if instant || reduce {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { chrome = true }
            } else {
                withAnimation(.easeOut(duration: 0.15)) { chrome = true }
            }
        }
        chromeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            // The card after a zap fades in 200 ms; the card and controls woken by the mouse in 260 ms.
            withAnimation(Motion.if(reduce, .easeOut(duration: controlsAwake ? 0.26 : 0.2))) { chrome = false }
            controlsAwake = false
            if watching, !peek { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }

    private func openPeek() {
        peekTask?.cancel()
        withAnimation(Motion.if(reduce, .easeOut(duration: 0.22))) { peek = true }
    }

    private func closePeek(after delay: Double) {
        peekTask?.cancel()
        peekTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.if(reduce, .easeOut(duration: 0.22))) { peek = false }
        }
    }

    /// In Watch mode: an 8-point strip at the left edge brings the list back over the picture.
    @ViewBuilder private var peekLayer: some View {
        if listAside {
            if peek {
                rail.frame(width: 360)
                    .overlay(alignment: .trailing) { Rectangle().fill(Brand.line).frame(width: 1) }
                    .shadow(color: .black.opacity(0.6), radius: 30)
                    .onHover { inside in inside ? peekTask?.cancel() : closePeek(after: 0.5) }
                    .transition(.move(edge: .leading))
            } else {
                Color.clear.frame(width: 8).frame(maxHeight: .infinity).contentShape(.rect)
                    .onHover { if $0 { openPeek() } }
            }
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
            Toggle("Compact list", isOn: $compact)
            if let p = store.selectedPlaylist {
                Button("Remove “\(p.name)”", role: .destructive) { store.remove(p) }
            }
        } label: {
            PlaylistLabel(name: store.selectedPlaylist?.name ?? "No playlist", size: 9.5)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
        // Before the first fetch starts the list is empty too: show "Tuning in", not "Nothing here yet".
        if store.isLoading || (!store.hasLoaded && store.error == nil && !store.playlists.isEmpty) {
            RailMessage(title: "Tuning in", detail: nil, busy: true)
                .transition(.identity)   // gone at once when the rows arrive, never fading over them
        } else if let e = store.error {
            RailMessage(title: "No signal", detail: e) { Task { await store.reload() } }
        } else if store.playlists.isEmpty {
            RailMessage(title: "Nothing to tune", detail: "Add an M3U playlist or an Xtream Codes account.")
        } else if list.isEmpty {
            RailMessage(title: search.isEmpty ? "Nothing here yet" : "No match", detail: search.isEmpty ? nil : "Nothing called “\(search)”.")
        } else {
            ScrollViewReader { proxy in   // (no fade of its own: on first load the rows do the arriving)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                            ChannelRow(number: i + 1, channel: c,
                                       now: store.library == .live ? store.nowPlaying(c, at: clock) : nil,
                                       next: store.library == .live ? store.upNext(c, at: clock) : nil,
                                       onAir: c.id == selection,
                                       favourite: store.favorites.contains(c.id), clock: clock, motion: motion,
                                       compact: compact)
                                // Proposal 05: every visible row rises 8 pt in 300 ms, 30 ms apart.
                                .rise(Double(i) * 0.03, distance: 8, active: firstLoad && i < 24,
                                      animation: .timingCurve(0.23, 1, 0.32, 1, duration: 0.3))
                                .id(c.id)
                                .contentShape(.rect)
                                .onTapGesture {
                                    select(c.id, keyed: false)
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
                .onAppear {   // back from Watch mode, or the peek: open on the channel that's on
                    if let selection { proxy.scrollTo(selection, anchor: .center) }
                }
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    if keyed || reduce {
                        proxy.scrollTo(id, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    keyed = false
                }
            }
            .transition(.identity)
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
                KeyHint(keys: "⏎", label: "Watch")
            }
        }
        .animation(Motion.if(reduce, Motion.snap), value: visible.count)
        .padding(.horizontal, 22).frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    // MARK: Stage

    /// Picture on the TV (a screen connected as a separate display), or back on this Mac.
    private func toggleTV() {
        if tv.showing != nil { tv.hide(animated: !reduce); return }
        tv.show(TVScreenView(playback: playback, tv: tv,
                             number: { c in visible.firstIndex { $0.id == c.id }.map { $0 + 1 } },
                             programme: { c in store.nowPlaying(c) }))
    }

    private func number(of c: Channel) -> Int? { visible.firstIndex { $0.id == c.id }.map { $0 + 1 } }

    @ViewBuilder private var stage: some View {
        if let c = playback.current {
            GeometryReader { g in
                let now = store.nowPlaying(c, at: clock)
                // The bar never shrinks the picture: docked only if a full-width 16:9 picture still fits above it.
                let docked = !watching && g.size.height - (now == nil ? 64 : 124) >= g.size.width * 9 / 16
                VStack(spacing: 0) {
                    screen(c)
                    if docked { nowBar(c, now: now, floating: false).transition(.move(edge: .bottom)) }
                }
                // Overlays on the picture stay in the view tree and fade by opacity: SwiftUI draws a view that is
                // being removed underneath AppKit's player view, so a removal fade would never be seen.
                .overlay(alignment: .bottom) {
                    if !docked, !watching {
                        nowBar(c, now: now, floating: true)
                            .opacity(chrome ? 1 : 0).allowsHitTesting(chrome)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if watching, tv.showing == nil {
                        ChannelCard(channel: c, number: number(of: c), typed: typed.isEmpty ? nil : typed,
                                    now: now, clock: clock, scale: 0.55)
                            .padding(36).allowsHitTesting(false)
                            .opacity(chrome || !typed.isEmpty ? 1 : 0)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !typed.isEmpty, !watching { NumberEntry(typed: typed).padding(28).allowsHitTesting(false) }
                }
            }
            .onContinuousHover { phase in
                if case .active = phase { wake(instant: false) }
            }
            .transition(.opacity)
        } else {
            Manifesto(action: store.playlists.isEmpty ? ("Add a playlist", { showAdd = true }) : nil)
        }
    }

    private func nowBar(_ c: Channel, now: Programme?, floating: Bool) -> some View {
        NowBar(channel: c, now: now, next: store.upNext(c, at: clock), clock: clock,
               favourite: store.favorites.contains(c.id),
               accessory: AnyView(TVButton(tv: TVControl(available: tv.available, on: tv.showing != nil, name: tv.name, toggle: toggleTV))),
               floating: floating) { store.toggleFavorite(c) }
    }

    private func screen(_ c: Channel) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            // The picture stays in the view tree: SwiftUI can't animate AppKit's player view while removing it.
            // On SHOW ON TV it shrinks and slides toward the TV; BACK TO MAC plays it in reverse.
            let onTV = tv.showing != nil
            PlayerView(player: playback.player, controls: !onTV && (!watching || controlsAwake),
                       onPictureInPicture: { on in withAnimation(Motion.if(reduce, Motion.fade)) { pip = on } })
                .opacity(playback.isTuning || onTV ? 0 : 1)
                .scaleEffect(onTV && !reduce ? 0.92 : 1)
                .offset(x: onTV && !reduce ? 24 : 0)
                .animation(reduce ? Motion.fade : Motion.fade.delay(0.12), value: playback.isTuning)
                .animation(reduce ? Motion.fade : (onTV ? .easeIn(duration: 0.3) : .easeOut(duration: 0.3)), value: onTV)
            if onTV {
                OnTVScreenView(channel: c, screenName: tv.name) { tv.hide(animated: !reduce) }
                    .transition(.opacity)
            }
            if pip, tv.showing == nil {
                InPictureInPictureView(channel: c)
                    .transition(.opacity)
            }
            if tv.showing == nil {
                TuningOverlay(channel: c, tuning: playback.isTuning)
            }
            if playback.soundOnly, !playback.isTuning, tv.showing == nil {
                SoundOnlyCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            // Final states are cards, on the Mac stage even while the picture is on the TV.
            if playback.offAir {
                OffAirView(channel: c).transition(.opacity)
            } else if playback.cantPlay {
                CantPlayView(channel: c).transition(.opacity)
            } else if let f = playback.failed {
                StageNotice(text: f, until: playback.holdUntil, size: 12)
                .padding(20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.if(reduce, Motion.fade), value: playback.isTuning)
        .animation(Motion.if(reduce, Motion.enter), value: playback.failed)
        .animation(Motion.if(reduce, Motion.enter), value: playback.soundOnly)
        .animation(Motion.if(reduce, Motion.fade), value: playback.offAir)
        .animation(Motion.if(reduce, Motion.fade), value: playback.cantPlay)
    }
}

// MARK: Pieces

/// Digits typed to change channel, top right, like a TV remote's entry.
struct NumberEntry: View {
    let typed: String
    var body: some View {
        Text(typed.padding(toLength: 3, withPad: "–", startingAt: 0))
            .font(.system(size: 34, weight: .heavy, design: .monospaced))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Brand.paper, in: .rect(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}

/// Hands over the NSWindow the view lives in, for full-screen and key handling.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { found(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
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

/// What the now bar needs to know about the TV screen.
struct TVControl {
    let available: Bool
    let on: Bool
    let name: String
    let toggle: () -> Void
}

/// "ON TV" when a second screen is connected; otherwise a TV icon that explains how to connect one.
struct TVButton: View {
    let tv: TVControl
    @State private var help = false
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        if tv.available || tv.on {
            Button(action: tv.toggle) {
                HStack(spacing: 7) {
                    Image(systemName: tv.on ? "laptopcomputer" : "tv").font(.system(size: 11, weight: .bold))
                    Text(tv.on ? "BACK TO MAC" : "SHOW ON TV").font(Brand.display(9)).tracking(1.2)
                }
                .foregroundStyle(tv.on ? Brand.paper : Brand.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(tv.on ? Brand.line : Brand.paper, in: .capsule)
                .scaleEffect(hover ? 1.04 : 1)
            }
            .buttonStyle(PressStyle())
            .onHover { h in withAnimation(reduce ? nil : Motion.snap) { hover = h } }
            .help(tv.on ? "Bring the picture back to this Mac" : "Show the picture full screen on \(tv.name)")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            IconButton(symbol: "tv", help: "Watch on your TV") { help.toggle() }
                .popover(isPresented: $help, arrowEdge: .top) { TVHowTo() }
        }
    }
}

/// How to connect the TV as a screen, once.
struct TVHowTo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WATCH ON YOUR TV").font(Brand.display(14)).foregroundStyle(Brand.paper)
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open Control Center and choose Screen Mirroring.")
                step(2, "Pick your TV, then “Use As Separate Display”.")
                step(3, "Come back here and press SHOW ON TV.")
            }
            Text("Your Mac keeps playing, so changing channel is instant.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.dim)
        }
        .padding(18).frame(width: 300)
        .background(Brand.ink)
    }
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(Brand.mono(11, .bold)).foregroundStyle(Brand.ink)
                .frame(width: 18, height: 18).background(Brand.paper, in: .circle)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.paper)
        }
    }
}
