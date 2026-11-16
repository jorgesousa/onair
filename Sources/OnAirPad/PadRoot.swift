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
    @State private var searching = false
    // Watching: controls + channel card for 3 s after a touch or a zap.
    @State private var chrome = false
    @State private var controlsShown = false   // the bar comes with a tap only, not with a zap
    @State private var chromeTask: Task<Void, Never>?
    @State private var pending: Channel.ID?     // swiped to, tuned once the swiping settles
    @State private var pendingTask: Task<Void, Never>?
    @State private var holdTuning = false        // see `pickFromSide`
    @State private var holdRail = false          // landscape, nothing on: the list stays a beat after the touch
    @State private var sideTask: Task<Void, Never>?
    @State private var typed = ""
    @State private var typedTask: Task<Void, Never>?
    @State private var dragY: CGFloat = 0
    @State private var fill = false
    // Rotation (or the list moving under/beside the picture): only the picture travels; the list
    // and the now bar wait unseen at their new place, then settle in.
    @State private var settledKey = ""
    @State private var surfaces: Double = 1      // the now bar
    @State private var listSurface: Double = 1   // the list, a beat after the bar
    @State private var settleTask: Task<Void, Never>?

    static let railWidth: CGFloat = 361

    private var visible: [Channel] { store.items(for: filter, search: search) }

    var body: some View {
        GeometryReader { g in
            let inset = g.safeAreaInsets
            let full = CGSize(width: g.size.width + inset.leading + inset.trailing,
                              height: g.size.height + inset.top + inset.bottom)
            let mode = PadLayout.mode(size: full, playing: playback.current != nil && !holdRail, expanded: expanded)
            content(full: full, inset: inset, mode: mode)
                .frame(width: full.width, height: full.height)
                .position(x: full.width / 2 - inset.leading, y: full.height / 2 - inset.top)
                .defersSystemGestures(on: mode == .watch ? .vertical : mode == .stacked ? .top : [])
                .background { keyboardShortcuts }
                .statusBarHidden(mode == .watch)
                .persistentSystemOverlays(mode == .watch ? .hidden : .automatic)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root")
                .accessibilityValue(String(describing: mode))
        }
        .background(Brand.ink.ignoresSafeArea())
        .sheet(isPresented: $showAdd) { AddPlaylistView() }
        .sheet(isPresented: $showAbout) { PadAbout() }
        // Home (Dispatcharr): one TV, several screens.
        .followsHome(playback: playback) { pick($0) }
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
        let key = "\(mode)|\(wide)"
        let settling = !settledKey.isEmpty && key != settledKey && Self.settles(from: settledKey, to: key)
        let shown = settling ? 0 : surfaces
        let listShown = settling ? 0 : listSurface
        ZStack(alignment: .topLeading) {
            // 1. The picture (or, with nothing on, the manifesto / the resume card).
            stageLayer(mode: mode, shown: stage.height > 0, inset: inset)
                .frame(width: stage.width, height: stage.height)
                .animation(Motion.if(reduce, Self.leave), value: key)
                .offset(x: stage.minX, y: stage.minY)

            // 2. Stacked: what's on, docked under the picture.
            if mode == .stacked, let c = playback.current {
                NowBar(channel: c, now: store.nowPlaying(c, at: clock), next: store.upNext(c, at: clock),
                       clock: clock, favourite: store.favorites.contains(c.id), floating: false, compact: true,
                       narrow: full.width < 500) {
                    store.toggleFavorite(c)
                }
                .frame(width: full.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                .offset(x: 0, y: stage.maxY)
                .opacity(shown)
                .scaleEffect(reduce ? 1 : 0.98 + 0.02 * shown, anchor: .top)
                .offset(y: reduce ? 0 : (1 - shown) * 24)
                .transition(.identity)
                .transaction(value: key) { t in if settling { t.animation = nil } }
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
                    onPick: { pick($0, fromList: true) }, onAdd: { showAdd = true }, onAbout: { showAbout = true },
                    onSearchFocus: { searching = $0 }, condensed: mode == .stacked)
                .padding(.top, rail.minY == 0 ? inset.top : 0)
                .padding(.bottom, inset.bottom)
                .padding(.leading, rail.minX <= 0 && mode != .stacked ? inset.leading : 0)
                .frame(width: rail.width, height: rail.height)
                .overlay(alignment: .trailing) {
                    if mode != .stacked, rail.width < full.width { Rectangle().fill(Brand.line).frame(width: 1) }
                }
                .shadow(color: .black.opacity(mode == .watch ? 0.6 * peekProgress : 0), radius: 30)
                .offset(x: rail.minX, y: rail.minY)
                .opacity(mode == .watch ? 1 : listShown)
                .scaleEffect(reduce || mode == .watch ? 1 : 0.98 + 0.02 * listShown, anchor: .top)
                .offset(y: reduce || mode == .watch ? 0 : (1 - listShown) * 24)
                .transaction(value: key) { t in if settling { t.animation = nil } else if t.animation == nil, !reduce { t.animation = .easeOut(duration: 0.22) } }
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
        .onChange(of: key, initial: true) { old, new in settle(from: old, to: new) }
    }

    /// Rotating, or the list moving between beside/under the picture, re-lays the list out
    /// completely: animating that reads as lumpy. Those surfaces hide, jump, then settle in.
    private static func settles(from old: String, to new: String) -> Bool {
        old.hasSuffix("true") != new.hasSuffix("true") || old.hasPrefix("stacked") || new.hasPrefix("stacked")
    }

    private func settle(from old: String, to new: String) {
        guard !settledKey.isEmpty, old != new, Self.settles(from: old, to: new) else { settledKey = new; return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { surfaces = 0; listSurface = 0; settledKey = new }
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduce ? 0.05 : 0.35))   // after the system has finished turning
            guard !Task.isCancelled else { return }
            // A critically damped spring settles without the snap of a sharp ease-out.
            let settleIn: Animation = reduce ? Motion.fade : .spring(duration: 0.55, bounce: 0)
            withAnimation(settleIn) { surfaces = 1 }
            try? await Task.sleep(for: .seconds(reduce ? 0 : 0.08))
            guard !Task.isCancelled else { return }
            withAnimation(settleIn) { listSurface = 1 }
        }
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
            PadStage(fill: fill, holdTuning: holdTuning)
                .offset(y: watching ? Swipe.rubberBand(dragY) : 0)
                // Swiped away from: the picture steps back until the new channel starts tuning.
                .opacity(pending != nil ? 0.4 : 1)
                .animation(.easeOut(duration: 0.2), value: pending != nil)
            // Held on through a side-list pick, so the stage never flashes black before it opens up.
            if playback.current == nil || holdRail {
                if let last = playback.lastStopped {
                    ResumeCard(channel: last) { pick(last) }.background(Brand.ink).transition(.opacity)
                } else if shown {
                    Manifesto(action: store.playlists.isEmpty ? ("Add a playlist", { showAdd = true }) : nil)
                        .background(Brand.ink).transition(.opacity)
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
                // On iPad the controls leave the tree when hidden (no AppKit view to fade under),
                // so nothing invisible can be tapped.
                if chrome && controlsShown {
                    PadControls(mode: mode, expanded: expanded || (Platform.phone && mode == .watch), lastName: lastChannelName,
                                onList: { setPeek(true) }, onLast: backToLast, onExpand: { toggleExpanded(wide: mode == .watch) })
                        // Full screen: clear of the Dynamic Island and the phone's rounded corners.
                        .padding(.leading, 20 + (mode == .watch ? inset.leading : 0))
                        .padding(.trailing, 20 + (mode == .watch ? inset.trailing : 0))
                        .padding(.top, (mode == .watch ? inset.top : 0) + 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -6)))
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stage")
        .accessibilityValue(stageState)
    }

    /// Bottom-left, never top-left: the broadcaster's score and clock live up there.
    @ViewBuilder private func channelCard(mode: PadLayoutMode, inset: EdgeInsets) -> some View {
        let id = pending ?? playback.current?.id
        if let c = store.items.first(where: { $0.id == id }) ?? playback.current {
            ChannelCard(channel: c, number: number(of: c), typed: typed.isEmpty ? nil : typed,
                        now: store.nowPlaying(c, at: clock), clock: clock, scale: cardScale(mode))
                .padding(.leading, cardMargin(mode) + inset.leading)
                .padding(.bottom, cardMargin(mode) + (mode == .watch ? inset.bottom : 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
                .opacity(chrome || pending != nil || !typed.isEmpty ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("card")
                .accessibilityValue(number(of: c).map { String(format: "%03d", $0) } ?? "")
        }
    }

    /// The card is sized for an iPad; on a phone it would cover the play.
    private func cardScale(_ mode: PadLayoutMode) -> CGFloat {
        Platform.phone ? (mode == .watch ? 0.42 : 0.32) : (mode == .watch ? 0.55 : 0.4)
    }
    private func cardMargin(_ mode: PadLayoutMode) -> CGFloat {
        Platform.phone ? (mode == .watch ? 20 : 12) : (mode == .watch ? 36 : 20)
    }

    private var stageState: String {
        if playback.current == nil { return playback.lastStopped == nil ? "idle" : "resume" }
        if let f = playback.failed { return "failed: \(f)" }
        return playback.isTuning ? "tuning" : "playing"
    }

    // MARK: Picking and the peek

    private func pick(_ c: Channel, fromList: Bool = false) {
        // Already on: re-tuning would reopen the provider's only connection for nothing.
        if c.id == playback.current?.id {
            selection = c.id
            if peek { setPeek(false) }
            return
        }
        if let s = selection, s != c.id { lastChannel = s }
        sideTask?.cancel(); holdTuning = false; holdRail = false
        // Landscape only (iPad and iPhone): the list that slid in from the edge, or the side list
        // with nothing on. Portrait keeps the sliding highlight below.
        if fromList, !reduce, peek || (playback.current == nil && settledKey.hasSuffix("true")) {
            pickFromSide(c)
            return
        }
        // A tap slides the on-air highlight to the row (as with the Mac's mouse); swipes and keys jump.
        if fromList { withAnimation(Motion.if(reduce, Motion.snap)) { selection = c.id } } else { selection = c.id }
        session.play(c)
        store.markPlayed(c)
        if peek { setPeek(false) }
        if chrome == false { wake(controls: false) }
    }

    /// One thing moves at a time: the row lights at once (the list is about to leave, so no
    /// slide); a beat later the list leaves as the picture opens up with the "tuning in" card
    /// fading in; the channel card only once the list has gone. The stream starts on the touch.
    private func pickFromSide(_ c: Channel) {
        selection = c.id
        holdTuning = true
        if playback.current == nil { holdRail = true }
        session.play(c)
        store.markPlayed(c)
        sideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.12))
            guard !Task.isCancelled else { return }
            // The list leaves as the picture opens up already tuning: never an empty, black stage.
            withAnimation(Self.leave) { holdRail = false; peek = false; peekDrag = 0 }
            holdTuning = false
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            if chrome == false { wake(controls: false) }
        }
    }

    /// The list leaving and the picture opening up: one critically damped movement.
    static let leave = Animation.spring(duration: 0.35, bounce: 0)

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

    /// iPhone: turn the screen (portrait ↔ landscape Watch). iPad: the picture fills the window.
    private func toggleExpanded(wide: Bool) {
        if let way = FullScreenTurn.target(phone: Platform.phone, wide: wide) {
            expanded = false
            PhoneTurn.turn(to: way)
            return
        }
        withAnimation(Motion.if(reduce, .easeOut(duration: 0.22))) { expanded.toggle() }
    }

    /// A swipe: the card shows where you're going at once; the stream starts when the swiping
    /// stops (0.6 s), so flicking past five channels opens one connection, not five.
    private func zap(_ delta: Int) {
        guard let id = Zap.move(from: pending ?? selection, in: visible.map(\.id), by: delta) else { return }
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
        guard let id = Zap.move(from: selection, in: visible.map(\.id), by: delta),
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
                if peek { setPeek(false) } else if expanded { toggleExpanded(wide: true) }
            }.keyboardShortcut(.escape, modifiers: [])
            Button("Full screen") { if playback.current != nil { toggleExpanded(wide: false) } }
                .keyboardShortcut(.return, modifiers: [])
            ForEach(0..<10, id: \.self) { d in
                Button("Channel digit \(d)") { type(d) }.keyboardShortcut(KeyEquivalent(Character("\(d)")), modifiers: [])
            }
        }
        .disabled(searching || showAdd || showAbout)
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// Shows the card (and, after a tap, the controls), then hides them after 3 s.
    private func wake(controls: Bool) {
        chromeTask?.cancel()
        if controls {
            // A tap: the bar comes in the way it leaves (fade + 6 pt from above).
            withAnimation(Motion.if(reduce, .easeOut(duration: 0.15))) { chrome = true; controlsShown = true }
        } else {
            // A zap: the card is there at once (it's feedback, not decoration).
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { chrome = true }
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
