# Homebrew cask for Trimshot.
#
# This file is the source of truth; `scripts/release.sh` stamps the version and sha256 from
# the disk image it just built, then tells you what to copy into the tap repository
# (github.com/anhthienonline/homebrew-trimshot, at Casks/trimshot.rb).
#
# Installing from here takes three commands, not two: Homebrew 6 refuses to load anything
# from a tap outside its own repositories until the user runs `brew trust`. Measured — the
# tap clones fine and then the install stops with "Refusing to load cask ... from untrusted
# tap". Any instructions that show only `tap` and `install` are broken for everybody.
#
# IMPORTANT, and the reason this is not the headline install method: Homebrew Cask
# quarantines its downloads by default. `brew install --cask trimshot` therefore still hits
# Gatekeeper on an un-notarised build, exactly like downloading the dmg by hand — the user
# still has to allow it once in System Settings. The `--no-quarantine` flag that used to
# skip that is being removed, and Homebrew is moving toward requiring casks to pass
# Gatekeeper outright. So brew buys convenient installs and updates here, not a bypass, and
# an un-notarised cask may stop being accepted.
cask "trimshot" do
  version "0.1.0"
  sha256 "b9b35d2bfad3f3c99dde15233fa50d1643b8d8a3851375927b01ed55d8a724b8"

  url "https://github.com/anhthienonline/trimshot/releases/download/v#{version}/Trimshot.dmg",
      verified: "github.com/anhthienonline/trimshot/"
  name "Trimshot"
  desc "Precision screen capture for design QA, reporting points and pixels together"
  homepage "https://github.com/anhthienonline/trimshot"

  # ScreenCaptureKit's SCScreenshotManager is macOS 14+.
  #
  # The bare symbol, not `">= :sonoma"`: Homebrew deprecated the string comparison form, and
  # the two mean the same thing here. Cask's DSL parses this with `comparator: ">="` already
  # (Homebrew/cask/dsl/depends_on.rb), so this still reads "Sonoma or newer" and does not
  # narrow the requirement to one release.
  depends_on macos: :sonoma

  app "Trimshot.app"

  uninstall quit: "com.thienho.trimshot",
            login_item: "Trimshot"

  zap trash: [
    "~/Library/Preferences/com.thienho.trimshot.plist",
  ]

  caveats <<~EOS
    Trimshot is signed but not notarised, so macOS will block the first launch.

    Allow it once in System Settings > Privacy & Security — scroll to the blocked-app
    notice and click "Open Anyway". macOS 15 removed the Control-click > Open shortcut.

    Then press Control-G and grant Screen Recording access when asked.
  EOS
end
