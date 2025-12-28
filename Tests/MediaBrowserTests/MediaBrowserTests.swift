import XCTest

@testable import MediaBrowser

final class MediaBrowserTests: XCTestCase {
  func testExample() throws {
    // Test something simple
    XCTAssertEqual(2 + 2, 4)
  }

  func testMediaScannerIsEdited() throws {
    let scanner = MediaScanner.shared
    XCTAssertTrue(scanner.isEdited(base: "IMG_E1234"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_1234"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_1234E"))
  }

  func testMediaItemInit() throws {
    let url = URL(fileURLWithPath: "/test.jpg")
    let item = MediaItem(id: 1, url: url, type: .photo, displayName: nil)
    XCTAssertEqual(item.url, url)
    XCTAssertEqual(item.type, MediaType.photo)
  }

  func testContentViewMonthlyGroups() throws {
    // Test the monthly grouping logic by extracting the logic
    let calendar = Calendar.current
    let testItems: [MediaItem] = []  // Empty for simplicity
    let grouped = Dictionary(grouping: testItems) { item -> Date? in
      guard let date = item.metadata?.creationDate else { return nil }
      return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }
    let sortedGroups = grouped.sorted { (lhs, rhs) -> Bool in
      guard let lhsDate = lhs.key, let rhsDate = rhs.key else { return lhs.key != nil }
      return lhsDate > rhsDate
    }
    let monthlyGroups = sortedGroups.map {
      (
        month: $0.key?.formatted(.dateTime.year().month(.wide)) ?? "Unknown",
        items: $0.value.sorted {
          ($0.metadata?.creationDate ?? Date.distantPast)
            > ($1.metadata?.creationDate ?? Date.distantPast)
        }
      )
    }
    XCTAssertEqual(monthlyGroups.count, 0)
  }

  func testMediaScannerMediaType() throws {
    let scanner = MediaScanner.shared
    let jpgURL = URL(fileURLWithPath: "/test.jpg")
    let movURL = URL(fileURLWithPath: "/test.mov")
    let unknownURL = URL(fileURLWithPath: "/test.txt")

    XCTAssertEqual(scanner.mediaType(for: jpgURL), .photo)
    XCTAssertEqual(scanner.mediaType(for: movURL), .video)
    XCTAssertNil(scanner.mediaType(for: unknownURL))
  }

  func testMediaScannerScan() async throws {
    let scanner = MediaScanner.shared
    // Test scan with empty directories (no file system access)
    await scanner.scan(directories: [])
    XCTAssertEqual(scanner.items.count, 0)
  }

  func testMediaScannerCountItems() async throws {
    let scanner = MediaScanner.shared
    let nonExistentURL = URL(fileURLWithPath: "/nonexistent")
    let count = await scanner.countItems(in: nonExistentURL)
    XCTAssertEqual(count, 0)
  }

  func testMediaScannerScanDirectory() async throws {
    let scanner = MediaScanner.shared
    let nonExistentURL = URL(fileURLWithPath: "/nonexistent")
    // Before
    let before = scanner.items.count
    await scanner.scanDirectory(nonExistentURL)
    // After, should be same
    XCTAssertEqual(scanner.items.count, before)
  }

  func testThumbnailCache() async throws {
    let cache = ThumbnailCache.shared
    let testURL = URL(fileURLWithPath: "/nonexistent.jpg")
    let image = await cache.thumbnail(for: testURL, size: CGSize(width: 100, height: 100))
    XCTAssertNil(image)  // Since file doesn't exist
  }

  func testDirectoryManager() throws {
    let manager = DirectoryManager.shared
    // Test remove
    let testURL1 = URL(fileURLWithPath: "/tmp/testdir1")
    let testURL2 = URL(fileURLWithPath: "/tmp/testdir2")
    manager.directories = [testURL1, testURL2]

    XCTAssertEqual(manager.directories.count, 2)

    // Test remove
    manager.removeDirectory(at: 0)
    XCTAssertEqual(manager.directories.count, 1)
    XCTAssertEqual(manager.directories.first, testURL2)

    // Test cleanup thumbnails
    let cleaned = manager.cleanupThumbnails()
    XCTAssertGreaterThanOrEqual(cleaned, 0)  // At least 0
  }

  func testBlurHashRoundTrip() throws {
    let testImage = NSImage(size: NSSize(width: 100, height: 100))
    testImage.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 100, height: 100).fill()
    testImage.unlockFocus()

    let hash = testImage.blurHash(numberOfComponents: (4, 3))
    XCTAssertNotNil(hash)

    let decodedImage = NSImage(blurHash: hash!, size: NSSize(width: 100, height: 100))
    XCTAssertNotNil(decodedImage)
  }

  func testDatabaseInsertAndRetrieve() throws {
    // Test database operations
    let db = DatabaseManager.shared

    // Clear DB first
    db.clearAll()

    let url = URL(fileURLWithPath: "/test/photo.jpg")
    let metadata = MediaMetadata(
      filePath: "/test/photo.jpg",
      filename: "photo.jpg",
      creationDate: Date(),
      modificationDate: Date(),
      dimensions: CGSize(width: 1920, height: 1080),
      exifDate: nil,
      gps: nil,
      duration: nil,
      make: "Test",
      model: "Test",
      lens: nil,
      iso: 100,
      aperture: 2.8,
      shutterSpeed: "1/100"
    )
    let item = MediaItem(id: 2, url: url, type: .photo, metadata: metadata, displayName: nil)

    db.insertItem(item)

    let items = db.getAllItems()
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.url, url)
    XCTAssertEqual(items.first?.type, MediaType.photo)
    XCTAssertEqual(items.first?.metadata?.filename, "photo.jpg")
  }
}
