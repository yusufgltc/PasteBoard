import XCTest
import Combine
@testable import PasteBoard

final class ClipboardStoreTests: XCTestCase {

    private var repo:     FakeClipboardRepository!
    private var settings: FakeSettings!
    private var store:    ClipboardStore!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        repo     = FakeClipboardRepository()
        settings = FakeSettings()
        store    = ClipboardStore(repository: repo, settings: settings)
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - add / dedup

    func testAdd_insertsItemAtTop() {
        let a = ClipboardItem.text("A")
        let b = ClipboardItem.text("B")
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.items.first?.text, "B")
        XCTAssertEqual(store.items.count, 2)
    }

    func testAdd_deduplicates_text() {
        let first  = ClipboardItem.text("hello")
        let second = ClipboardItem.text("hello")
        store.add(first)
        store.add(second)
        XCTAssertEqual(store.items.count, 1, "duplicate text must collapse to one entry")
        XCTAssertEqual(store.items.first?.id, second.id)
    }

    func testAdd_deduplicates_url() {
        store.add(.url("https://example.com"))
        store.add(.url("https://example.com"))
        XCTAssertEqual(store.items.count, 1)
    }

    func testAdd_deduplicates_file() {
        store.add(.file(["/a/b.txt"]))
        store.add(.file(["/a/b.txt"]))
        XCTAssertEqual(store.items.count, 1)
    }

    func testAdd_deduplicates_images_with_same_content() {
        let img1 = ClipboardItem.image(fileName: "abc123.png")
        let img2 = ClipboardItem.image(fileName: "abc123.png")  // same hash = same pixels
        store.add(img1)
        store.add(img2)
        XCTAssertEqual(store.items.count, 1, "images with the same content hash must deduplicate")
    }

    func testAdd_doesNotDeduplicate_images_with_different_content() {
        let img1 = ClipboardItem.image(fileName: "abc123.png")
        let img2 = ClipboardItem.image(fileName: "def456.png")  // different hash = different pixels
        store.add(img1)
        store.add(img2)
        XCTAssertEqual(store.items.count, 2, "images with different content must not deduplicate")
    }

    func testAdd_doesNotDeleteImageFile_whenDeduplicatingSameContent() {
        let img1 = ClipboardItem.image(fileName: "shared.png")
        let img2 = ClipboardItem.image(fileName: "shared.png")
        repo.savedImages["shared.png"] = NSImage()
        store.add(img1)
        store.add(img2)
        XCTAssertFalse(repo.deletedFileNames.contains("shared.png"),
                       "must not delete the image file when both items reference the same content")
        XCTAssertNotNil(repo.savedImages["shared.png"])
    }

    func testAdd_doesNotDeduplicate_acrossTypes() {
        store.add(.text("https://example.com"))
        store.add(.url("https://example.com"))
        XCTAssertEqual(store.items.count, 2, "same string as text vs url must not dedup")
    }

    func testAdd_persistsAfterEveryInsert() {
        store.add(.text("X"))
        XCTAssertEqual(repo.savedItems.count, 1)
        store.add(.text("Y"))
        XCTAssertEqual(repo.savedItems.count, 2)
    }

    // MARK: - cap enforcement

    func testAdd_dropsOldestWhenCapExceeded() {
        let oldest = ClipboardItem.text("oldest")
        store.add(oldest)
        for i in 1...50 { store.add(.text("item-\(i)")) }
        XCTAssertEqual(store.items.count, 50)
        XCTAssertFalse(store.items.contains { $0.id == oldest.id }, "oldest item must be evicted")
    }

    func testAdd_deletesImageFileWhenEvicted() {
        let imageItem = ClipboardItem.image(fileName: "evict-me.png")
        repo.savedImages["evict-me.png"] = NSImage()
        store.add(imageItem)
        for i in 1...50 { store.add(.text("item-\(i)")) }
        XCTAssertTrue(repo.deletedFileNames.contains("evict-me.png"),
                      "image file must be deleted when its item is evicted by the cap")
    }

    // MARK: - promote

    func testPromote_movesItemToTop() {
        let a = ClipboardItem.text("A")
        let b = ClipboardItem.text("B")
        store.add(a)
        store.add(b)           // order: [B, A]
        store.promote(a)       // should become [A, B]
        XCTAssertEqual(store.items.first?.id, a.id)
    }

    func testPromote_updatesTimestamp() {
        let item = ClipboardItem.text("old", daysAgo: 1)
        store.add(item)
        let before = store.items.first!.timestamp
        store.promote(item)
        XCTAssertGreaterThan(store.items.first!.timestamp, before)
    }

    // MARK: - remove

    func testRemove_deletesItem() {
        let item = ClipboardItem.text("bye")
        store.add(item)
        store.remove(item)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRemove_deletesAssociatedImageFile() {
        let item = ClipboardItem.image(fileName: "remove-me.png")
        repo.savedImages["remove-me.png"] = NSImage()
        store.add(item)
        store.remove(item)
        XCTAssertTrue(repo.deletedFileNames.contains("remove-me.png"))
    }

    // MARK: - clearAll

    func testClearAll_removesEverything() {
        store.add(.text("A"))
        store.add(.text("B"))
        store.clearAll()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(repo.savedItems.isEmpty)
    }

    func testClearAll_deletesAllImageFiles() {
        let img1 = ClipboardItem.image(fileName: "clear1.png")
        let img2 = ClipboardItem.image(fileName: "clear2.png")
        repo.savedImages["clear1.png"] = NSImage()
        repo.savedImages["clear2.png"] = NSImage()
        store.add(img1)
        store.add(img2)
        store.clearAll()
        XCTAssertTrue(repo.deletedFileNames.contains("clear1.png"))
        XCTAssertTrue(repo.deletedFileNames.contains("clear2.png"))
    }

    // MARK: - retention purge

    func testPurge_removesExpiredItemsOnInit() {
        let expired = ClipboardItem.text("old", daysAgo: 10)
        let fresh   = ClipboardItem.text("new", daysAgo: 0)
        repo.saveItems([expired, fresh])
        settings = FakeSettings(retention: .thirtyMinutes) // 30-min window
        store = ClipboardStore(repository: repo, settings: settings)
        XCTAssertFalse(store.items.contains { $0.id == expired.id }, "item older than retention must be purged on load")
        XCTAssertTrue(store.items.contains  { $0.id == fresh.id   })
    }

    func testPurge_triggersWhenRetentionChanges() {
        let oldItem = ClipboardItem.text("too old", daysAgo: 2)
        store.add(oldItem)
        XCTAssertEqual(store.items.count, 1)

        let expectation = XCTestExpectation(description: "purge after retention change")
        store.$items.dropFirst().sink { items in
            if items.isEmpty { expectation.fulfill() }
        }.store(in: &cancellables)

        settings.changeRetention(to: .thirtyMinutes)
        wait(for: [expectation], timeout: 1.0)
    }

    func testPurge_deletesImageFilesForExpiredItems() {
        let expired = ClipboardItem.image(fileName: "expired.png", daysAgo: 10)
        repo.savedImages["expired.png"] = NSImage()
        repo.saveItems([expired])
        settings = FakeSettings(retention: .thirtyMinutes)
        store = ClipboardStore(repository: repo, settings: settings)
        XCTAssertTrue(repo.deletedFileNames.contains("expired.png"),
                      "image file for expired item must be deleted during purge")
    }
}
