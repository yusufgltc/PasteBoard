import Foundation
import AppKit
import Combine

/// Persistent, observable store for the clipboard history.
///
/// All persistence is delegated to a ``ClipboardRepository`` (injected via init)
/// so the store contains only coordination logic — no FileManager / JSON code.
/// Retention-purge behaviour reacts to ``SettingsProviding/retentionOptionPublisher``
/// so the correct window is always used without polling.
final class ClipboardStore: ObservableObject {

    /// The ordered history list, newest first.
    @Published private(set) var items: [ClipboardItem] = []

    private let maxItems = 50
    private var retentionInterval: TimeInterval { settings.retentionOption.duration }
    private let repository: any ClipboardRepository
    private let settings:   any SettingsProviding
    private var settingsCancellable: AnyCancellable?

    /// - Parameters:
    ///   - repository: Handles all disk I/O for items and images.
    ///   - settings:   Source of truth for retention and monitoring preferences.
    init(repository: any ClipboardRepository, settings: any SettingsProviding) {
        self.repository = repository
        self.settings   = settings
        items = repository.loadItems()
        purgeExpired()

        settingsCancellable = settings.retentionOptionPublisher
            .dropFirst()
            .sink { [weak self] _ in self?.purgeExpired() }
    }

    // MARK: - Mutations

    /// Inserts a new item at the top of the list, deduplicating by content.
    ///
    /// If an identical item already exists it is removed first so the list never
    /// shows duplicates. Overflow beyond `maxItems` drops the oldest entry and
    /// deletes its associated image file.
    func add(_ item: ClipboardItem) {
        if let existing = items.first(where: { isDuplicate($0, item) }) {
            items.removeAll { $0.id == existing.id }
        }
        items.insert(item, at: 0)
        if items.count > maxItems {
            let removed = items.removeLast()
            deleteImageFile(removed)
        }
        repository.saveItems(items)
    }

    /// Moves an existing item to the top and refreshes its timestamp.
    func promote(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var promoted = items.remove(at: index)
        promoted.timestamp = Date()
        items.insert(promoted, at: 0)
        repository.saveItems(items)
    }

    /// Removes a single item and its associated image file.
    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        deleteImageFile(item)
        repository.saveItems(items)
    }

    /// Removes all items and deletes every stored image file.
    func clearAll() {
        items.forEach { deleteImageFile($0) }
        items.removeAll()
        repository.saveItems(items)
    }

    // MARK: - Image helpers

    /// Loads the PNG image for an image-type clipboard item.
    func image(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        return repository.loadImage(fileName: fileName)
    }

    /// Converts an `NSImage` to PNG, persists it, and returns the generated file name.
    func saveImage(_ image: NSImage) -> String {
        repository.saveImage(image)
    }

    // MARK: - Private

    private func isDuplicate(_ existing: ClipboardItem, _ incoming: ClipboardItem) -> Bool {
        guard existing.type == incoming.type else { return false }
        switch existing.type {
        case .text:  return existing.text      == incoming.text
        case .url:   return existing.url       == incoming.url
        case .file:  return existing.filePaths == incoming.filePaths
        case .image: return false
        }
    }

    private func deleteImageFile(_ item: ClipboardItem) {
        guard let fileName = item.imageFileName else { return }
        repository.deleteImage(fileName: fileName)
    }

    private func purgeExpired() {
        let cutoff  = Date().addingTimeInterval(-retentionInterval)
        let expired = items.filter { $0.timestamp < cutoff }
        expired.forEach { deleteImageFile($0) }
        items.removeAll { $0.timestamp < cutoff }
        if !expired.isEmpty { repository.saveItems(items) }
    }
}
