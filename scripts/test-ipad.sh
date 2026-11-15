#!/usr/bin/env bash
# Runs the iPad UI tests against the fake provider.
#   scripts/test-ipad.sh                                   # all, iPad Pro 13-inch (M5) iOS 27.2
#   scripts/test-ipad.sh "iPad mini (A17 Pro)" 26.5 OnAirUITests/PlayerTests
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-iPad Pro 13-inch (M5)}"; OS="${2:-27.2}"; ONLY="${3:-}"
curl -sf -o /dev/null "http://127.0.0.1:18765/get.php" || { python3 scripts/fake-provider.py >/dev/null 2>&1 & sleep 1; }
# A run that was stopped can leave the app (and its Picture in Picture) up, which keeps
# Springboard busy and makes every step wait a minute: start clean.
xcrun simctl terminate booted com.sousalab.onair >/dev/null 2>&1 || true
rm -rf iPad/build/results.xcresult
xcodebuild test -project iPad/OnAir.xcodeproj -scheme OnAir \
  -destination "platform=iOS Simulator,name=$DEVICE,OS=$OS" -derivedDataPath iPad/build \
  -resultBundlePath iPad/build/results.xcresult ${ONLY:+-only-testing:"$ONLY"} 2>&1 \
  | grep -E "Test Case|error:|failed|passed|TEST (SUCCEEDED|FAILED)|\*\* " || true
