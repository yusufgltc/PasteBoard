import AppKit

/// Polls `NSPasteboard.general` every 0.5 s and records new clipboard content
/// into ``ClipboardStore``.
///
/// Polling is necessary because macOS does not provide a push notification API
/// for pasteboard changes. `changeCount` increments on every write, so comparing
/// it to the last-seen value is an O(1) no-op when nothing changed.
final class PasteboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let store:     ClipboardStore
    private let settings:  any SettingsProviding
    private let pasteboard = NSPasteboard.general

    /// - Parameters:
    ///   - store:    Receives newly detected clipboard items.
    ///   - settings: Consulted on every tick to respect the monitoring toggle.
    init(store: ClipboardStore, settings: any SettingsProviding) {
        self.store    = store
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Starts the 0.5 s polling timer on the main run loop.
    func start() {
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Stops the polling timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Advances `lastChangeCount` without adding an item.
    ///
    /// Call this immediately after PasteBoard itself writes to the pasteboard
    /// so the next poll does not record the item as a new copy.
    func skipNextChange() {
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Private

    private func check() {
        guard settings.isMonitoringEnabled else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        let sourceID   = frontmost?.bundleIdentifier
        let sourceName = frontmost?.localizedName

        if let item = extract(sourceID: sourceID, sourceName: sourceName) {
            store.add(item)
        }
    }

    /// Inspects the current pasteboard and returns a ``ClipboardItem``, or `nil`.
    ///
    /// Priority order: file paths → images → URLs → plain text.
    private func extract(sourceID: String?, sourceName: String?) -> ClipboardItem? {
        let types = pasteboard.types ?? []

        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String], !paths.isEmpty {
            return ClipboardItem(id: UUID(), type: .file, timestamp: Date(),
                                 filePaths: paths, sourceAppBundleID: sourceID, sourceAppName: sourceName)
        }
        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return ClipboardItem(id: UUID(), type: .file, timestamp: Date(),
                                 filePaths: urls.map(\.path), sourceAppBundleID: sourceID, sourceAppName: sourceName)
        }

        if types.contains(.tiff) || types.contains(.png),
           let image = NSImage(pasteboard: pasteboard) {
            let fileName = store.saveImage(image)
            return ClipboardItem(id: UUID(), type: .image, timestamp: Date(),
                                 imageFileName: fileName, sourceAppBundleID: sourceID, sourceAppName: sourceName)
        }

        if let str = pasteboard.string(forType: .string), !str.isEmpty {
            if let url    = URL(string: str),
               let scheme = url.scheme,
               ["http", "https", "ftp"].contains(scheme),
               url.host != nil {
                return ClipboardItem(id: UUID(), type: .url, timestamp: Date(),
                                     url: str, sourceAppBundleID: sourceID, sourceAppName: sourceName)
            }
            return ClipboardItem(id: UUID(), type: .text, timestamp: Date(),
                                 text: str, sourceAppBundleID: sourceID, sourceAppName: sourceName)
        }

        return nil
    }
}
