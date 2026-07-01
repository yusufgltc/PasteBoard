# PasteBoard — Complete Application Spec
> **Purpose of this document:** A single source of truth for building PasteBoard from scratch.
> Hand this to an AI coding agent and the full app — including distribution — should be
> producible in one or two passes with minimal back-and-forth.

---

## 1. Product Overview

**What:** A macOS menu-bar clipboard history manager.

**Why:** macOS Tahoe (26+) ships a native clipboard history feature, but it requires hardware
Apple dropped from Tahoe support. PasteBoard fills that gap for those Macs.

**Target users:** Mac users on macOS 13 Ventura or 14 Sonoma who cannot upgrade to Tahoe.

**Distribution channel:** Homebrew custom tap (`yusufgltc/pasteboard`). No App Store.

**Repositories:**
- App source + local cask copy: `github.com/yusufgltc/PasteBoard`
- Homebrew tap (what `brew` actually reads): `github.com/yusufgltc/homebrew-pasteboard`
- Both must be kept in sync on every cask change.

---

## 2. Platform & Runtime Constraints

| Constraint | Value | Why |
|---|---|---|
| Minimum macOS | 13.0 Ventura | Target audience can't run Tahoe |
| Swift | 5.9+ | Observation/SwiftUI compat |
| Xcode | 15+ | Required for macOS 13 SDK |
| App type | `LSUIElement = YES` (background agent) | No Dock icon; lives only in menu bar |
| Bundle ID | `com.pasteboard.app` | Used in Homebrew cask and UserDefaults keys |
| Entitlements | None beyond defaults | No sandbox; avoids App Store |
| Code signing | Ad-hoc (`CODE_SIGN_IDENTITY = "-"`) for now | Notarization is a post-v1 concern |

**LSUIElement implications:**
- `NSApp.activate()` is unreliable for titled windows from a Carbon hotkey callback context.
- Borderless `NSPanel` with `canBecomeKey = true` override works reliably.
- Titled `NSPanel` (Settings) can be shown via `makeKeyAndOrderFront` + `orderFrontRegardless`
  from menu-bar menu actions; it does NOT work reliably from a global hotkey handler.

---

## 3. Architecture

### 3.1 Layer Map

```
AppDelegate  (composition root — wires everything, owns the status bar item)
│
├── ClipboardStore          (ObservableObject — owns ordered history [ClipboardItem])
│     └── ClipboardRepository  (protocol — abstracts disk I/O)
│           └── FileSystemClipboardRepository  (JSON + PNG files in Application Support)
│
├── PasteboardMonitor       (polls NSPasteboard every 0.5 s, feeds ClipboardStore)
│
├── PanelController         (manages the floating history panel: show/hide/animate/paste)
│     └── ContentViewModel  (ObservableObject — drives ContentView)
│           └── ContentView + ItemRowView  (SwiftUI inside NSHostingView)
│
├── SettingsController      (manages the Settings NSPanel window)
│     └── SettingsView      (SwiftUI inside NSHostingController)
│
└── HotkeyManager           (Carbon RegisterEventHotKey for ⌘⇧V)
```

### 3.2 Design Patterns

- **Protocol-based injection:** `ClipboardStore` and `PasteboardMonitor` accept
  `any SettingsProviding` and `any ClipboardRepository` — not concrete types.
  `SettingsProviding` is a read-only protocol on `AppSettings`; it exposes only
  `isMonitoringEnabled`, `retentionOption`, and `retentionOptionPublisher`.

- **Single shared settings singleton:** `AppSettings.shared` is the only instance.
  It is `ObservableObject`; SwiftUI views observe it directly. Non-UI code uses
  `SettingsProviding` to keep the dependency surface minimal.

- **Combine for reactive propagation:** `AppSettings.$isMonitoringEnabled` and
  `$retentionOption` are `@Published`. `ClipboardStore` subscribes to
  `retentionOptionPublisher` to re-purge on change. `AppDelegate` subscribes to
  `isMonitoringEnabled` to gray out / enable the menu item and clear history.

- **No timer on the main thread for heavy work:** `PasteboardMonitor` uses a `Timer`
  on the main `RunLoop` but each tick is O(1) (just compare `changeCount`). Heavy
  image encoding happens only when content actually changed.

- **SHA256-based image filenames:** Images saved to disk use the SHA256 of their PNG
  data as the filename. This gives free deduplication: two identical screenshots =
  one file. Checking `fileExists` before writing avoids redundant disk writes.

### 3.3 UserDefaults Keys (all prefixed `pasteboard`)

| Key | Type | Default | Purpose |
|---|---|---|---|
| `pasteboardMonitoringEnabled` | Bool | false | Master monitoring toggle |
| `pasteboardRetentionOption` | Int (raw) | 1 (8 hours) | Retention window |
| `pasteboardHasLaunchedBefore` | Bool | false | Written by Homebrew postflight; not read by app |

The app reads `pasteboardMonitoringEnabled` and `pasteboardRetentionOption` in
`AppSettings.init()`. It never reads `pasteboardHasLaunchedBefore` at runtime —
that key is only written by the Homebrew cask postflight to prevent any
"first launch" auto-action logic that would race with `defaults write` timing.

---

## 4. Feature Specifications

### 4.1 Clipboard Monitoring

**Mechanism:** Poll `NSPasteboard.general.changeCount` every 0.5 s. When it changes,
read the pasteboard and create a `ClipboardItem`. Skip the change if the frontmost
app is PasteBoard itself (prevents loop when we write to the pasteboard during paste).

**Content priority order** (first match wins):
1. `NSFilenamesPboardType` or `.fileURL` → `.file` item with array of paths
2. `.tiff` or `.png` → `.image` item; encode to PNG, save to disk, store filename
3. `.string` that parses as a valid http/https/ftp URL with a non-nil host → `.url`
4. `.string` (non-empty) → `.text`
5. Nothing matched → ignore

**Source app:** Capture `NSWorkspace.shared.frontmostApplication` at the moment the
change is detected. Store `bundleIdentifier` and `localizedName` on the item.

**Max history:** 50 items. When adding item 51, drop the oldest and delete its image file.

**Deduplication:** Before inserting, check for an existing item of the same type with
identical content (text == text, url == url, filePaths == filePaths,
imageFileName == imageFileName). If found: remove it first (so the new copy floats
to top), skip image file deletion only when both items share the same filename
(same content = same SHA256 = same file still needed).

**Retention purge:** On startup and whenever the retention setting changes, remove all
items older than the retention window. Delete their image files. Persist the updated list.

**Guard:** If `isMonitoringEnabled == false`, skip the check entirely. Do not record.

### 4.2 History Panel

**Trigger:** ⌘⇧V global hotkey (registered via Carbon `RegisterEventHotKey`).
If monitoring is disabled, the hotkey does nothing (silent no-op). The panel toggles
(show if hidden, hide if visible).

**Window type:** Borderless `NSPanel` subclass (`SpotlightPanel`) with:
- `canBecomeKey = true` (required for keyboard input in a borderless window)
- `styleMask: [.borderless, .fullSizeContentView]`
- `level = .floating`
- `collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]`
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`
- `NSHostingView` subclass (`FirstMouseHostingView`) with `acceptsFirstMouse → true`
  (so the first click after appearance is not discarded)
- Hosting view gets a `CALayer` with `cornerRadius = 18`, `cornerCurve = .continuous`,
  `masksToBounds = true` so the shadow follows the rounded shape

**Size:** 680 × 500 pt. Centered on main screen with +60 pt vertical offset (golden zone).

**Show animation:** `panelScale` 0.96 → 1.0, `panelOpacity` 0.0 → 1.0 via
`.spring(response: 0.22, dampingFraction: 0.88)`. Triggered with `DispatchQueue.main.async`
after `makeKeyAndOrderFront` so the initial state is rendered before animating.
Search field focus is set 0.05 s after show via `shouldFocusSearch` signal.

**Hide animation:** On `windowDidResignKey` (click outside): `panelScale` → 0.95,
`panelOpacity` → 0.0 via `.easeIn(duration: 0.14)`, then `orderOut` after 0.16 s.
Guard with `isHidingProgrammatically` flag to prevent re-entrant dismiss.

**Previous app restoration:** Capture `NSWorkspace.shared.frontmostApplication` at show time.
On hide, call `app.activate()` / `app.activate(options: .activateIgnoringOtherApps)`.

**Keyboard navigation (local monitor while panel is key):**

| Key | Action |
|---|---|
| Escape | Hide panel |
| Return / numpad Enter | Paste selected item |
| ↓ | Select next item, enter title-chip mode |
| ↑ | Select previous item, enter title-chip mode |
| Tab | Toggle between search bar and list navigation |
| ⌘C | Copy selected item without pasting |
| ⌘⇧V | Dismiss panel |
| Any non-⌘ key | Exit title-chip mode, propagate to search field |

**Title-chip mode:** When navigating with arrow keys or Tab, the search bar shows a chip
(`item.displayTitle – Paste`) with accent-color fill instead of the text field.
Clicking the chip or typing any character exits chip mode.

**Empty state:** When `filteredItems` is empty:
- No search text: clipboard icon + "Nothing copied yet"
- Search active: magnifying glass icon + "No results for \"query\""

### 4.3 Paste Flow

1. Write item content to `NSPasteboard.general` (clear first).
2. Call `monitor.skipNextChange()` to advance `lastChangeCount` so the monitor
   doesn't re-record what we just wrote.
3. `hide()` the panel.
4. After 0.15 s delay, simulate ⌘V via `CGEvent(keyboardEventSource:, virtualKey: 0x09, keyDown:)`
   posted to `.cghidEventTap` with `.maskCommand` flag.
   The delay gives the previous app time to become active and accept key events.

**Pasteboard write by type:**
- `.text` → `setString(text, forType: .string)`
- `.url` → `setString(urlString, forType: .string)` + `writeObjects([parsedURL as NSURL])`
- `.image` → load PNG from disk, `writeObjects([image])`
- `.file` → `writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })`

After writing, call `store.promote(item)` to update its timestamp and move it to top.

### 4.4 Item Row View

Each row: 50 pt icon stack + text stack + copy button, 12 pt horizontal padding, 9 pt vertical.

**Icon stack (50 × 50 pt):**
- 44 × 44 pt content icon with `RoundedRectangle(cornerRadius: 9)` clip
  - `.text` → blue gradient + doc.text symbol
  - `.image` → purple gradient + photo symbol
  - `.url` → green gradient + link symbol
  - `.file` → orange gradient + doc symbol
- 18 × 18 pt source app icon badge at bottom-right offset (7, 7), `cornerRadius = 4.5`,
  1.5 pt window-background-color border. Loaded from `NSWorkspace` and cached by bundle ID
  in a process-wide `AppIconCache` enum (not in ViewModel — the view owns this cache).

**Text stack:**
- `item.displayTitle`, size 13, weight .medium, `lineLimit(2)`, `.truncationMode(.tail)`
- `item.typeLabel + " · Copied " + copiedTime(item.timestamp)`, size 11, secondary color, `lineLimit(1)`

**`displayTitle` truncation:** Text items longer than 120 chars are truncated to 117 + "…"
in the model, not the view. This keeps the chip in search-bar title mode concise too.

**Row interaction:** An `NSViewRepresentable` overlay (`RowInteractionNSView`) handles:
- `mouseDown`: single click = select; double click = paste
- `rightMouseDown`: show context menu (Paste / Copy / Delete with SF Symbols)
- `hitTest`: right-click covers full width; left-click passes through to SwiftUI for
  the copy button area (rightmost 56 pt)
- `acceptsFirstMouse → true`

**Row background states:**
- Focused (selected + title-chip mode): `accentColor.opacity(0.15)`
- Selected (not focused): `unemphasizedSelectedContentBackgroundColor`
- Hovered: `primary.opacity(0.06)`
- Default: `.clear`

**Performance:** `ItemRowView` conforms to `Equatable` (excluding closures). Use `.equatable()`
on each row inside `LazyVStack` to skip re-render when item/selection state hasn't changed.

### 4.5 Settings Window

**Window type:** `NSPanel` with `styleMask: [.titled, .closable]`, `level = .floating`,
`isReleasedWhenClosed = false`. Shown via `makeKeyAndOrderFront` + `orderFrontRegardless`.
Built lazily on first `show()` call. Width 380 pt (height fits content).

**Note on show() in LSUIElement apps:** `NSApp.activate()` (macOS 14+) or
`NSApp.activate(ignoringOtherApps: true)` must be called before `makeKeyAndOrderFront`
for the window to actually come to front. This works reliably when triggered from a
menu-bar menu action. It does NOT work reliably when triggered from a Carbon hotkey
callback — do not attempt to open Settings from the hotkey.

**Settings UI (SwiftUI):**
1. Monitoring toggle (`Toggle`, switch style) — turning off immediately clears history
   and grays out the other sections.
2. Retention picker (radio group): 30 Minutes / 8 Hours / 7 Days.
3. "Clear Clipboard History" destructive button — disabled when monitoring is off.

### 4.6 Menu Bar

**Icon:** `NSImage(systemSymbolName: "doc.on.clipboard.fill")` with
`NSImage.SymbolConfiguration(pointSize: 13.5, weight: .regular)`. Mark as template image.
Use `NSStatusItem.squareLength`.

**Menu items:**
- "Show PasteBoard  ⌘⇧V" — enabled only when monitoring is on (`menu.autoenablesItems = false`)
- "Settings…"
- Separator
- "Quit PasteBoard" (key equivalent: q)

Subscribe to `AppSettings.shared.$isMonitoringEnabled` via Combine to enable/disable
"Show PasteBoard" reactively. Also hide the panel immediately if it is visible when
monitoring is turned off.

### 4.7 Global Hotkey

Use `Carbon.RegisterEventHotKey` with:
- Virtual key: `kVK_ANSI_V` (0x09 for ⌘V; 9 (0x09) for V in RegisterEventHotKey)
- Modifiers: `cmdKey | shiftKey`
- Signature: `OSType(0x50424F41)` ("PBOA"), id: 1
- Target: `GetApplicationEventTarget()`

Install event handler via `InstallEventHandler` on `GetApplicationEventTarget()`.
Dispatch to main queue from inside the handler. The handler holds an unretained
`Unmanaged` pointer to `HotkeyManager`.

**Why Carbon and not NSEvent global monitor?** `NSEvent.addGlobalMonitorForEvents`
silently stops firing on macOS 13+ without Accessibility permission. Carbon hotkeys
require no entitlements.

---

## 5. Data Model

```swift
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType   // text | image | url | file
    var timestamp: Date           // var — updated by promote()
    var text: String?
    var imageFileName: String?    // SHA256.png — relative filename, not full path
    var url: String?
    var filePaths: [String]?
    var sourceAppBundleID: String?
    var sourceAppName: String?
}
```

**Persistence:** `~/Library/Application Support/PasteBoard/history.json` (ISO8601 dates).
Images in `~/Library/Application Support/PasteBoard/images/`.

**Equatable:** By `id` only. This allows `promote()` to mutate `timestamp` without SwiftUI
treating the item as a new object.

---

## 6. Persistence & Installation

### 6.1 File Locations

| Path | Contents | Cleared on uninstall |
|---|---|---|
| `~/Library/Application Support/PasteBoard/history.json` | Serialised `[ClipboardItem]` | Yes |
| `~/Library/Application Support/PasteBoard/images/*.png` | Clipboard image files | Yes |
| `~/Library/Preferences/com.pasteboard.app.plist` | UserDefaults | Yes |
| `~/Library/Saved Application State/com.pasteboard.app.savedState` | Window state | Zap only |

### 6.2 Homebrew Cask Structure

Two repos — changes to the cask must be pushed to **both**:
1. `PasteBoard/Casks/pasteboard.rb` (source of truth, lives with app code)
2. `homebrew-pasteboard/Casks/pasteboard.rb` (what `brew` actually reads)

**Release flow:**
```bash
# 1. Archive
xcodebuild -project PasteBoard.xcodeproj -scheme PasteBoard \
  -configuration Release -archivePath /tmp/PasteBoard.xcarchive archive \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# 2. Zip (must use ditto to preserve macOS metadata and code signature)
ditto -c -k --keepParent \
  /tmp/PasteBoard.xcarchive/Products/Applications/PasteBoard.app \
  /tmp/PasteBoard-X.Y.Z.zip

# 3. SHA256
shasum -a 256 /tmp/PasteBoard-X.Y.Z.zip

# 4. GitHub release
gh release create vX.Y.Z /tmp/PasteBoard-X.Y.Z.zip --title "PasteBoard vX.Y.Z"

# 5. Update sha256 + version in both cask files, push both repos
```

### 6.3 Cask DSL

```ruby
cask "pasteboard" do
  version "X.Y.Z"
  sha256 "<sha256 of zip>"

  url "https://github.com/yusufgltc/PasteBoard/releases/download/v#{version}/PasteBoard-#{version}.zip"
  name "PasteBoard"
  desc "Clipboard history for Macs that can't upgrade to macOS Tahoe"
  homepage "https://github.com/yusufgltc/PasteBoard"

  app "PasteBoard.app"

  caveats <<~'EOS'          # single-quoted to preserve backslashes in ASCII art
    Welcome to
    ...ASCII art...
    ⌘⇧V  open   Tab  navigate   ↵  paste   ⌫  delete
    All data stays on your Mac.
  EOS

  preflight do
    # Delete data from any previous install BEFORE installing new version.
    # This prevents stale history from carrying over across reinstalls.
    system_command "/bin/rm", args: ["-rf", File.expand_path("~/Library/Application Support/PasteBoard")]
    system_command "/bin/rm", args: ["-f",  File.expand_path("~/Library/Preferences/com.pasteboard.app.plist")]
  end

  postflight do
    # Interactive stdin prompt — falls back to "n" in non-TTY contexts (CI, pipe)
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

    # IMPORTANT: write this for BOTH y and n so the app never auto-opens Settings on launch.
    # The app must not have first-launch auto-actions that race with `defaults write` timing.
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
```

**Key rules:**
- `preflight` runs BEFORE the new `.app` is copied. Use it to nuke old data.
- `postflight` runs AFTER the new `.app` is copied. Use it to set defaults and launch.
- `uninstall delete:` paths can require sudo if not owned by current user — this is expected
  brew behaviour; users will be prompted for their password in a real terminal.
- `system_command` in preflight/postflight runs as the current user (not root).
- `defaults write` in postflight sets UserDefaults in the `com.pasteboard.app` domain.
  cfprefsd caches these; the app reads them fresh on launch (not a problem in practice).

---

## 7. App Icon

**Format:** `.icns` file referenced directly in `project.pbxproj` (not an Asset Catalog).
This avoids Xcode processing that can alter the icon.

**Spec:**
- Base artwork: squircle shape (rounded rectangle matching macOS icon language)
- Add 8% transparent padding on all sides before packing into `.icns`.
  This makes the icon appear the correct size in Launchpad (without padding it looks oversized).
- Pack with `iconutil --convert icns` from an `.iconset` folder with all required sizes:
  `16, 32, 128, 256, 512` pt at 1× and 2× (10 PNG files total, named per Apple spec).

**Build script (Python, requires Pillow):**
```python
from PIL import Image
import os, subprocess, shutil

src = Image.open("icon_1024.png").convert("RGBA")
margin = int(src.width * 0.08)
canvas = Image.new("RGBA", (src.width + margin*2, src.height + margin*2), (0,0,0,0))
canvas.paste(src, (margin, margin))
# resize canvas to 1024x1024
canvas = canvas.resize((1024, 1024), Image.LANCZOS)
# then export all sizes into AppIcon.iconset/ and run iconutil
```

---

## 8. What NOT to Do (Anti-Patterns Discovered)

| Anti-pattern | Problem | Correct approach |
|---|---|---|
| Open Settings from a Carbon hotkey callback | `NSApp.activate()` is unreliable from hotkey context in an LSUIElement app; window shows but doesn't receive focus | Only open Settings from a menu-bar action |
| Read `isFirstLaunch` from UserDefaults in-app and auto-open Settings | Races with `defaults write` in postflight; also Gatekeeper delays after `open -a` mean the defaults may not be flushed | Write `pasteboardHasLaunchedBefore=true` in postflight for both Y and N; remove all first-launch app-side logic |
| Use NSEvent global monitor for hotkey | Silently stops firing on macOS 13+ without Accessibility permission | Use Carbon `RegisterEventHotKey` |
| Use Asset Catalog for app icon | Xcode processing alters the icon; padding technique doesn't survive | Reference `.icns` directly in pbxproj |
| Store image dedup logic in ViewModel | Duplicates the concern; ViewModel should not own disk-level caching | Keep `AppIconCache` in the view layer; keep image SHA256 logic in repository |
| History surviving reinstall | Old `history.json` persists across brew reinstalls because uninstall only runs at explicit `brew uninstall` | Add `preflight` to delete Application Support before every install |
| Postflight writing `pasteboardHasLaunchedBefore` only on Y | N path never set the key, so the (now-removed) first-launch logic could fire | Write the key for both Y and N |
| Skipping `$stdin.isatty` check | `$stdin.gets` hangs forever in non-TTY brew contexts (e.g. CI) | Always guard stdin reads with `$stdin.isatty` |

---

## 9. Verification Checklist

### Install
- [ ] `brew tap yusufgltc/pasteboard && brew install --cask pasteboard` completes without error
- [ ] Caveats ASCII art displays, prompt appears
- [ ] Answering Y: defaults `pasteboardMonitoringEnabled=true`; app opens; ⌘⇧V shows empty panel
- [ ] Answering N: defaults `pasteboardMonitoringEnabled=false`; app opens; ⌘⇧V does nothing
- [ ] `brew uninstall --cask pasteboard` quits app, removes plist and Application Support
- [ ] `brew reinstall --cask pasteboard` clears old history; fresh panel after reinstall

### Core Behaviour
- [ ] Copying text in any app → appears at top of history panel
- [ ] Copying a URL → appears as URL type with green icon
- [ ] Copying a file → appears as File type with orange icon
- [ ] Copying an image → appears as Image type with purple icon
- [ ] Copying the same item twice → only one entry (deduplication), moved to top
- [ ] Pasting from panel (Return or double-click) → content pasted in previous app
- [ ] ⌘C in panel → copies item without pasting
- [ ] Right-click → context menu: Paste / Copy / Delete
- [ ] Delete key (via context menu) → item removed from list
- [ ] Search filters history in real time; clearing search restores full list
- [ ] Tab → enters list navigation (title chip); Tab again → back to search
- [ ] Arrow keys navigate list; Return pastes the focused item
- [ ] Panel closes on Escape, click outside, and ⌘⇧V when open
- [ ] Source app badge shows correct icon on each row

### Settings
- [ ] Settings opens from menu bar → "Settings…"
- [ ] Settings opens from panel's ⋯ menu
- [ ] Toggling monitoring off → panel hides immediately, history cleared, "Show PasteBoard" grays out
- [ ] Toggling monitoring on → ⌘⇧V works again
- [ ] Retention change takes effect immediately (items older than new window disappear)
- [ ] "Clear Clipboard History" button clears all items

### Edge Cases
- [ ] 50+ items copied → oldest dropped automatically
- [ ] Long text (>120 chars) → truncated in row with "…"
- [ ] App handles empty clipboard gracefully (no crash)
- [ ] Quitting and relaunching preserves history
- [ ] Menu bar icon is the correct size (not oversized, template image renders in dark/light mode)
- [ ] Launchpad icon is the correct size (not oversized vs system apps)

---

## 10. What This Spec Intentionally Leaves Out (Post-v1)

- **Notarization / Gatekeeper:** Requires an Apple Developer account ($99/year).
  Without it, users see "Apple cannot verify this app" and must manually allow it
  in System Settings → Privacy & Security.
- **Auto-update (Sparkle):** Users who install via brew can `brew upgrade`, but they
  don't know to do so. Sparkle would add an in-app update check via an appcast XML feed.
- **Accessibility permission for paste simulation:** The `CGEvent` paste simulation works
  without Accessibility permission because it posts directly to the HID event tap.
  If Apple restricts this in a future macOS version, Accessibility permission will be needed.
- **iCloud sync:** All data is intentionally local-only.
- **Homebrew core tap submission:** Requires 30+ days of public availability and significant
  stars/forks before the homebrew maintainers will accept it.

---

## 11. Lessons — How to Write AI Specs Effectively

The entire PasteBoard feature set was built iteratively through ~20+ back-and-forth
exchanges. Each exchange fixed something that a proper upfront spec would have prevented.
This section maps each iteration to the spec section that would have avoided it.

| What was discovered iteratively | Spec section that covers it |
|---|---|
| History surviving reinstall/uninstall | §6.3 — `preflight` deletes Application Support |
| Menu bar icon too big | §4.6 — `pointSize: 13.5` in SymbolConfiguration |
| Launchpad icon too big | §7 — 8% transparent padding before iconutil |
| ASCII art misaligned in caveats | §6.3 — single-quoted `<<~'EOS'` heredoc |
| ⌘⇧V can't reliably open Settings in LSUIElement | §2, §8 — LSUIElement constraints documented |
| Auto-open Settings racing with postflight defaults | §3.3, §8 — write key for both Y and N |
| Old history appearing after fresh install | §6.3 — preflight stanza |
| Two repos getting out of sync | §1, §6.2 — both repos documented explicitly |
| `$stdin.gets` hanging in non-TTY | §6.3 — `$stdin.isatty` guard documented |
| Dead code accumulation | §4 — acceptance criteria make unused features obvious upfront |
| xcodebuild path not in PATH | §6.2 — full path documented for non-default Xcode locations |
| Postflight message misleading users | §6.3 — exact message text specified |

**General rules for writing AI-ready specs:**

1. **Specify the runtime environment explicitly.** `LSUIElement = YES` changes how
   window management works. State it upfront with its implications.

2. **Name every file and every default key.** Ambiguity in names leads to the AI
   inventing names that conflict with your cask or other tools.

3. **Specify the distribution channel before writing a line of code.** Homebrew vs
   App Store vs direct download changes entitlements, signing, sandboxing, and
   auto-update strategy.

4. **Write acceptance criteria, not just feature names.** "Clipboard monitoring"
   is ambiguous. "Poll changeCount every 0.5 s; skip if frontmost app is self; priority
   order: file → image → URL → text" is actionable.

5. **Document anti-patterns from similar apps.** The LSUIElement + titled window problem
   is not obvious and causes silent failures. Write it down.

6. **Specify what should NOT be built.** Explicitly listing out-of-scope features prevents
   the AI from adding complexity "helpfully" (e.g., a preview pane that is never wired up).

7. **Include the release pipeline in the spec.** The build → zip → SHA256 → release →
   cask update flow is non-trivial and has ordering dependencies. Spec it fully.
