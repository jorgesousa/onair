# ONAIR for iPad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An iPad app of ONAIR for watching live TV (mostly football) on the counter, sharing one Swift core with the unchanged Mac app.

**Architecture:** Code both apps need moves to `Sources/OnAirCore`. The Mac executable target compiles `OnAir/` + `OnAirCore/` as one module (SwiftPM, as today). A new Xcode project `iPad/OnAir.xcodeproj` compiles `OnAirCore/` + `OnAirPad/` as one module. Pure decisions (zap stepping, typed numbers, layout mode, connection lifecycle) live in core as plain functions with Swift Testing tests run on the Mac by `swift test`.

**Tech Stack:** Swift 5 language mode, SwiftUI, Observation, AVFoundation/AVKit (AVPlayerLayer, AVPictureInPictureController, AVRoutePickerView), Swift Testing, Xcode 27.2, iPadOS 17+.

**Spec:** `docs/superpowers/specs/2026-11-14-ipad-design.md`

## Global Constraints

- iPadOS 17.0 minimum; iPad only (`TARGETED_DEVICE_FAMILY = 2`); all four orientations.
- Swift 5 language mode, no default main-actor isolation on the iPad target (match the package).
- Bundle id `com.sousalab.onair`; team `L4ZLV2Y44P`, automatic signing.
- English UI. Test Card brand: `Brand` colours, Archivo Black (`Support/Fonts/ArchivoBlack.ttf`), `Motion` tokens.
- The Mac app's behaviour, `scripts/build-app.sh`, `release.sh`, `smoke-test.sh` and the Homebrew build stay working; no Mac screen changes beyond the wake hook and the shared `Zap` helpers.
- Never read, print or commit `.test-account`. Before every commit: `git diff --cached | grep -E "USERNAME|PASSWORD|SERVER="` must print nothing beyond `smoke-test.sh`'s variable names.
- No push, release, TestFlight or other public action without Jorge's explicit OK.
- Network: streams are often plain http; the iPad Info.plist keeps `NSAllowsArbitraryLoads = true` like the Mac.
- Simulators: test on iOS 27.2 (iPad Pro 13-inch (M5), iPad Air 11-inch (M4), iPad mini (A17 Pro)) and once on 26.5.

## Review Focus

1. **Swipe during tuning / fast repeated swipes** → each swipe moves one channel, the card ticks the number at once, only the last channel actually starts (no pile-up of stream starts). Test: `Zap.step` tests + Task 8 sim check of five quick swipes.
2. **The slot is held by an iPad nobody is looking at** → backgrounded without PiP releases at once; PiP paused in the background ≥ 10 s releases. Test: `ConnectionPolicy` tests in Task 3.
3. **Empty or one-item list, or search that matches nothing** → swipe does nothing, no crash, card does not appear. Test: `Zap.step` with `[]` and one item in Task 3.
4. **Rotation or window resize while playing** → layout switches between watch and stacked without restarting the stream. Test: `PadLayout.mode` tests in Task 3 + Task 7 sim rotation with stream continuing (no new `start` in logs).
5. **Old M3U-file playlist path no longer readable on iPad** → copied file used; if missing, the rail shows the normal load error, not a hang. Test: Task 9 import test with a file then deleting the original.

---

### Task 1: Branch, baseline and the core folder

**Files:**
- Move (git mv) to `Sources/OnAirCore/`: `Models.swift`, `M3UParser.swift`, `Xtream.swift`, `Guide.swift`, `Keychain.swift`, `FreeLists.swift`, `Store.swift`, `Brand.swift`, `Motion.swift`
- Modify: `Package.swift`, `Sources/OnAirCore/Brand.swift:2` (drop `import AppKit`)
- Create: `Tests/OnAirTests/BaselineTests.swift`

**Interfaces:**
- Produces: module `OnAir` built from `Sources/OnAir` + `Sources/OnAirCore`; test target `OnAirTests` (`@testable import OnAir`).

- [ ] **Step 1:** The Mac work from 2026-11-14 is uncommitted on `main`. Get Jorge's OK to commit it as its own commit (credential grep first), then `git switch -c ipad`.
- [ ] **Step 2:** Baseline: `scripts/build-app.sh` succeeds; note the binary size. Launch `build/OnAir.app`, confirm the channel list loads.
- [ ] **Step 3:** Write `Tests/OnAirTests/BaselineTests.swift` with `@Test func m3uParsesNameGroupAndURL()` feeding `#EXTM3U\n#EXTINF:-1 tvg-id="a" group-title="Sport",Sport TV\nhttp://x/1.ts` to the existing M3U parser and expecting one channel named `Sport TV`, group `Sport`, epgID `a`.
- [ ] **Step 4:** Package.swift: `.executableTarget(name: "OnAir", path: "Sources", sources: ["OnAir", "OnAirCore"])` and `.testTarget(name: "OnAirTests", dependencies: ["OnAir"], path: "Tests/OnAirTests")`. Move the files.
- [ ] **Step 5:** Run `swift build && swift test`. Expected: build OK, 1 test passes.
- [ ] **Step 6:** `scripts/build-app.sh`, launch the app, channel list loads as in Step 2.
- [ ] **Step 7:** Commit `Move shared code to Sources/OnAirCore`.

### Task 2: PlaybackController and shared views into core

**Files:**
- Create: `Sources/OnAirCore/PlaybackController.swift` (the class and its helpers from `PlayerView.swift:45-314`)
- Create: `Sources/OnAirCore/SharedViews.swift` (`ChannelCard`, `InPictureInPictureView` from TVScreen.swift; `SoundOnlyCard`, `RailMessage`, `Hairline`, `NowBar`, `ChannelRow`, `FilterButton`, `IconButton` from ContentView.swift, only those with no AppKit use)
- Modify: `Sources/OnAir/PlayerView.swift` (keeps only the NSViewRepresentable), `Sources/OnAir/ContentView.swift` (wire wake)

**Interfaces:**
- Produces: `PlaybackController.reconnectNow(reason: String)` (internal, was private), `PlaybackController.release()` — stops the player, clears `current`, `isTuning`, `failed`, `soundOnly`, ends the session so the provider slot frees. `var lastStopped: Channel?` set by `release()`.
- The `NSWorkspace.didWakeNotification` observer moves out of the controller into ContentView's `.onAppear` (Mac), calling `playback.reconnectNow(reason: "wake")`.

- [ ] **Step 1:** Test `@Test func releaseClearsState()`: a fresh `PlaybackController`, `release()` with nothing playing → `current == nil`, `isTuning == false`, `lastStopped == nil`; no crash.
- [ ] **Step 2:** `swift test` → fails (no `release`).
- [ ] **Step 3:** Move the code, add `release()`/`lastStopped`, move the wake observer.
- [ ] **Step 4:** `swift test` passes; `grep -n "NSWorkspace\|AppKit\|NSView" Sources/OnAirCore` prints nothing.
- [ ] **Step 5:** Mac check: build-app, play a channel on the fake provider (Task 4 server can run from the scratchpad copy for now), zap, Watch mode, sleep/wake reconnect visible in `log show --predicate 'process == "OnAir"'`.
- [ ] **Step 6:** Commit `Playback and shared views in core`.

### Task 3: Pure decisions with tests

**Files:**
- Create: `Sources/OnAirCore/Decisions.swift`
- Create: `Tests/OnAirTests/DecisionsTests.swift`
- Modify: `Sources/OnAir/ContentView.swift:153-212` (`step`, `type`, `commitTyped` call `Zap`)

**Interfaces (Produces):**
```swift
enum Zap {
    /// Wraps around. nil list → nil. Unknown current → first (delta>0) or last (delta<0).
    static func step(from current: Channel.ID?, in list: [Channel.ID], by delta: Int) -> Channel.ID?
    /// Mac rule: commit at 3 digits or when another digit could not still be valid.
    static func shouldCommit(typed: String, count: Int) -> Bool
    /// 1-based number → id, nil if out of range.
    static func channel(forTyped typed: String, in list: [Channel.ID]) -> Channel.ID?
}
enum PadLayoutMode: Equatable { case rail, watch, stacked }
enum PadLayout {
    static func mode(size: CGSize, playing: Bool, expanded: Bool) -> PadLayoutMode
}
enum ScenePhaseLike { case active, inactive, background }
enum ConnectionPolicy {
    static let pausedGrace: TimeInterval = 10
    static func keep(phase: ScenePhaseLike, pip: Bool, pausedFor: TimeInterval) -> Bool
}
```

- [ ] **Step 1: Tests** (`DecisionsTests.swift`):
  - `step(from: "b", in: ["a","b","c"], by: 1) == "c"`; `by: 1` from `"c"` → `"a"`; `by: -1` from `"a"` → `"c"`; `from: nil, by: 1` → `"a"`; `from: nil, by: -1` → `"c"`; `in: []` → `nil`; `in: ["a"], from: "a", by: 1` → `"a"`.
  - `shouldCommit(typed: "1", count: 100) == false`; `("12", 200) == false`; `("12", 100) == true` (120 > 100); `("123", 999) == true`; `("5", 40) == true` (50 > 40); `("4", 40) == false`.
  - `channel(forTyped: "2", in: ["a","b"]) == "b"`; `"0"` → nil; `"3"` → nil.
  - `PadLayout.mode(size: 1366×1024, playing: false, expanded: false) == .rail`; `(1366×1024, true, false) == .watch`; `(1024×1366, true, false) == .stacked`; `(1024×1366, true, true) == .watch`; `(500×800, true, false) == .stacked`.
  - `keep(.active, pip: false, pausedFor: 0) == true`; `(.inactive, false, 0) == true`; `(.background, false, 0) == false`; `(.background, true, 0) == true`; `(.background, true, 9) == true`; `(.background, true, 10) == false`.
- [ ] **Step 2:** `swift test` → fails to compile.
- [ ] **Step 3:** Implement in `Decisions.swift`. Mac `ContentView.step/type/commitTyped` use `Zap` with identical behaviour.
- [ ] **Step 4:** `swift test` all pass; Mac build-app, ↑↓ and typed numbers behave as before.
- [ ] **Step 5:** Commit `Zap, layout and connection decisions in core, with tests`.

### Task 4: iPad project that builds and launches

**Files:**
- Create: `iPad/OnAir.xcodeproj` (file-system-synchronised groups pointing at `../Sources/OnAirCore` and `../Sources/OnAirPad`), `iPad/Info.plist`, `iPad/Assets.xcassets` (AppIcon from `docs/icon.png` / `scripts/make-icon.swift`, AccentColor as Mac)
- Create: `Sources/OnAirPad/OnAirPadApp.swift` (`@main struct OnAirPadApp: App`, `Store` in environment, `Brand.registerFonts()`, dark scheme, tint `Brand.signal`), placeholder `PadRoot` view showing `Wordmark` and `store.channels.count`
- Create: `scripts/fake-provider.py` (copy of the scratchpad `fakeprov/server.py`, port 18765, no real credentials), `scripts/build-ipad.sh`
- Modify: `.gitignore` (`iPad/build/`, `*.xcuserstate`, `xcuserdata/`)

**Info.plist values:** `UIBackgroundModes = [audio]`, `NSAppTransportSecurity.NSAllowsArbitraryLoads = true`, `UIRequiresFullScreen = false`, `UISupportedInterfaceOrientations~ipad` = all four, `UIAppFonts = [ArchivoBlack.ttf]` (font file in Copy Bundle Resources from `Support/Fonts`), `CFBundleShortVersionString` = Mac's current version.

- [ ] **Step 1:** `scripts/build-ipad.sh` runs `xcodebuild -project iPad/OnAir.xcodeproj -scheme OnAir -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=27.2' -derivedDataPath iPad/build build` and prints the `.app` path.
- [ ] **Step 2:** Run it. Expected: `BUILD SUCCEEDED`. Fix any core code that doesn't compile on iOS with the smallest change (prefer SwiftUI API available on both; `#if os(macOS)` only as last resort, inside core files).
- [ ] **Step 3:** Check settings: `xcodebuild -showBuildSettings | grep -E "SWIFT_VERSION|SWIFT_DEFAULT_ACTOR_ISOLATION|IPHONEOS_DEPLOYMENT_TARGET|TARGETED_DEVICE_FAMILY"` → `5`, not MainActor, `17.0`, `2`.
- [ ] **Step 4:** Start `python3 scripts/fake-provider.py` in the background; seed the sim with `xcrun simctl spawn booted defaults write com.sousalab.onair playlists -data <hex>` (Xtream playlist for `http://127.0.0.1:18765`, test user, password in sim Keychain via first-run add flow if seeding the Keychain is not possible). Launch with the simulator tool, screenshot: wordmark in Archivo Black and a channel count of 15.
- [ ] **Step 5:** `swift test` and Mac `build-app.sh` still pass.
- [ ] **Step 6:** Commit `iPad project: builds, launches, loads a playlist`.

### Task 5: iPad player

**Files:**
- Create: `Sources/OnAirPad/PadPlayerView.swift` — `struct PadPlayerView: UIViewRepresentable` hosting a `UIView` whose `layerClass` is `AVPlayerLayer`; params `player: AVPlayer`, `fill: Bool` (`videoGravity` `.resizeAspectFill` / `.resizeAspect`), `onPictureInPicture: (Bool) -> Void`
- Create: `Sources/OnAirPad/PadSession.swift` — `@Observable final class PadSession` owning the PiP controller, audio session and idle timer

**Interfaces (Produces):**
- `PadSession.configureAudio()` → `AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)`; activate on first play.
- `PadSession.pipActive: Bool`, `PadSession.startPictureInPicture()`, PiP via `AVPictureInPictureController(playerLayer:)` with `canStartPictureInPictureAutomaticallyFromInline = true`.
- `PadSession.update(phase: ScenePhaseLike, playing: Bool)` → sets `UIApplication.shared.isIdleTimerDisabled = (phase == .active && playing)`; applies `ConnectionPolicy.keep`, calling `playback.release()` when false. A 1 s timer tracks `pausedFor` while in background with PiP.
- Reconnect triggers: `scenePhase` back to `.active` while a channel is current and stalled; `AVAudioSession.interruptionNotification` ended → `playback.reconnectNow(reason: "interruption")`.
- `AirPlayButton: UIViewRepresentable` wrapping `AVRoutePickerView` (tint `Brand.paper`).

- [ ] **Step 1:** In `PadRoot`, tapping a channel name from a plain list plays it in `PadPlayerView` (temporary UI). Build, launch, play "Test One": picture visible in a screenshot within 10 s.
- [ ] **Step 2:** Leave the app (Home): PiP window appears (screenshot), sound continues. Close PiP: `log show` shows the session stopped; the fake provider's stderr shows no more `REQ /live` lines after ~10 s.
- [ ] **Step 3:** Leave with PiP disabled in sim settings → release at once (no more requests).
- [ ] **Step 4:** Return: last channel shown as ready ("Resume <name>" button, using `playback.lastStopped`), nothing playing until tapped.
- [ ] **Step 5:** Commit `iPad player, PiP, audio, idle timer, connection lifecycle`.

### Task 6: Rail and stage (nothing playing)

**Files:**
- Create: `Sources/OnAirPad/PadRail.swift` — playlist menu (switch, add, remove, Compact list toggle, About), search field, filters (`SidebarItem`: All, Favourites, Recents, groups) and the channel list using shared `ChannelRow`, `RailMessage`, first-load `.rise` exactly as the Mac (`active: firstLoad && i < 24`, `.timingCurve(0.23,1,0.32,1,duration:0.3)`, 0.03 s per row).
- Create: `Sources/OnAirPad/PadRoot.swift` (replaces the placeholder) — chooses `PadLayout.mode`.

- [ ] **Step 1:** Landscape 13": rail left (361 pt, as Mac), stage right with the empty state. Portrait: rail fills the screen. Screenshots of both.
- [ ] **Step 2:** Rows ≥ 54 pt tall in normal mode (compact keeps the Mac's compact padding but ≥ 44 pt). Measure from the screenshot.
- [ ] **Step 3:** Search "two" → only "Test Two"; empty search result shows the RailMessage, no crash.
- [ ] **Step 4:** Commit `iPad rail and empty stage`.

### Task 7: Watch, stacked and the list peek

**Files:**
- Create: `Sources/OnAirPad/PadStage.swift` — the picture (`PadPlayerView`), `TuningOverlay`, `SoundOnlyCard`, failed capsule, `InPictureInPictureView` when PiP, docked `NowBar` in stacked mode.
- Modify: `Sources/OnAirPad/PadRoot.swift` — mode switching; peek overlay of `PadRail` from the left in watch, with shadow, opening/closing in 0.22 s (`Motion` easeOut as Mac `openPeek/closePeek`); closes on pick, tap outside, or swipe left.

- [ ] **Step 1:** Pick a channel in landscape → full-screen picture (rail gone, `.move(edge: .leading)` with the Mac's 0.22 s easeOut).
- [ ] **Step 2:** Rotate to portrait while playing → stacked (picture 16:9 on top, NowBar docked, list below); the stream does not restart (one `start` in logs). Rotate back → watch.
- [ ] **Step 3:** Portrait expand button → watch; swipe down or the button → stacked.
- [ ] **Step 4:** Swipe in from the left edge (≤ 24 pt start) in watch → list over the picture; pick → it closes and the channel tunes.
- [ ] **Step 5:** Narrow window (Stage Manager / iPadOS windowing in the 27.2 sim) → same rules by size; controls never under the window buttons (screenshot).
- [ ] **Step 6:** Commit `iPad watch, stacked and peek`.

### Task 8: Touch controls, channel card and keyboard

**Files:**
- Create: `Sources/OnAirPad/PadControls.swift` — top bar: list, last channel (name), AirPlay, PiP, expand, playlist menu; ≥ 54 pt targets; shown 3 s on tap (Mac `wake` rule: fade 0.26 in, 0.2 out), placed after the window-controls safe area.
- Create: `Sources/OnAirPad/PadGestures.swift` — gesture layer over the picture.
- Modify: `PadStage.swift` — `ChannelCard` bottom-leading (scale 0.55, padding 36), above the NowBar, shown at once on a change, held 3 s, fade 0.2; number tick as Mac.

**Gestures:** vertical swipe ≥ 60 pt or velocity ≥ 500 pt/s → `Zap.step` by +1 (up) / −1 (down); tap toggles controls; two-finger tap → last channel; pinch toggles `fill`; `.defersSystemGestures(on: .bottom)` and `.persistentSystemOverlays(.hidden)` in watch. During the drag the picture follows the finger vertically (rubber-banded past 80 pt) and settles back with `.spring(duration: 0.35, bounce: 0)` carrying the release velocity; the flick commits by the velocity rule above, not distance alone. The left-edge peek tracks the finger the same way and settles open/closed by projected position. Repeated swipes within 0.6 s tick the card number and start only the final channel after the 0.6 s settles (cancel earlier pending starts).

**Keyboard** (`.onKeyPress` on the root, ignored while the search field is focused): ↑/↓ step, digits via `Zap.shouldCommit`/`channel(forTyped:)` with the Mac's 1.2 s wait, delete → last channel, return/esc toggle watch.

- [ ] **Step 1:** Swipe up in watch → card bottom-left shows the next number before the picture arrives (record frames: card visible in the first frame after the gesture).
- [ ] **Step 2:** Five quick swipes → number ticks five times, fake provider log shows one new stream request.
- [ ] **Step 3:** Two-finger tap flips between the last two channels; the last-channel button shows the other's name.
- [ ] **Step 4:** Top-left of the picture stays clear while the card is up (screenshot).
- [ ] **Step 5:** Hardware keyboard in the sim: ↓ steps; typing `2` tunes channel 2 after 1.2 s; delete → last channel.
- [ ] **Step 6:** Reduce Motion on (sim Settings) → cross-fades, no slides; card number still ticks without movement.
- [ ] **Step 7:** Commit `iPad touch controls, channel card, keyboard`.

### Task 9: Add playlist, About, settings

**Files:**
- Create: `Sources/OnAirPad/PadAddPlaylist.swift` — sheet with the Mac flow (M3U URL, file, Xtream, free lists). If `AddPlaylistView` compiles on iOS unchanged, move it to core instead and wrap it.
- Create: `Sources/OnAirPad/PadAbout.swift` — `Wordmark`, `Manifesto`, version, source link; no updater.
- Modify: `Sources/OnAirCore/Store.swift` only if needed for the file copy, keeping the Mac path untouched.

**File import:** on iPad, the picked file is copied (security-scoped access) to `Application Support/Playlists/<uuid>.m3u` and that path stored in `.m3u(location:)`.

- [ ] **Step 1:** Add the fake provider via the Xtream form in the sim → list loads, password in Keychain (not in UserDefaults: `defaults read` shows none).
- [ ] **Step 2:** Import an `.m3u` from Files, then delete the original → list still loads after relaunch.
- [ ] **Step 3:** Remove a playlist → gone after relaunch. About shows version, no update UI.
- [ ] **Step 4:** Commit `iPad add playlist, About, settings`.

### Task 10: Full verification and project records

- [ ] **Step 1:** Run every check in Tasks 5–9 again on iPad mini (A17 Pro) 27.2 and iPad Air 11-inch on 26.5; screenshots of watch, stacked, rail, peek per device into `docs/ipad/`.
- [ ] **Step 2:** One-connection check: with the Mac test copy playing from the fake provider (max 1), start on iPad → "Waiting for your provider…"; stop the Mac → iPad tunes.
- [ ] **Step 3:** `swift test`, Mac `build-app.sh`, launch the Mac app and play/zap/Watch: unchanged.
- [ ] **Step 4:** Update `ROADMAP.md` (iPad items done, real-device test left for Jorge, Mac channel-card-to-bottom-left follow-up), `projects.json` next step, run `node hub.mjs` at the root.
- [ ] **Step 5:** Commit `iPad: verified in simulators`. No push.
- [ ] **Step 6:** Hand Jorge the real-device steps: connect the iPad, open `iPad/OnAir.xcodeproj`, pick his iPad, Run (automatic signing on team L4ZLV2Y44P).
