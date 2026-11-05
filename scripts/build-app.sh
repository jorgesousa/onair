#!/usr/bin/env bash
# Builds OnAir.app into ./build (ad-hoc signed).
#   scripts/build-app.sh            # build
#   scripts/build-app.sh --install  # build and copy to ~/Applications
# Other arguments go to `swift build` (Homebrew passes --disable-sandbox).
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0; ARGS=()
for a in "$@"; do [[ "$a" == "--install" ]] && INSTALL=1 || ARGS+=("$a"); done

APP="build/OnAir.app"
swift build -c release --product OnAir ${ARGS[@]+"${ARGS[@]}"}
BIN="$(swift build -c release --product OnAir ${ARGS[@]+"${ARGS[@]}"} --show-bin-path)/OnAir"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OnAir"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/Fonts/*.ttf "$APP/Contents/Resources/"
# Accent colour (signal orange) for selections and controls. Needs actool from Xcode.
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool Support/Assets.xcassets --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --accent-color AccentColor \
    --output-partial-info-plist build/assets-info.plist >/dev/null
fi
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ $INSTALL == 1 ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/OnAir.app"
  cp -R "$APP" "$HOME/Applications/"
  rm -rf "$HOME/Applications/SousaTV.app"   # the app's first name
  echo "Installed ~/Applications/OnAir.app"
fi
