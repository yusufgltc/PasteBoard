cask "pasteboard" do
  version "1.0.0"
  sha256 "501b4de9809cd6a42dc302d693953b16c2b5774fab8ed0ccfff1ffc013c6b3c2"

  url "https://github.com/yusufgltc/PasteBoard/releases/download/v#{version}/PasteBoard-#{version}.zip"
  name "PasteBoard"
  desc "Clipboard history for Macs that can't upgrade to macOS Tahoe"
  homepage "https://github.com/yusufgltc/PasteBoard"

  app "PasteBoard.app"

  caveats <<~'EOS'
    Welcome to

        ____             __       ____                       __
       / __ \____ ______/ /____  / __ )____  ____ __________/ /
      / /_/ / __ `/ ___/ __/ _ \/ __  / __ \/ __ `/ ___/ __  /
     / ____/ /_/ (__  ) /_/  __/ /_/ / /_/ / /_/ / /  / /_/ /
    /_/    \__,_/____/\__/\___/_____/\____/\__,_/_/   \__,_/

    ⌘⇧V  open   Tab  navigate   ↵  paste   ⌫  delete

    All data stays on your Mac.
  EOS

  preflight do
    system_command "/bin/rm",
      args: ["-rf", File.expand_path("~/Library/Application Support/PasteBoard")]
    system_command "/bin/rm",
      args: ["-f", File.expand_path("~/Library/Preferences/com.pasteboard.app.plist")]
  end

  postflight do
    print "Enable clipboard monitoring? [y/N]: "
    $stdout.flush
    answer = $stdin.isatty ? ($stdin.gets || "").chomp.downcase : "n"
    puts ""

    if answer == "y"
      system_command "/usr/bin/defaults",
        args: ["write", "com.pasteboard.app", "pasteboardMonitoringEnabled", "-bool", "true"]
      puts "Monitoring enabled. Press ⌘⇧V to open your history."
    else
      system_command "/usr/bin/defaults",
        args: ["write", "com.pasteboard.app", "pasteboardMonitoringEnabled", "-bool", "false"]
      puts "Monitoring is off — click the menu bar icon to open Settings and enable it."
    end

    system_command "/usr/bin/defaults",
      args: ["write", "com.pasteboard.app", "pasteboardHasLaunchedBefore", "-bool", "true"]

    puts ""
    system_command "/usr/bin/open", args: ["-a", "PasteBoard"]
  end

  uninstall quit:   "com.pasteboard.app",
            delete: [
              "~/Library/Preferences/com.pasteboard.app.plist",
              "~/Library/Application Support/PasteBoard",
            ]

  zap trash: [
    "~/Library/Application Support/PasteBoard",
    "~/Library/Preferences/com.pasteboard.app.plist",
    "~/Library/Saved Application State/com.pasteboard.app.savedState",
  ]
end
