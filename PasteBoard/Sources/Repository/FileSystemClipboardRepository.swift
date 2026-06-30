import AppKit
import Foundation

/// Persists clipboard items as JSON and images as PNG files inside
/// `~/Library/Application Support/PasteBoard/`.
final class FileSystemClipboardRepository: ClipboardRepository {

    private let historyURL: URL
    private let imagesURL:  URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PasteBoard")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        historyURL = support.appendingPathComponent("history.json")
        imagesURL  = support.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
    }

    func loadItems() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ClipboardItem].self, from: data)) ?? []
    }

    func saveItems(_ items: [ClipboardItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    func saveImage(_ image: NSImage) -> String {
        let fileName = UUID().uuidString + ".png"
        if let tiffData = image.tiffRepresentation,
           let bitmapRepresentation = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRepresentation.representation(using: .png, properties: [:]) {
            try? pngData.write(to: imagesURL.appendingPathComponent(fileName))
        }
        return fileName
    }

    func loadImage(fileName: String) -> NSImage? {
        NSImage(contentsOf: imagesURL.appendingPathComponent(fileName))
    }

    func deleteImage(fileName: String) {
        try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(fileName))
    }
}
