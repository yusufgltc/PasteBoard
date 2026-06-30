# PasteBoard

A lightweight macOS clipboard history manager that lives in your menu bar.
Press **⌘⇧V** anywhere to instantly browse, search, and paste anything you've previously copied.

---

## Features

- **Clipboard history** — stores up to 50 recent items across text, URLs, images, and files
- **Instant search** — start typing to filter history in real time
- **Keyboard-first** — navigate entirely with Tab, arrow keys, Return, and Escape
- **Source app badges** — see which app each item was copied from
- **Configurable retention** — keep history for 30 minutes, 8 hours, or 7 days
- **Image preview** — see copied images before pasting
- **Zero configuration** — works immediately after install, no setup required
- **Native macOS** — built with SwiftUI, no Electron, no background daemons

---

## Install

### Homebrew (recommended)

```bash
brew tap ygultac/pasteboard
brew install --cask pasteboard
```

### Manual

1. Download `PasteBoard.dmg` from the [latest release](https://github.com/ygultac/PasteBoard/releases/latest)
2. Open the DMG and drag **PasteBoard.app** to your Applications folder
3. Launch PasteBoard from Applications or Spotlight

> **Gatekeeper note** — On first launch, macOS may warn that the app was downloaded from the internet.
> Open **System Settings → Privacy & Security** and click **Open Anyway**.

---

## Usage

| Action | Shortcut |
|--------|----------|
| Open PasteBoard | **⌘⇧V** |
| Paste selected item | **Return** |
| Copy without pasting | **⌘C** |
| Navigate down | **↓** or **Tab** |
| Navigate up | **↑** |
| Select item (title preview) | **Tab** |
| Return to search | **Tab** (when item is selected) |
| Dismiss | **Escape** |
| Search | Just start typing |
| Clear search | **⌘A** then **Delete**, or click **✕** |

Click any row to paste it immediately. Double-click to paste and dismiss.

---

## Advanced

### Ignore Copied Items

To prevent specific content from being stored, disable monitoring temporarily:

1. Click the PasteBoard icon in the menu bar
2. Open **Settings → General**
3. Toggle **Enable Monitoring** off while copying sensitive content, then toggle it back on

Alternatively, apps that use the Secure Input API (password managers, Terminal sudo prompts) are automatically excluded.

### Ignore Custom Copy Types

PasteBoard records text, URLs, images, and file paths. It automatically ignores:

- Items copied while monitoring is disabled
- Items copied by PasteBoard itself during a paste operation (no duplicates)
- Items from the same app in the same paste session (Universal Clipboard deduplication)

If a specific app writes non-standard pasteboard types, its plain-text representation is still captured.

### Speed up Clipboard Check Interval

PasteBoard polls the system pasteboard every **0.5 seconds** by default. This is the optimal balance between responsiveness and battery impact. The polling uses only the pasteboard's `changeCount` integer — it reads actual content only when something new is detected, so CPU usage is negligible even at 0.5 s.

If you need faster detection, you can modify `PasteboardMonitor.swift`:

```swift
// Change 0.5 to your preferred interval (in seconds)
timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
    self?.check()
}
```

---

## FAQ

### Why doesn't it paste when I select an item in history?

PasteBoard simulates **⌘V** in your previous application after dismissing the panel. A few things can prevent this:

- **Accessibility permission not granted** — Open **System Settings → Privacy & Security → Accessibility** and ensure PasteBoard is listed and enabled.
- **The target app doesn't accept ⌘V** — Some apps use their own paste shortcut. Copy the item with **⌘C** from PasteBoard and paste manually.
- **The panel took focus back** — If you click inside another window before the 0.15 s delay expires, the paste may go to the wrong app. Use keyboard navigation instead.

### When assigning a hotkey to open PasteBoard, it says the hotkey is already used.

**⌘⇧V** is PasteBoard's built-in shortcut, registered via the Carbon API which operates at the system level. If another app has claimed the same combination, the second registration silently loses. To resolve:

1. Find the conflicting app in **System Settings → Keyboard → Keyboard Shortcuts**
2. Reassign or disable its shortcut
3. Restart PasteBoard

The shortcut can be changed in `HotkeyManager.swift` by modifying the `kVK_ANSI_V` and modifier key constants.

### How to clear clipboard history?

Click the **⋯** (ellipsis) menu in PasteBoard's search bar and select **Clear History**. You can also clear history from the Settings window. Clearing deletes all stored items and their associated image files from disk immediately.

### How to ignore copies from Universal Clipboard?

PasteBoard does not currently filter Universal Clipboard items differently from local ones. Items copied on another Apple device and received via Universal Clipboard are stored normally. To prevent this, disable **System Settings → General → AirDrop & Handoff → Universal Clipboard** on your Mac, or toggle monitoring off before using Universal Clipboard.

### My keyboard shortcut stopped working in password fields. How do I fix this?

macOS automatically enables **Secure Input Mode** when a password field is focused. This blocks all third-party keyboard event listeners, including PasteBoard's global hotkey. This is intentional system behavior and cannot be bypassed — it protects your passwords.

**Workaround:** Open PasteBoard from the menu-bar icon while the password field is focused, then click the item you want to paste.

---

## Translations

PasteBoard's UI is currently English-only. Contributions for additional languages are welcome — the strings are in `ContentView.swift`, `ItemRowView.swift`, and `SettingsView.swift`.

To add a translation:
1. Fork the repository
2. Add a `Localizable.strings` file for your language
3. Replace hardcoded strings with `NSLocalizedString` calls
4. Open a pull request

---

## Motivation

macOS has no built-in clipboard history. Third-party options are either bloated with features I don't use, require a subscription, or use Electron. PasteBoard is a minimal, native, open-source alternative: one window, one shortcut, fast search, instant paste.

---

## License

PasteBoard is released under the [MIT License](LICENSE).
