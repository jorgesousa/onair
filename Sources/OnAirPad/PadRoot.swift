import SwiftUI

/// The iPad screen. One stage and one rail stay in the tree in every layout and only move,
/// so rotating or opening the list never rebuilds the picture (PadLayout decides where).
struct PadRoot: View {
    @Environment(Store.self) private var store
    @Environment(PlaybackController.self) private var playback
    @Environment(PadSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var motion

    @State private var filter: SidebarItem = .all
    @State private var search = ""
    @AppStorage("compactList") private var compact = false
    @State private var selection: Channel.ID?
    @State private var lastChannel: Channel.ID?
    @State private var clock = Date.now
    @State private var firstLoad = false
    @State private var armFirstLoad = false
    @State private var expanded = false         // portrait: picture full screen anyway
    @State private var peek = false             // watch: the list over the picture
    @State private var peekDrag: CGFloat = 0    // finger travel while opening/closing the peek
    @State private var barHeight: CGFloat = 0
    @State private var showAdd = false
    @State private var showAbout = false
    // Watching: controls + channel card for 3 s after a touch or a zap.
    @State private var chrome = false
    @State private var controlsShown = false   // the bar comes with a tap only, not with a zap
    @State private var chromeTask: Task<Void, Never>?
    @State private var pending: Channel.ID?     // swiped to, tuned once the swiping settles
    @State private var pendingTask: Task<Void, Never>?
    @State private var typed = ""
    @State private var typedTask: Task<Void, Never>?
    @State private var dragY: CGFloat = 0
    @State private var fill = false

    static let railWidth: CGFloat = 361

    private var visible: [Channel] { store.items(for: filter, search: search) }

    var body: some View {
        GeometryReader { g in
            let inset = g.safeAreaInsets
            let full = CGSize(width: g.size.width + inset.leading + inset.trailing,
                              height: g.size.height + inset.top + inset.bottom)
            let mode = PadLayout.mode(size: full, playing: playback.current != nil, expanded: expanded)
            content(full: full, inset: inset, mode: mode)
                .frame(width: full.width, height: full.height)
                .position(x: full.width / 2 - inset.leading, y: full.height / 2 - inset.top)
                .defersSystemGestures(on: mode == .watch ? .vertical : [])
                .background { keyboardShortcuts }
                .statusBarHidden(mode == .watch)
                .persistentSystemOverlays(mode == .watch ? .hidden : .automatic)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root")
                .accessibilityValue(String(describing: mode))
                .animation(Motion.if(reduce, .easeOut(duration: 0.22)), value: mode)
        }
        .background(Brand.ink.ignoresSafeArea())
        .sheet(isPresented: $showAdd) { AddPlaylistView() }
        .sheet(isPresented: $showAbout) { PadAbout() }
        .task { await store.loadIfNeeded() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                clock = .now
                await store.loadGuide()
            }
        }
        .onChange(of: store.selectedPlaylistID) { _, _ in
            armFirstLoad = true
            store.reset(); filter = .all; selection = nil
            Task { await store.loadIfNeeded() }
        }
        .onChange(of: store.isLoading) { _, loading in
            if loading {
                if armFirstLoad { firstLoad = true; armFirstLoad = false }
                return
            }
            Task { @MainActor in try? await Task.sleep(for: .seconds(1.2)); firstLoad = false }
        }
        .onChange(of: scenePhase, initial: true) { _, p in session.update(phase: p) }
        .onChange(of: playback.current) { _, c in
            session.refreshIdleTimer()
            if c == nil { expanded = false }
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(full: CGSize, inset: EdgeInsets, mode: PadLayoutMode) -> some View {
        let wide = full.width > full.height
        let stage = stageFrame(full: full, inset: inset, mode: mode, wide: wide)
        let rail = railFrame(full: full, inset: inset, mode: mode, wide: wide, stage: stage)
        ZStack(alignment: .topLeading) {
            // 1. The picture (or, with nothing on, the manifesto / the resume card).
            stageLayer(mode: mode, shown: stage.height > 0, inset: inset)
                .frame(width: stage.width, height: stage.height)
                .offset(x: stage.minX, y: stage.minY)

            // 2. Stacked: what's on, docked under the picture.
            if mode == .stacked, let c = playback.current {
                NowBar(channel: c, now: store.nowPlaying(c, at: clock), next: store.upNext(c, at: clock),
                       clock: clock, favourite: store.favorites.contains(c.id), floating: false) {
                    store.toggleFavorite(c)
                }
                .frame(width: full.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                .offset(x: 0, y: stage.maxY)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 3. Watch: dim behind the open list; a tap there closes it.
            if mode == .watch {
                Color.black.opacity(peekProgress * 0.45)
                    .allowsHitTesting(peek)
                    .onTapGesture { setPeek(false) }
                    .frame(width: full.width, height: full.height)
            }

            // 4. The list.
            PadRail(filter: $filter, search: $search, compact: $compact, selection: selection,
                    firstLoad: firstLoad, clock: clock, motion: motion,
                    onPick: pick, onAdd: { showAdd = true }, onAbout: { showAbout = true })
                .padding(.top, rail.minY == 0 ? inset.top : 0)
                .padding(.bottom, inset.bottom)
                .padding(.leading, rail.minX <= 0 && mode != .stacked ? inset.leading : 0)
                .frame(width: rail.width, height: rail.height)
                .overlay(alignment: .trailing) {
                    if mode != .stacked, rail.width < full.width { Rectangle().fill(Brand.line).frame(width: 1) }
                }
                .shadow(color: .black.opacity(mode == .watch ? 0.6 * peekProgress : 0), radius: 30)
                .offset(x: rail.minX, y: rail.minY)
                .gesture(mode == .watch ? closePeekDrag : nil)

            // 5. Watch: the left edge pulls the list in.
            if mode == .watch, !peek {
                Color.clear.frame(width: 24, height: full.height).contentShape(.rect)
                    .gesture(openPeekDrag)
                    .accessibilityIdentifier("edge")
            }
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
        .clipped()
    }

    private func stageFrame(full: CGSize, inset: EdgeInsets, mode: PadLayoutMode, wide: Bool) -> CGRect {
        switch mode {
        case .watch:
            return CGRect(origin: .zero, size: full)
        case .stacked:
            return CGRect(x: 0, y: inset.top, width: full.width, height: full.width * 9 / 16)
        case .rail:
            if wide {
                return CGRect(x: Self.railWidth + inset.leading, y: 0,
                              width: full.width - Self.railWidth - inset.leading, height: full.height)
            }
            // Portrait with nothing on: the list fills the screen, unless there's a channel to resume.
            let h = playback.lastStopped == nil ? 0 : full.width * 9 / 16
            return CGRect(x: 0, y: inset.top, width: full.width, height: h)
        }
    }

    private func railFrame(full: CGSize, inset: EdgeInsets, mode: PadLayoutMode, wide: Bool, stage: CGRect) -> CGRect {
        let w = Self.railWidth + inset.leading
        switch mode {
        case .watch:
            let x = (peek ? 0 : -w) + peekDrag
            return CGRect(x: min(0, max(-w, x)), y: 0, width: w, height: full.height)
        case .stacked:
            let top = stage.maxY + barHeight
            return CGRect(x: 0, y: top, width: full.width, height: max(0, full.height - top))
        case .rail:
            if wide { return CGRect(x: 0, y: 0, width: w, height: full.height) }
            let top = stage.height > 0 ? stage.maxY : 0
            return CGRect(x: 0, y: top, width: full.width, height: full.height - top)
        }
    }

    /// `shown` false: the stage is folded away (portrait list). Nothing animating may stay behind it.
    @ViewBuilder private func stageLayer(mode: PadLayoutMode, shown: Bool, inset: EdgeInsets) -> some View {
        let watching = playback.current != nil && mode != .rail
        ZStack {
            PadStage(fill: fill)
                .offset(y: watching ? Swipe.rubberBand(dragY) : 0)
            if playback.current == nil {
                if let last = playback.lastStopped {
                    ResumeCard(channel: last) { pick(last) }.background(Brand.ink)
                } else if shown {
                    Manifesto(action: store.playlists.isEmpty ? ("Add a playlist", { showAdd = true }) : nil)
                        .background(Brand.ink)
                }
            }
            if watching {
                PictureGestures(
                    onTap: { controlsShown && chrome ? hideChrome() : wake(controls: true) },
                    onTwoFingerTap: backToLast,
                    onDrag: { dragY = $0 },
                    onRelease: { travel, velocity in
                        let step = Swipe.step(travel: travel, velocity: velocity)
                        withAnimation(Motion.if(reduce, .spring(duration: 0.35, bounce: 0))) { dragY = 0 }
                        if step != 0 { zap(step) }
                    },
                    onPinch: { out in withAnimation(Motion.if(reduce, Motion.snap)) { fill = out } })
                .accessibilityIdentifier("picture")
                channelCard(mode: mode, inset: inset)
                PadControls(mode: mode, expanded: expanded, lastName: lastChannelName,
                            onList: { setPeek(true) }, onLast: backToLast, onExpand: toggleExpanded)
                    .padding(.horizontal, 20)
                    .padding(.top, (mode == .watch ? inset.top : 0) + 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(chrome && controlsShown ? 1 : 0)
                    .allowsHitTesting(chrome && controlsShown)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stage")
        .accessibilityValue(stageState)
    }

    /// Bottom-left, never top-left: the broadcaster's score and clock live up there.
    @ViewBuilder private func channelCard(mode: PadLayoutMode, inset: EdgeInsets) -> some View {
        let id = pending ?? playback.current?.id
        if let c = store.items.first(where: { $0.id == id }) ?? playback.current {
            ChannelCard(channel: c, number: number(of: c), typed: typed.isEmpty ? nil : typed,
                        now: store.nowPlaying(c, at: clock), clock: clock, scale: mode == .watch ? 0.55 : 0.4)
                .padding(.leading, (mode == .watch ? 36 : 20) + inset.leading)
                .padding(.bottom, (mode == .watch ? 36 : 20) + (mode == .watch ? inset.bottom : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
                .opacity(chrome || pending != nil || !typed.isEmpty ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("card")
                .accessibilityValue(number(of: c).map { String(format: "%03d", $0) } ?? "")
        }
    }

    private var stageState: String {
        if playback.current == nil { return playback.lastStopped == nil ? "idle" : "resume" }
        if let f = playback.failed { return "failed: \(f)" }
        return playback.isTuning ? "tuning" : "playing"
    }

    // MARK: Picking and the peek

    private func pick(_ c: Channel) {
        if let s = selection, s != c.id { lastChannel = s }
        selection = c.id
        session.play(c)
        store.markPlayed(c)
        if peek { setPeek(false) }
        if chrome == false { wake(controls: false) }
    }

    private func number(of c: Channel) -> Int? { visible.firstIndex { $0.id == c.id }.map { $0 + 1 } }

    private var lastChannelName: String? {
        guard let l = lastChannel, l != selection else { return nil }
        return store.items.first { $0.id == l }?.displayName
    }

    private func backToLast() {
        guard let l = lastChannel, let c = store.items.first(where: { $0.id == l }) else { return }
        pendingTask?.cancel(); pending = nil
        pick(c)
        wake(controls: false)
    }

    private func toggleExpanded() {
        withAnimation(Motion.if(reduce, .easeOut(duration: 0.22))) { expanded.toggle() }
    }

    /// A swipe: the card shows where you're going at once; the stream starts when the swiping
    /// stops (0.6 s), so flicking past five channels opens one connection, not five.
    private func zap(_ delta: Int) {
        guard let id = Zap.step(from: pending ?? selection, in: visible.map(\.id), by: delta) else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { pending = id }
        wake(controls: false)
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, let c = store.items.first(where: { $0.id == id }) else { return }
            pick(c)
            pending = nil
        }
    }

    /// Keys behave as on the Mac: they jump at once, because they repeat.
    private func step(_ delta: Int) {
        guard let id = Zap.step(from: selection, in: visible.map(\.id), by: delta),
              let c = store.items.first(where: { $0.id == id }) else { return }
        pick(c); wake(controls: false)
    }

    private func type(_ digit: Int) {
        typedTask?.cancel()
        typed += String(digit)
        wake(controls: false)
        if Zap.shouldCommit(typed: typed, count: visible.count) { commitTyped(); return }
        typedTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            commitTyped()
        }
    }

    private func commitTyped() {
        if let id = Zap.channel(forTyped: typed, in: visible.map(\.id)), let c = store.items.first(where: { $0.id == id }) {
            pick(c)
        }
        typed = ""
    }

    /// A hardware keyboard gets the Mac's keys. Shortcuts rather than key presses: they work
    /// wherever focus is, and a focused search field still gets its own typing first.
    @ViewBuilder private var keyboardShortcuts: some View {
        Group {
            Button("Next channel") { step(1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("Previous channel") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Last channel") { backToLast() }.keyboardShortcut(.delete, modifiers: [])
            Button("Last channel ") { backToLast() }.keyboardShortcut(.deleteForward, modifiers: [])
            Button("Close") {
                if peek { setPeek(false) } else if expanded { toggleExpanded() }
            }.keyboardShortcut(.escape, modifiers: [])
            Button("Full screen") { if playback.current != nil { toggleExpanded() } }
                .keyboardShortcut(.return, modifiers: [])
            ForEach(0..<10, id: \.self) { d in
                Button("Channel digit \(d)") { type(d) }.keyboardShortcut(KeyEquivalent(Character("\(d)")), modifiers: [])
            }
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// Shows the card (and, after a tap, the controls), then hides them after 3 s.
    private func wake(controls: Bool) {
        chromeTask?.cancel()
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            chrome = true
            if controls { controlsShown = true }
        }
        chromeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            hideChrome()
        }
    }

    private func hideChrome() {
        chromeTask?.cancel()
        withAnimation(Motion.if(reduce, .easeOut(duration: controlsShown ? 0.26 : 0.2))) { chrome = false }
        controlsShown = false
    }

    private var peekProgress: Double {
        let w = Self.railWidth
        let x = (peek ? 0 : -w) + peekDrag
        return Double(min(1, max(0, 1 + x / w)))
    }

    private func setPeek(_ open: Bool) {
        withAnimation(Motion.if(reduce, .spring(duration: 0.3, bounce: 0))) { peek = open; peekDrag = 0 }
    }

    /// From the left edge: the list follows the finger, and settles by where the flick was heading.
    private var openPeekDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in peekDrag = max(0, v.translation.width) }
            .onEnded { v in setPeek(v.predictedEndTranslation.width > Self.railWidth / 2) }
    }

    private var closePeekDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { v in if peek { peekDrag = min(0, v.translation.width) } }
            .onEnded { v in if peek { setPeek(v.predictedEndTranslation.width > -Self.railWidth / 2) } }
    }
}
