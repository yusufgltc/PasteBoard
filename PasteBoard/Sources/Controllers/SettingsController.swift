import AppKit
import SwiftUI

/// Manages the floating Settings window that hosts ``SettingsView``.
///
/// The window is created lazily on first `show()` call and kept alive
/// (`isReleasedWhenClosed = false`) so settings are not lost if the user
/// closes and reopens the window without restarting the app.
final class SettingsController {
    private var window: NSWindow?
    /// Weak reference — ``ClipboardStore`` outlives this controller and is
    /// owned by ``AppDelegate``.
    private weak var store: ClipboardStore?

    /// - Parameter store: Passed to ``SettingsView`` so the "Clear History" button
    ///   can call ``ClipboardStore/clearAll()``.
    init(store: ClipboardStore) {
        self.store = store
    }

    /// Brings the Settings window to the front, building it first if needed.
    func show() {
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() }
        else                          { NSApp.activate(ignoringOtherApps: true) }
    }

    // MARK: - Private

    private func buildWindow() {
        let content = SettingsView(settings: AppSettings.shared) { [weak self] in
            self?.store?.clearAll()
        }
        let controller = NSHostingController(rootView: content)
        controller.view.setFrameSize(controller.sizeThatFits(in: NSSize(width: 380, height: 800)))

        let win = NSPanel(
            contentRect: NSRect(origin: .zero, size: controller.view.frame.size),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        win.title                 = "PasteBoard Settings"
        win.isReleasedWhenClosed  = false
        win.level                 = .floating
        win.contentViewController = controller
        win.center()

        window = win
    }
}
