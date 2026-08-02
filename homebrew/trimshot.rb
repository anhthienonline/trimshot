# Homebrew cask for Trimshot.
#
# This file is the source of truth; `scripts/release.sh` stamps the version and sha256 from
# the disk image it just built, then tells you what to copy into the tap repository
# (github.com/hokhacthien91/homebrew-trimshot, at Casks/trimshot.rb).
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
  sha256 "99dbc53ab5efaa9e4fe084433fdb6a1550f073256b6b6e4c0146ef935536a167"

  url "https://github.com/hokhacthien91/trimshot/releases/download/v#{version}/Trimshot.dmg",
      verified: "github.com/hokhacthien91/trimshot/"
  name "Trimshot"
  desc "Precision screen capture for design QA, reporting points and pixels together"
  homepage "https://github.com/hokhacthien91/trimshot"

  # ScreenCaptureKit's SCScreenshotManager is macOS 14+.
  depends_on macos: ">= :sonoma"

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
