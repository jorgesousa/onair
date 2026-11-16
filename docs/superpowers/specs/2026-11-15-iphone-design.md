# ONAIR on iPhone — short design

**Why:** watch live TV (mostly football) away from the Mac and the iPad: on the sofa, in bed, out.

**Approach (picked):** the iPad target becomes universal (`TARGETED_DEVICE_FAMILY = 1,2`). Same
`OnAirCore` and the same `OnAirPad` views; only sizes bend for the phone.
- Considered: a separate iPhone target/views (more to keep in sync, nothing gained);
  a SwiftUI `TabView`/`NavigationStack` app (unfamiliar next to the iPad and Mac, more chrome).

**Layout (unchanged model, phone sizes):**
- Portrait, nothing on: the list fills the screen.
- Portrait, playing: picture 16:9 under the status bar, compact now bar, list below.
- Landscape, playing: Watch — full-screen picture, swipe up/down to zap, left edge peeks the list,
  status bar and home indicator hidden, vertical system edges deferred.
- Expand (portrait): full-screen picture.

**Phone-specific:** channel card smaller (Watch 0.42, stacked 0.32) and closer to the edges;
add-playlist sheet at 1×; orientations portrait + both landscapes (no upside-down).

**Non-goals:** iPhone-only features, widgets, Live Activities, CarPlay.

**Left to the builder:** spacing tweaks found on the simulator and on the phone.

**Constraint:** the provider allows one connection — iPhone playing means iPad/Mac are refused
(the refusal hold from 2026-11-15 keeps the app from hammering it).
