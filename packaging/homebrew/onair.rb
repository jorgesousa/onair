# Homebrew formula for OnAir. Copy to a tap repo (e.g. jorgesousa/homebrew-tap) as
# Formula/onair.rb. On each release: point `url` at the new tag archive, bump `version`
# to match Support/Info.plist, and set `sha256` to `curl -L <url> | shasum -a 256`.
#
#   brew install jorgesousa/tap/onair
#   brew upgrade onair
class Onair < Formula
  desc "Just TV. An IPTV player for macOS with no ads, watermarks, accounts or tracking"
  homepage "https://github.com/jorgesousa/onair"
  url "https://github.com/jorgesousa/onair/archive/refs/tags/v0.1.0.tar.gz"
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256"
  license "MIT"
  head "https://github.com/jorgesousa/onair.git", branch: "main"

  depends_on macos: :sonoma

  def install
    # SwiftPM's sandbox can't nest inside Homebrew's build sandbox.
    system "scripts/build-app.sh", "--disable-sandbox"
    prefix.install "build/OnAir.app"
  end

  def caveats
    <<~EOS
      To open OnAir:
        open "#{opt_prefix}/OnAir.app"
      To show it in Finder and the Dock, link it once (the link follows upgrades):
        ln -sf "#{opt_prefix}/OnAir.app" ~/Applications/
    EOS
  end

  test do
    assert_path_exists prefix/"OnAir.app/Contents/MacOS/OnAir"
  end
end
