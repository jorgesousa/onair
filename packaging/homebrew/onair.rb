# Homebrew formula for ONAIR. Served from jorgesousa/homebrew-tap as Formula/onair.rb;
# this copy is the source it's updated from. See "Releasing a version" in the README.
#
#   brew install jorgesousa/tap/onair
#   brew update && brew upgrade onair
class Onair < Formula
  desc "Just TV: IPTV player for macOS with no ads, watermarks, accounts or tracking"
  homepage "https://github.com/jorgesousa/onair"
  url "https://github.com/jorgesousa/onair/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "21a13574c1694cc06e1a16519a69391ad0b8df70dffc57d3701744cbe3719986"
  license "MIT"
  head "https://github.com/jorgesousa/onair.git", branch: "main"

  depends_on macos: :sonoma

  def install
    # Built with the system Swift toolchain and ad-hoc signed. SwiftPM's own sandbox
    # can't nest inside Homebrew's build sandbox.
    system "scripts/build-app.sh", "--disable-sandbox"
    prefix.install "build/OnAir.app"
  end

  def caveats
    <<~EOS
      To open ONAIR:
        open "#{opt_prefix}/OnAir.app"

      To keep it in Finder, Launchpad search and the Dock, link it once.
      The link goes through #{opt_prefix}, so it follows every upgrade:
        ln -sf "#{opt_prefix}/OnAir.app" ~/Applications/OnAir.app

      ONAIR tells you when a new version is out. To update:
        brew update && brew upgrade onair
      Then quit ONAIR and open it again. Lists, saved channels and passwords stay.
    EOS
  end

  test do
    assert_path_exists prefix/"OnAir.app/Contents/MacOS/OnAir"
  end
end
