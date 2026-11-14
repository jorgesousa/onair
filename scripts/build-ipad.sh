#!/usr/bin/env bash
# Builds the iPad app for the simulator into iPad/build.
#   scripts/build-ipad.sh                       # iPad Pro 13-inch (M5), iOS 27.2
#   scripts/build-ipad.sh "iPad mini (A17 Pro)" 26.5
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-iPad Pro 13-inch (M5)}"; OS="${2:-27.2}"
xcodebuild -project iPad/OnAir.xcodeproj -scheme OnAir -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE,OS=$OS" \
  -derivedDataPath iPad/build build -quiet
echo "iPad/build/Build/Products/Debug-iphonesimulator/OnAir.app"
