import AppKit
import Combine
@testable import PasteBoard

// MARK: - FakeClipboardRepository

final class FakeClipboardRepository: ClipboardRepository {
    private(set) var savedItems: [ClipboardItem] = []
    var savedImages: [String: NSImage] = [:]
    private(set) var deletedFileNames: [String] = []

    func loadItems() -> [ClipboardItem] { savedItems }
    func saveItems(_ items: [ClipboardItem]) { savedItems = items }

    func saveImage(_ image: NSImage) -> String {
        let fn = "fake-\(UUID().uuidString).png"
        savedImages[fn] = image
        return fn
    }

    func loadImage(fileName: String) -> NSImage? { savedImages[fileName] }

    func deleteImage(fileName: String) {
        savedImages.removeValue(forKey: fileName)
        deletedFileNames.append(fileName)
    }
}

// MARK: - FakeSettings

final class FakeSettings: SettingsProviding {
    var isMonitoringEnabled: Bool = true
    var retentionOption: RetentionOption = .eightHours

    private let retentionSubject: CurrentValueSubject<RetentionOption, Never>

    init(retention: RetentionOption = .eightHours, monitoring: Bool = true) {
        self.retentionOption        = retention
        self.isMonitoringEnabled    = monitoring
        self.retentionSubject       = CurrentValueSubject(retention)
    }

    var retentionOptionPublisher: AnyPublisher<RetentionOption, Never> {
        retentionSubject.eraseToAnyPublisher()
    }

    func changeRetention(to option: RetentionOption) {
        retentionOption = option
        retentionSubject.send(option)
    }
}

// MARK: - Helpers

extension ClipboardItem {
    static func text(_ value: String, daysAgo: Double = 0) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), type: .text,
            timestamp: Date().addingTimeInterval(-daysAgo * 86400),
            text: value
        )
    }

    static func url(_ value: String, daysAgo: Double = 0) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), type: .url,
            timestamp: Date().addingTimeInterval(-daysAgo * 86400),
            url: value
        )
    }

    static func file(_ paths: [String], daysAgo: Double = 0) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), type: .file,
            timestamp: Date().addingTimeInterval(-daysAgo * 86400),
            filePaths: paths
        )
    }

    static func image(fileName: String = "img.png", daysAgo: Double = 0) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), type: .image,
            timestamp: Date().addingTimeInterval(-daysAgo * 86400),
            imageFileName: fileName
        )
    }
}
