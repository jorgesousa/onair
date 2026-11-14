# ONAIR for iPad — design

Date: 2026-11-14 · Status: draft for approval

## Why

Jorge watches live TV on the iPad, mostly football, while cooking or eating at a side
table. The iPad sits propped up a short distance away. Hands are busy, wet or greasy, so
touches are few and rough. He is **watching**, not listening; the picture is the point.
The Mac app (ONAIR 0.1.3+, SwiftUI, Homebrew) already has the look, the motion and the
provider handling he likes. The iPad version is that app for the counter.

It is for his own iPad. Not the App Store.

## Goals

- Put a channel on in two taps and leave it playing for a whole match.
- Changing channel works without aiming: one swipe on the picture.
- Flip between two matches instantly (the Mac's ⌫ "last channel").
- Readable from across the kitchen: channel card, now/next, clock.
- The same Test Card look and motion as the Mac (tokens, tuning fold, channel card,
  number tick, first-load rise), adapted to touch.
- Same provider behaviour as the Mac: one-connection rule, "Waiting for your provider…",
  reconnects, SOUND ONLY notice.
- Landscape and portrait, all iPad sizes, and resizable windows (iPadOS 26+ windowing).
- Keep the core clean of UI code so an Android port later is a translation job
  (see ROADMAP, Later).

## Non-goals

- App Store / TestFlight release (possible later, needs its own OK).
- Syncing playlists or logins with the Mac. Each device has its own list. (Later: iCloud.)
- iPhone layout. The target is iPad only.
- The Mac's TV-as-second-screen window, the Homebrew updater, update checks.
- Recording, timeshift, scrubbing back in a live stream.

## Anti-goals (fail even if it "works")

- An overlay sitting on the broadcaster's score and clock (top-left in most football
  coverage) while you're trying to read it.
- The screen locking or dimming mid-match.
- A zap that feels slow or uncertain: a swipe that doesn't register, or no feedback
  until the stream arrives.
- Any change that alters the Mac app's behaviour or its build/release.
- Two copies of the same logic that drift apart.

## Constraints

- Provider allows **one connection**. Mac and iPad cannot play at the same time; the
  second one gets "Waiting for your provider…" until the first stops. This is shown, not
  fixed.
- IPTV credentials live only in `.test-account` (gitignored). Never committed, printed or
  sent anywhere. Grep the staged diff for USERNAME / PASSWORD / SERVER before each commit.
- No push, release or public action without Jorge's explicit OK.
- English UI.
- iPadOS 17 minimum (Observation framework, same era as macOS 14).
- Running on his real iPad needs an Apple Development certificate on team L4ZLV2Y44P
  (automatic signing in Xcode). That team is a paid Developer Program team (it already
  holds a Developer ID Application certificate), so installs don't expire after 7 days.
  Simulator work needs nothing.
- Simulator runtimes installed: iOS 26.5, 27.0, 27.2. Test on 27.2 and 26.5.

## Approaches considered

1. **Shared core, two apps — chosen.** Code both platforms need moves to
   `Sources/OnAirCore`. The Mac app keeps building with SwiftPM as today. A new Xcode
   project builds the iPad app from `OnAirCore` plus `Sources/OnAirPad`. Fixes to the core
   reach both; Mac screens are untouched; cleanest base for an Android port.
2. One multiplatform target with `#if os(...)` inside the screens. Fewer files, but the
   982-line `ContentView` fills with branches and every iPad change risks the Mac app.
   Rejected (anti-goal: don't disturb the Mac).
3. Copy the code into a separate iPad project. Fastest start, then drift and double fixes.
   Rejected.
4. Cross-platform rewrite (Flutter / React Native) to cover Android too. Throws away the
   SwiftUI motion work and AVKit's PiP/AirPlay, and still leaves the Mac separate.
   Rejected; Android stays a Later item.

Chosen by: Claude as CTO, with Jorge's go-ahead to make the technical calls.

## Code structure

```
Sources/
  OnAirCore/     shared, no AppKit/UIKit
    Models, M3UParser, Xtream, Guide, Keychain, FreeLists, Store,
    Brand (colours, fonts, Bars, BarsProgress), Motion (tokens, Rise, CRTOff,
    TuningOverlay), PlaybackController (AVFoundation only), ChannelCard,
    and any other pure-SwiftUI piece that needs no platform branch
  OnAir/         Mac only (unchanged behaviour)
    OnAirApp, ContentView, PlayerView (AVPlayerView), TVScreen, Updater,
    Updates, AboutView, AddPlaylistView (unless it moves to core cleanly)
  OnAirPad/      iPad only
    app entry, screens, player view, gestures, iPad About
iPad/OnAir.xcodeproj   the iPad app target
```

- **One module per app, no `public` sweep.** Package.swift keeps a single Mac
  executable target that compiles both `OnAir/` and `OnAirCore/`
  (`path: "Sources"`, `sources: ["OnAir", "OnAirCore"]`). The Xcode iPad target compiles
  `OnAirCore/` and `OnAirPad/` directly. No access-modifier churn, no package product.
  If SwiftPM's layout fights this, fall back to a library target with `public` API.
- `PlaybackController` is split out of `PlayerView.swift` into core. It is AVFoundation
  plus one AppKit hook: it reconnects on `NSWorkspace.didWakeNotification`
  (PlayerView.swift:80). In core that becomes a public `reconnectNow(reason:)` and a
  `stop()` that releases the connection; each app wires its own triggers (Mac: wake;
  iPad: back to the foreground, audio interruption ended, network back). The Mac
  `PlayerView` (NSViewRepresentable) stays in `OnAir/`.
- **M3U file playlists:** the Mac stores the picked file's path and rereads it
  (AddPlaylistView.swift:98, Store.swift:131). On iPad that path is outside the sandbox
  later, so the iPad copies the file into the app's own storage on import and stores
  that path. The Mac keeps its current behaviour.
- **Same compiler settings for the core on both apps:** Swift 5 language mode, no
  default main-actor isolation, matching the package. New Xcode 27 project defaults
  (Swift 6, MainActor default) must be switched off for the iPad target.
- `Brand` drops `import AppKit`. Fonts register through CoreText on both platforms; the
  iPad bundle includes `Support/Fonts/ArchivoBlack.ttf`.
- Data stays per device: `UserDefaults` + Keychain, same keys as the Mac.
- The Mac build, `scripts/build-app.sh`, `release.sh`, `smoke-test.sh` and the Homebrew
  formula must still work unchanged (paths updated only if they must be). Verify the Mac
  app before and after the move behaves the same.

## The iPad app

### Player

- Our own view around `AVPlayerLayer`, not `AVPlayerViewController`: live TV needs no
  scrubber, and the system controls would swallow our swipes.
- Picture in Picture through `AVPictureInPictureController(playerLayer:)`, starting
  automatically when he leaves the app while playing. Same "IN THE SMALL WINDOW" screen
  as the Mac while PiP is up.
- AirPlay through `AVRoutePickerView` in the controls. With the one-connection provider
  AirPlay may misbehave; it is offered, not promised.
- Audio session `.playback` (sound with the silent switch on, keeps playing in the
  background / PiP). Background mode: audio.
- Screen stays awake (`isIdleTimerDisabled`) while a channel plays and the app is active;
  normal again when stopped or failed.
- **The connection lives only while there is a picture** (he watches, not listens; the
  Mac needs the slot back). Keeps playing: app on screen, or Picture in Picture. Stops
  and releases the connection: PiP window closed, iPad locked, or app left with PiP
  off/unavailable. Coming back shows the last channel ready, one tap to resume (no
  silent auto-reconnect that would steal the slot from the Mac). Claude's call.

### Layout

- **Nothing playing:** the Mac layout — channel rail (playlist menu, search, filters,
  list) on the left, stage on the right with the "pick a channel" state. In portrait the
  rail fills the screen.
- **Playing = Watch mode.** Picking a channel fills the screen with the picture. The list
  comes back over the picture by swiping in from the left edge or tapping the list
  button; it closes on pick, on a tap on the picture, or by swiping it away. Same peek
  timing as the Mac (0.22 s).
- **Which layout while playing is decided by the window's shape, not orientation:**
  wider than tall → full-screen Watch; taller than wide → stacked (picture on top at
  16:9, now/next bar docked under it, channel list below). In stacked, a full-screen
  button (or tapping "expand" in the controls) gives full-screen Watch in portrait too,
  with the picture letterboxed; a swipe down on it or the button returns. The Mac's
  docked-bar rule is not used for this; it only applies to the now bar inside stacked.
  Claude's call.
- **Windows (iPadOS 26+ windowing):** same rules by window size. In a window the system
  draws window controls at the top-left, so our top controls bar starts after them
  (respect the window-controls safe area), and nothing of ours sits there.

### Touch

| Gesture on the picture | Does |
| --- | --- |
| Tap | Show controls + now bar for 3 s (Mac rule); tap again hides |
| Swipe up / down | Next / previous channel in the current list |
| Swipe in from left edge | Channel list over the picture |
| Two-finger tap, or the "last" button | Back to the last channel |
| Pinch | Fit / fill (zoom to remove black bars) |

- Controls (top bar): list, last channel (shows its name), AirPlay, PiP, playlist menu.
  Large targets (≥ 54 pt) for rough taps.
- A swipe gives feedback at once: the channel card appears with the new number before
  the stream arrives, and fast repeated swipes only tick the number (as on the Mac).
- Swipe-to-zap starts away from the bottom edge; the app defers the system's
  bottom-edge gesture while in Watch so a zap doesn't send him home.
- A hardware keyboard gets the Mac keys: ↑↓, digits to type a number, ⌫ last channel,
  ⏎ / esc for Watch.

### Overlays and placement (football rule)

- The **channel card sits bottom-left** on iPad, above the now bar, shown 3 s on a change
  and while typing. The top-left belongs to the broadcaster's score and clock.
- The controls bar is the only thing at the top, and only while shown.
- Tuning fold, SOUND ONLY card, failed capsule, "Waiting for your provider…": same as the
  Mac, centred.
- Follow-up for the Mac (not in this work): its Watch card is top-left too; consider the
  same move there. Listed in ROADMAP.

### Motion

- Same tokens (`Motion.snap/enter/fade/quick`) and pieces (TuningOverlay, CRTOff, number
  tick, first-load rise capped like the Mac, NowBar title push).
- Swipe-to-zap and the list peek follow the finger and settle with a critically damped
  spring; a flick commits by velocity, not only distance.
- No animation on keyboard-driven actions (same rule as the Mac).
- Reduce Motion: cross-fades instead of moves, as on the Mac.
- No haptics (most iPads have no Taptic Engine).

### Other screens

- Add playlist: the Mac flow (M3U URL, file, Xtream login, free lists), as a sheet.
- About: brand page without the updater; version and source link.
- Settings in the playlist menu: compact list, remove playlist.

## Verifying

- Build and run in the iPad simulators (Pro 13", Air 11", mini), landscape and portrait,
  plus a narrow resizable window.
- Use the fake Xtream provider (one connection, short programmes, public Apple/Mux test
  streams), moved from the scratchpad into `scripts/fake-provider.py` so it survives.
  No real credentials in the repo.
- Drive it with the simulator tool: tap, swipe-to-zap, edge peek, last channel, PiP,
  rotation; record frames to check the motion like on the Mac.
- Re-run the Mac build and smoke test to prove nothing changed there.
- Real-device check (screen awake through a match, PiP over another app, real provider)
  needs Jorge's iPad connected and signing set up; that is the last step and his to do.

## Left to the builder

- Exact swipe thresholds and velocities, edge-swipe width.
- Which further pure-SwiftUI views (ChannelRow, NowBar, RailMessage…) move to core;
  share when it needs no platform branch, otherwise keep per platform.
- Xcode project mechanics (file-system-synchronised groups are fine; no extra tools
  required to build; `xcodebuild` must build it from the command line).
- App icon export for iPad from the existing icon source.
- Bundle id `com.sousalab.onair` (same as the Mac, leaves universal purchase open).
