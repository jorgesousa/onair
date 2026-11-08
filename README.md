# ONAIR

<a href="https://github.com/jorgesousa/onair/raw/main/docs/onair.mp4">
  <img src="docs/onair-poster.jpg" width="860" alt="ONAIR, an IPTV player for macOS. Click to watch the 23-second video.">
</a>

<sub>▶ <a href="https://github.com/jorgesousa/onair/raw/main/docs/onair.mp4">Watch with sound</a> · 23 seconds</sub>

**Just TV.** No ads. No watermarks. No accounts. No tracking.
**Free and open source. Built like it isn't.**

Free software shouldn't look or feel worse than paid software. ONAIR is built to the same standard as the best paid apps on the Mac, and the code is open so anyone can check every promise. See [docs/BRAND.md](docs/BRAND.md).

ONAIR is an IPTV player for macOS, written in SwiftUI. Add an M3U playlist (a link or a file) or an Xtream Codes account. Channels are numbered like a tuner, and each one shows what's on now. Zap with the arrow keys and press Return for full screen.

ONAIR ships with no channels. Use only playlists you're entitled to.

### Free lists

The add sheet has a **Free** tab with one-click public playlists from [iptv-org](https://github.com/iptv-org/iptv) and [Free-TV/IPTV](https://github.com/Free-TV/IPTV). Both projects only list streams that are free and public: Portugal, Portuguese-language, Free-TV, News, Sports, Movies, Music, Kids, Documentary, and all of iptv-org (over 11,000 channels). They're community lists, so some channels are offline or geo-blocked at any given time, and they carry no programme guide. Edit `Sources/OnAir/FreeLists.swift` to change them.

Know another free, legal list? [Suggest it](https://github.com/jorgesousa/onair/issues/new?title=Free%20list%3A%20&labels=free-list) — there's a link to the same form in the app.

## Install

From source (macOS 14+, Xcode):

```bash
scripts/build-app.sh --install
```

With Homebrew, once the tap is published: `brew install jorgesousa/tap/onair`.

## Updates

When a new version is out, an UPDATE tag appears at the bottom of the channel list and in About ONAIR. Press **Update now**: ONAIR runs `brew update` and `brew upgrade onair` itself, shows the progress, and restarts in the new version. No Terminal needed. If Homebrew belongs to another account on the Mac, the same steps open in Terminal so you can type that account's password. Lists, saved channels and passwords are kept.

A Homebrew install compares with the version the tap serves (what `brew upgrade` installs). Releases are GitHub releases tagged `vX.Y.Z`; see "Releasing a version".

## Keys

| Key | Does |
|---|---|
| ↑ ↓ | Previous / next channel (list focused) |
| ⌘↑ ⌘↓ | Previous / next channel, anywhere |
| Return | Full screen |
| ⌘R | Reload playlist |

## How it works

- Per-stream `http-user-agent` / `http-referrer` hints in a list (and `#EXTVLCOPT`) are sent with the stream; some channels need them.
- `get.php?username=…&password=…` M3U links are read as Xtream accounts, which unlocks the guide.
- The guide is the account's XMLTV, downloaded once and refreshed every 3 hours. It is not fetched per channel.
- Playback is AVFoundation, so streams must be HLS. Raw MPEG-TS links are asked for as `/live/…/<id>.m3u8`, which Xtream servers serve.
- Many providers answer a channel link with a redirect to a session URL. ONAIR resolves it once and plays the session URL: re-requesting the original link on every playlist refresh (what AVFoundation does) opens a new session each time and stalls the stream after ~30 s.
- A watchdog reconnects on its own when the picture stops for more than a few seconds, the stream fails or ends, or the Mac wakes from sleep, waiting longer after each try (1 s up to 30 s) and never giving up while the channel is picked.
- Most accounts allow one connection. Switching closes the old stream first and retries a refused one before giving up.
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

## Credits

By Jorge Sousa. Type: Archivo Black (SIL OFL). MIT licence.
