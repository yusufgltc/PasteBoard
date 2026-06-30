cask "pasteboard" do
  version "1.0.0"
  # After each release, update sha256 with:
  #   shasum -a 256 PasteBoard-{version}.dmg
  sha256 "REPLACE_WITH_SHA256_OF_DMG"

  url "https://github.com/ygultac/PasteBoard/releases/download/v#{version}/PasteBoard-#{version}.dmg"
  name "PasteBoard"
  desc "Clipboard history manager for macOS"
  homepage "https://github.com/ygultac/PasteBoard"

  # Minimum macOS version required by the app
  depends_on macos: ">= :sequoia"

  app "PasteBoard.app"

  # Remove all app data on `brew uninstall --zap pasteboard`
  zap trash: [
    "~/Library/Application Support/PasteBoard",
    "~/Library/Preferences/com.pasteboard.app.plist",
    "~/Library/Saved Application State/com.pasteboard.app.savedState",
  ]
end
