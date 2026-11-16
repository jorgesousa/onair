# How ONAIR works

The technical side, for developers and the curious. The [README](../README.md) is the short version.

## Playback and providers

- Per-stream `http-user-agent` / `http-referrer` hints in a list (and `#EXTVLCOPT`) are sent with the stream; some channels need them.
- `get.php?username=…&password=…` M3U links are read as Xtream accounts, which unlocks the guide.
- The guide is the account's XMLTV, downloaded once and refreshed every 3 hours. It is not fetched per channel. A playlist without an Xtream account can name its guide in its header (`url-tvg` or `x-tvg-url`), which is how a Dispatcharr playlist gets one.
- Playback is AVFoundation, so streams must be HLS. Raw MPEG-TS links are asked for as `/live/…/<id>.m3u8`, which Xtream servers serve.
- Many providers answer a channel link with a redirect to a session URL. ONAIR resolves it once and plays the session URL: re-requesting the original link on every playlist refresh (what AVFoundation does) opens a new session each time and stalls the stream after ~30 s.
- A watchdog reconnects on its own when the picture stops for more than a few seconds, the stream fails or ends, or the Mac wakes from sleep, waiting longer after each try (1 s up to 30 s) and never giving up while the channel is picked.
- Most accounts allow one connection. Switching closes the old stream first and retries a refused one before giving up.
- A channel that never shows a picture after 3 tries and 20 seconds says OFF AIR instead of reconnecting forever; pick it again to retry. A channel whose video the device can't decode says CAN'T PLAY.
- Passwords are stored in the Keychain. Everything else is stored in the app's preferences.
- ONAIR talks to your provider and, once a day, asks GitHub for the latest release number. That request carries nothing about you. Turn it off in About ONAIR → "Check for updates automatically".
- Films and series are built but hidden (`ContentView.showsLibraries`).

## Releasing a version

```bash
scripts/release.sh 0.1.2 "- What changed"
```

The script sets the version in `Support/Info.plist`, tags `vX.Y.Z`, publishes the GitHub release, pins the formula to the new tarball and pushes it to [jorgesousa/homebrew-tap](https://github.com/jorgesousa/homebrew-tap). From then on:

- **ONAIR tells people.** Once a day it asks GitHub for the latest release. If it's newer, an UPDATE tag appears at the bottom of the channel list and in About ONAIR.
- **The app installs it.** Update now runs `brew upgrade onair` (or `git pull` and the build script for a source build) and restarts ONAIR.
- **Nothing is lost.** Lists, saved channels and passwords stay across updates.

## Testing

Put a test account in `.test-account` (ignored by Git) with `SERVER`, `USERNAME` and `PASSWORD`, then run `scripts/smoke-test.sh`.

## One TV, several screens

The Dispatcharr setup, the channel-change flow, the per-channel fix script and the on-screen states, with diagrams: [DISPATCHARR.md](DISPATCHARR.md). In the code: `HomeLink`, `Follow` and `.followsHome` in `Sources/OnAirCore`, and the Dispatcharr branch of `PlaybackController.start()`.

## Updates

**Update now** runs `brew update` and `brew upgrade onair` itself, shows the progress, and restarts in the new version. If Homebrew belongs to another account on the Mac, the same steps open in Terminal so you can type that account's password. A source build runs `git pull` and the build script instead.

A Homebrew install compares with the version the tap serves (what `brew upgrade` installs). Releases are GitHub releases tagged `vX.Y.Z`; see "Releasing a version".

## Code layout

- `Sources/OnAirCore`: everything shared by the Mac, the iPad and the iPhone (playback, lists, guide, shared views).
- `Sources/OnAir`: the Mac app. `Sources/OnAirPad` + `iPad/OnAir.xcodeproj`: the universal iPad and iPhone app.
- `Sources/OnAirCore/FreeLists.swift`: the one-click free lists.
