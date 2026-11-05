#!/usr/bin/env bash
# Releases a new ONAIR version end to end:
#   scripts/release.sh 0.1.1 "What changed, one line per item"
# 1. sets the version in Support/Info.plist and commits it
# 2. tags vX.Y.Z, pushes, and publishes the GitHub release (this is what the in-app check reads)
# 3. pins the Homebrew formula to the new tarball and pushes it to jorgesousa/homebrew-tap
# Needs: gh (logged in), a clean working tree on main.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh X.Y.Z \"notes\"}"
NOTES="${2:-}"
TAG="v$VERSION"
TAP_REPO="jorgesousa/homebrew-tap"

[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean."; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Not on main."; exit 1; }

/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" Support/Info.plist
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Support/Info.plist)
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $((BUILD + 1))" Support/Info.plist
git commit -qam "ONAIR $VERSION"
git tag -a "$TAG" -m "ONAIR $VERSION"
git push -q origin main "$TAG"

gh release create "$TAG" --title "ONAIR $VERSION" --notes "$NOTES

### Update
\`\`\`
brew update && brew upgrade onair
\`\`\`"

URL="https://github.com/jorgesousa/onair/archive/refs/tags/$TAG.tar.gz"
SHA=$(curl -fsSL "$URL" | shasum -a 256 | cut -d' ' -f1)
sed -i '' -E "s|^  url \".*\"|  url \"$URL\"|; s|^  sha256 \".*\"|  sha256 \"$SHA\"|" packaging/homebrew/onair.rb
git commit -qam "Formula: onair $VERSION"
git push -q origin main

TMP=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TMP" -- -q
cp packaging/homebrew/onair.rb "$TMP/Formula/onair.rb"
git -C "$TMP" commit -qam "onair $VERSION"
git -C "$TMP" push -q origin HEAD:main
rm -rf "$TMP"

echo "Released $TAG. Users get the UPDATE tag within a day; brew upgrade onair installs it."
