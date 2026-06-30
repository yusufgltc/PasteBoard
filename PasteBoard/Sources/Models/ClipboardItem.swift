import Foundation

/// The kind of content a clipboard entry holds.
enum ClipboardItemType: String, Codable {
    case text, image, url, file
}

/// A single entry in the clipboard history.
///
/// `timestamp` is `var` so ``ClipboardStore/promote(_:)`` can refresh it when
/// the user re-copies an existing item from the panel.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    /// Last time this item was copied. Updated by ``ClipboardStore/promote(_:)``.
    var timestamp: Date
    var text: String?
    /// File name (not full path) of the saved PNG inside the images directory.
    var imageFileName: String?
    var url: String?
    var filePaths: [String]?
    var sourceAppBundleID: String?
    var sourceAppName: String?

    /// A human-readable title used in the panel row and the search-bar chip.
    /// Text is truncated to 120 characters to keep the UI compact.
    var displayTitle: String {
        switch type {
        case .text:  return text.map { t in t.count > 120 ? String(t.prefix(117)) + "…" : t } ?? ""
        case .image: return "Image"
        case .url:   return url ?? ""
        case .file:  return filePaths?.first.map { ($0 as NSString).lastPathComponent } ?? "File"
        }
    }

    /// Short type label shown in the row subtitle (e.g. "Text · Copied 14:32").
    var typeLabel: String {
        switch type {
        case .text:  return "Text"
        case .image: return "PNG Image"
        case .url:   return "URL"
        case .file:  return "File"
        }
    }

    /// Identity is by `id` only so that `promote(_:)` can mutate `timestamp`
    /// without SwiftUI treating it as a different item.
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool { lhs.id == rhs.id }
}

/// Returns the wall-clock copy time formatted as "HH:mm", shown in row subtitles.
/// - Parameter date: The copy timestamp to format.
func copiedTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}
