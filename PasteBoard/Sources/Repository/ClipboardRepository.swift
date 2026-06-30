import AppKit

/// Abstracts all persistence for clipboard items and their associated image files.
///
/// The only production implementation is ``FileSystemClipboardRepository``.
/// Tests use an in-memory fake that conforms to this protocol without touching disk.
protocol ClipboardRepository: AnyObject {
    func loadItems() -> [ClipboardItem]
    func saveItems(_ items: [ClipboardItem])
    func saveImage(_ image: NSImage) -> String
    func loadImage(fileName: String) -> NSImage?
    func deleteImage(fileName: String)
}
