import Cocoa
import Combine

/// Application delegate — the composition root.
///
/// Creates and wires all major components in `applicationDidFinishLaunching`:
/// ``ClipboardStore`` → ``PasteboardMonitor`` → ``PanelController`` →
/// ``SettingsController`` → ``HotkeyManager``. Owns the status-bar item and
/// observes ``AppSettings/isMonitoringEnabled`` to keep the "Show PasteBoard"
/// menu item in sync.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store:    ClipboardStore!
    private var monitor:  PasteboardMonitor!
    private var hotkey:   HotkeyManager!
    private var panel:    PanelController!
    private var settings: SettingsController!
    private var statusItem: NSStatusItem!

    /// Retained reference so we can enable/disable it reactively.
    private var showPanelItem: NSMenuItem!
    private var monitoringObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let repository   = FileSystemClipboardRepository()
        let appSettings  = AppSettings.shared
        store    = ClipboardStore(repository: repository, settings: appSettings)
        monitor  = PasteboardMonitor(store: store, settings: appSettings)
        panel    = PanelController(store: store, monitor: monitor, settings: appSettings)
        settings = SettingsController(store: store)
        monitor.start()

        panel.viewModel.onShowSettings = { [weak self] in
            self?.panel.hide()
            self?.settings.show()
        }

        hotkey = HotkeyManager()
        hotkey.onHotkey = { [weak self] in
            guard let self else { return }
            guard AppSettings.shared.isMonitoringEnabled else { return }
            self.panel.toggle()
        }
        hotkey.start()

        setupStatusBar()
        observeMonitoring()
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let button = statusItem.button!
        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .regular)
        button.image = NSImage(systemSymbolName: "doc.on.clipboard.fill",
                               accessibilityDescription: "PasteBoard")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = true

        showPanelItem = NSMenuItem(title: "Show PasteBoard  ⌘⇧V",
                                   action: #selector(showPanel), keyEquivalent: "")

        let menu = NSMenu()
        menu.autoenablesItems = false   // respect isEnabled we set via Combine
        menu.addItem(showPanelItem)
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PasteBoard",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: - Monitoring observer

    /// Subscribes to ``AppSettings/isMonitoringEnabled`` and reacts to changes:
    /// - Grays out / re-enables the "Show PasteBoard" status-bar item.
    /// - Hides the panel immediately if monitoring is turned off while it is visible.
    /// - Clears the clipboard history when monitoring is turned off.
    private func observeMonitoring() {
        monitoringObserver = AppSettings.shared.$isMonitoringEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.showPanelItem.isEnabled = enabled
                if !enabled { self.panel.hide() }
                if !enabled { self.store.clearAll() }
            }
    }

    // MARK: - Actions

    @objc private func showPanel()    { panel.show()    }
    @objc private func showSettings() { settings.show() }
}
