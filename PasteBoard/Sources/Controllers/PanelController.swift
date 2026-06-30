import AppKit
import SwiftUI

// MARK: - Private panel & hosting view

/// `NSPanel` subclass that allows the panel to become the key window.
/// Without this override a borderless panel ignores keyboard input.
private final class SpotlightPanel: NSPanel {
    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }
}

/// `NSHostingView` subclass that accepts the first mouse click without requiring
/// a prior activation click. Without this, the very first click after the panel
/// appears behaves like clicking on a background window and is silently discarded.
private final class FirstMouseHostingView: NSHostingView<ContentView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - PanelController

/// Manages the lifecycle of the floating clipboard-history panel.
///
/// Responsibilities:
/// - Building and positioning the borderless ``SpotlightPanel``
/// - Animating show (spring scale-up + fade-in) and hide (ease-in scale-down + fade-out)
/// - Handling keyboard events while the panel is key
/// - Executing the paste flow: write to pasteboard → skip monitor → hide → simulate ⌘V
/// - Guarding against showing the panel when monitoring is disabled
///
/// The controller is the sole owner of ``ContentViewModel``, which it shares with
/// ``ContentView`` via the initialiser.
final class PanelController: NSObject {
    private var panel: SpotlightPanel?
    private var keyMonitor: Any?
    /// Prevents ``windowDidResignKey(_:)`` from triggering the dismiss animation
    /// when `hide()` itself calls `orderOut` (which fires the delegate synchronously).
    private var isHidingProgrammatically = false
    /// The frontmost app at the moment `show()` was called, restored after the panel hides.
    private var previousApp: NSRunningApplication?
    /// Weak reference — the monitor outlives this controller and is owned by `AppDelegate`.
    private weak var monitor: PasteboardMonitor?

    /// The view-model shared with ``ContentView``. `AppDelegate` wires callbacks on this.
    let viewModel: ContentViewModel
    private let settings: any SettingsProviding

    /// - Parameters:
    ///   - store:    The clipboard history store.
    ///   - monitor:  Used to suppress duplicate entries after a paste.
    ///   - settings: Consulted before showing or toggling the panel.
    init(store: ClipboardStore, monitor: PasteboardMonitor, settings: any SettingsProviding) {
        self.monitor  = monitor
        self.settings = settings
        viewModel = ContentViewModel(store: store)
        super.init()
        viewModel.onPaste = { [weak self] item in self?.paste(item) }
        viewModel.onClose = { [weak self] in self?.hide() }
    }

    // MARK: - Public API

    /// Shows or hides the panel depending on its current visibility.
    /// No-ops silently when monitoring is disabled.
    func toggle() {
        guard settings.isMonitoringEnabled else { return }
        panel?.isVisible == true ? hide() : show()
    }

    /// Brings the panel on screen with a Spotlight-style spring animation.
    ///
    /// Clears the search field and resets selection on every invocation so the
    /// panel always opens in a clean state. No-ops when monitoring is disabled.
    func show() {
        guard settings.isMonitoringEnabled else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        if panel == nil { buildPanel() }

        viewModel.searchText       = ""
        viewModel.isItemTitleMode  = false
        viewModel.selectedID       = nil
        viewModel.panelScale       = 0.96
        viewModel.panelOpacity     = 0.0

        positionPanel()
        panel?.makeKeyAndOrderFront(nil)

        if #available(macOS 14.0, *) { NSApp.activate() }
        else                          { NSApp.activate(ignoringOtherApps: true) }

        installMonitors()

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                self.viewModel.panelScale   = 1.0
                self.viewModel.panelOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.viewModel.shouldFocusSearch = true
        }
    }

    /// Removes the panel from the screen and restores focus to the previous app.
    func hide() {
        guard panel?.isVisible == true else { return }
        isHidingProgrammatically = true
        removeMonitors()
        panel?.orderOut(nil)
        reactivatePrevious()
        isHidingProgrammatically = false
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let size = NSSize(width: 680, height: 500)
        let rect = NSRect(origin: .zero, size: size)

        let builtPanel = SpotlightPanel(
            contentRect: rect,
            styleMask:   [.borderless, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        builtPanel.isMovableByWindowBackground = false
        builtPanel.isReleasedWhenClosed        = false
        builtPanel.level                       = .floating
        builtPanel.collectionBehavior          = [.canJoinAllSpaces, .transient, .ignoresCycle]
        builtPanel.isOpaque                    = false
        builtPanel.backgroundColor             = .clear
        builtPanel.hasShadow                   = true
        builtPanel.delegate                    = self

        let hosting = FirstMouseHostingView(rootView: ContentView(viewModel: viewModel))
        hosting.frame            = rect
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) { hosting.sizingOptions = [] }

        // A backing layer with matching corner radius lets the window compositor
        // render the drop-shadow following the rounded shape rather than a rectangle.
        hosting.wantsLayer             = true
        hosting.layer?.cornerRadius    = 18
        hosting.layer?.cornerCurve     = .continuous
        hosting.layer?.masksToBounds   = true

        builtPanel.contentView = hosting

        panel = builtPanel
    }

    /// Centers the panel vertically with a slight upward offset so it sits in
    /// the visual "golden zone" of the screen, similar to Spotlight.
    private func positionPanel() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let originX = (screen.frame.width  - panel.frame.width)  / 2 + screen.frame.minX
        let originY = (screen.frame.height - panel.frame.height) / 2 + screen.frame.minY + 60
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    // MARK: - Event monitors

    /// Installs a local `keyDown` monitor for the duration the panel is visible.
    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }
    }

    private func removeMonitors() {
        if let existingMonitor = keyMonitor { NSEvent.removeMonitor(existingMonitor); keyMonitor = nil }
    }

    // MARK: - Keyboard handling

    /// Routes key events to the appropriate action while the panel is key.
    ///
    /// Returns `nil` to consume the event (prevents it from reaching the system),
    /// or the original `event` to let it propagate normally.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags
        switch event.keyCode {
        case 53:                                                           // Escape
            hide(); return nil
        case 36, 76:                                                       // Return / numpad Enter
            viewModel.pasteSelected(); return nil
        case 125:                                                          // ↓
            viewModel.selectNext(); return nil
        case 126:                                                          // ↑
            viewModel.selectPrevious(); return nil
        case 48:                                                           // Tab
            if viewModel.isItemTitleMode {
                // Tab back to search bar; selected row keeps its gray highlight.
                viewModel.isItemTitleMode   = false
                viewModel.shouldFocusSearch = true
            } else {
                // Tab into the list, returning to the last selected item (or first).
                if viewModel.selectedID == nil {
                    viewModel.selectedID = viewModel.filteredItems.first?.id
                }
                viewModel.isItemTitleMode = true
            }
            return nil
        case 8 where flags.contains(.command):                             // ⌘C — copy without pasting
            viewModel.copySelected(); return nil
        case 9 where flags.contains(.command) && flags.contains(.shift):   // ⌘⇧V — dismiss
            hide(); return nil
        default:
            if !flags.contains(.command) { viewModel.isItemTitleMode = false }
            return event
        }
    }

    // MARK: - Paste flow

    /// Writes the item to the pasteboard, tells the monitor to skip the resulting
    /// change, hides the panel, and simulates ⌘V in the previous application.
    ///
    /// The 0.15 s delay before ⌘V gives the previous app time to become active
    /// and process keyboard events again.
    private func paste(_ item: ClipboardItem) {
        viewModel.copyToPasteboard(item)
        monitor?.skipNextChange()
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.simulateCmdV() }
    }

    /// Posts a synthetic ⌘V key-down/up pair via the HID event tap so the target
    /// application receives the paste command even though PasteBoard is not frontmost.
    private func simulateCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func reactivatePrevious() {
        guard let app = previousApp else { return }
        previousApp = nil
        if #available(macOS 14.0, *) { app.activate() }
        else                          { app.activate(options: .activateIgnoringOtherApps) }
    }
}

// MARK: - NSWindowDelegate

extension PanelController: NSWindowDelegate {
    /// Fires when the panel loses key status (click outside, app switch, etc.).
    ///
    /// Triggers the Spotlight-style dismiss animation (scale-down + fade-out)
    /// followed by `hide()`. The `isHidingProgrammatically` flag prevents
    /// re-entrant dismiss when our own `orderOut` triggers this delegate.
    func windowDidResignKey(_ notification: Notification) {
        guard !isHidingProgrammatically, panel?.isVisible == true else { return }

        withAnimation(.easeIn(duration: 0.14)) {
            viewModel.panelScale   = 0.95
            viewModel.panelOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.hide()
        }
    }
}
