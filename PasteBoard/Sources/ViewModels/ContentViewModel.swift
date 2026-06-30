import Foundation
import AppKit

/// Observable view-model that drives ``ContentView``.
///
/// ``PanelController`` owns this object and wires the action callbacks
/// (`onPaste`, `onClose`, `onShowSettings`) before handing the view-model to
/// ``ContentView``. All state mutations happen on the main actor because
/// `@Published` properties are observed by SwiftUI.
final class ContentViewModel: ObservableObject {

    // MARK: - Published state

    /// Current text in the search field. Drives ``filteredItems``.
    @Published var searchText = ""

    /// The `id` of the currently highlighted row, or `nil` when nothing is selected.
    @Published var selectedID: UUID?

    /// When `true` the search bar shows the selected item's title chip instead of
    /// the plain text field (Spotlight-style "you're about to paste X" state).
    @Published var isItemTitleMode = false

    /// Setting this to `true` programmatically moves focus to the search `TextField`.
    /// ``ContentView`` resets it to `false` immediately after consuming the signal.
    @Published var shouldFocusSearch = false

    /// Drive the Spotlight-style enter/exit animations.
    /// Set by ``PanelController`` via `withAnimation {}` blocks.
    @Published var panelScale:   CGFloat = 1.0
    @Published var panelOpacity: Double  = 1.0

    // MARK: - Dependencies & callbacks

    let store: ClipboardStore

    /// Called with the item the user wants to paste (double-click or Return).
    var onPaste: ((ClipboardItem) -> Void)?

    /// Called when the user asks to close the panel (Escape key).
    var onClose: (() -> Void)?

    /// Called when the user opens Settings from the panel menu.
    var onShowSettings: (() -> Void)?

    private static var appIconCache: [String: NSImage] = [:]

    /// - Parameter store: The clipboard history store.
    init(store: ClipboardStore) {
        self.store = store
    }

    // MARK: - Filtering

    /// Items that match the current ``searchText``.
    /// Returns the full list when the search field is empty.
    var filteredItems: [ClipboardItem] {
        guard !searchText.isEmpty else { return store.items }
        let query = searchText.lowercased()
        return store.items.filter { item in
            switch item.type {
            case .text:  return item.text?.lowercased().contains(query) ?? false
            case .url:   return item.url?.lowercased().contains(query) ?? false
            case .file:  return item.filePaths?.joined().lowercased().contains(query) ?? false
            case .image: return "image".contains(query)
            }
        }
    }

    /// The item currently identified by ``selectedID``, falling back to the
    /// first item in ``filteredItems`` when nothing is explicitly selected.
    var selectedItem: ClipboardItem? {
        let items = filteredItems
        guard !items.isEmpty else { return nil }
        if let id = selectedID, let item = items.first(where: { $0.id == id }) { return item }
        return items.first
    }

    // MARK: - Navigation

    /// Moves the selection down one row and enters item-title mode.
    func selectNext() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        if let id = selectedID, let index = items.firstIndex(where: { $0.id == id }) {
            selectedID = items[min(index + 1, items.count - 1)].id
        } else {
            selectedID = items.first?.id
        }
        isItemTitleMode = true
    }

    /// Moves the selection up one row and enters item-title mode.
    func selectPrevious() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        if let id = selectedID, let index = items.firstIndex(where: { $0.id == id }) {
            selectedID = items[max(index - 1, 0)].id
        } else {
            selectedID = items.first?.id
        }
        isItemTitleMode = true
    }

    // MARK: - Actions

    /// Triggers the paste flow for the currently selected (or first) item.
    func pasteSelected() {
        if let item = selectedItem { onPaste?(item) }
    }

    /// Copies the selected item to the pasteboard without triggering the full paste flow.
    func copySelected() {
        if let item = selectedItem { copyToPasteboard(item) }
    }

    /// Writes `item`'s content to `NSPasteboard.general` and promotes it to the
    /// top of the store so the list reflects the new "last copied" order in real time.
    /// - Parameter item: The item to write.
    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.type {
        case .text:
            if let text = item.text { pasteboard.setString(text, forType: .string) }
        case .url:
            if let urlString = item.url {
                pasteboard.setString(urlString, forType: .string)
                if let parsedURL = URL(string: urlString) { pasteboard.writeObjects([parsedURL as NSURL]) }
            }
        case .image:
            if let image = store.image(for: item) { pasteboard.writeObjects([image]) }
        case .file:
            if let paths = item.filePaths {
                pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
            }
        }
        store.promote(item)
    }

    /// Returns the app icon for the given bundle identifier, loading and caching
    /// it on first access. Returns `nil` if the app is not installed.
    /// - Parameter bundleID: The bundle identifier to look up.
    func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = Self.appIconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.appIconCache[bundleID] = icon
        return icon
    }
}
