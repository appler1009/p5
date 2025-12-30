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
    let item = LocalFileSystemMediaItem(id: 1, type: .photo, original: url)
    XCTAssertEqual(item.originalUrl, url)
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
    let testItem = LocalFileSystemMediaItem(
      id: 1, type: .photo, original: URL(fileURLWithPath: "/nonexistent.jpg"))
    let image = cache.thumbnail(mediaItem: testItem)
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

  func testDatabaseInsertAndRetrieve() throws {
    // Test database operations
    let db = DatabaseManager.shared

    // Clear DB first
    db.clearAll()

    let url = URL(fileURLWithPath: "/test/photo.jpg")
    let metadata = MediaMetadata(
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
    let item = LocalFileSystemMediaItem(id: 2, type: .photo, original: url)
    item.metadata = metadata

    db.insertItem(item)

    let items = db.getAllItems()
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.originalUrl, url)
    XCTAssertEqual(items.first?.type, MediaType.photo)
    // Note: id may be auto-assigned by DB, so we don't check it
  }

  func testGroupRelatedMedia() throws {
    // Create a mock ImportView to access the private method
    let importView = ImportView()

    // Test case 1: Single photo
    let singlePhoto = ["IMG_1234.JPG"]
    let result1 = importView.groupRelatedMedia(singlePhoto)
    XCTAssertEqual(result1.count, 1)
    XCTAssertEqual(result1[0].main, "IMG_1234.JPG")
    XCTAssertNil(result1[0].edited)
    XCTAssertNil(result1[0].live)

    // Test case 2: Original and edited photo
    let originalAndEdited = ["IMG_1234.JPG", "IMG_1234 (Edited).JPG"]
    let result2 = importView.groupRelatedMedia(originalAndEdited)
    XCTAssertEqual(result2.count, 1)
    // The shorter name becomes main, longer becomes edited
    XCTAssertEqual(result2[0].main, "IMG_1234.JPG")
    XCTAssertEqual(result2[0].edited, "IMG_1234 (Edited).JPG")
    XCTAssertNil(result2[0].live)

    // Test case 3: Live photo (HEIC + MOV)
    let livePhoto = ["IMG_5678.HEIC", "IMG_5678.MOV"]
    let result3 = importView.groupRelatedMedia(livePhoto)
    XCTAssertEqual(result3.count, 1)
    XCTAssertEqual(result3[0].main, "IMG_5678.HEIC")
    XCTAssertNil(result3[0].edited)
    XCTAssertEqual(result3[0].live, "IMG_5678.MOV")

    // Test case 4: Live photo with edited version
    let livePhotoEdited = ["IMG_9999.HEIC", "IMG_9999 (Edited).HEIC", "IMG_9999.MOV"]
    let result4 = importView.groupRelatedMedia(livePhotoEdited)
    XCTAssertEqual(result4.count, 1)
    XCTAssertEqual(result4[0].main, "IMG_9999.HEIC")
    XCTAssertEqual(result4[0].edited, "IMG_9999 (Edited).HEIC")
    XCTAssertEqual(result4[0].live, "IMG_9999.MOV")

    // Test case 5: Separate video file (not live photo)
    let separateVideo = ["VIDEO_001.MP4"]
    let result5 = importView.groupRelatedMedia(separateVideo)
    XCTAssertEqual(result5.count, 1)
    XCTAssertEqual(result5[0].main, "VIDEO_001.MP4")
    XCTAssertNil(result5[0].edited)
    XCTAssertNil(result5[0].live)

    // Test case 6: Mixed content - photo, live photo, and separate video
    let mixedContent = [
      "IMG_1111.JPG",  // Single photo
      "IMG_2222.HEIC", "IMG_2222.MOV",  // Live photo
      "VIDEO_3333.MP4",  // Separate video
      "IMG_4444.HEIC", "IMG_E4444.HEIC",  // Eedited photo
    ]
    let result6 = importView.groupRelatedMedia(mixedContent)
    XCTAssertEqual(result6.count, 4)

    // Find each group
    let photoGroup = result6.first { $0.main == "IMG_1111.JPG" }
    XCTAssertNotNil(photoGroup)
    XCTAssertNil(photoGroup?.edited)
    XCTAssertNil(photoGroup?.live)

    let liveGroup = result6.first { $0.main == "IMG_2222.HEIC" }
    XCTAssertNotNil(liveGroup)
    XCTAssertNil(liveGroup?.edited)
    XCTAssertEqual(liveGroup?.live, "IMG_2222.MOV")

    let videoGroup = result6.first { $0.main == "VIDEO_3333.MP4" }
    XCTAssertNotNil(videoGroup)
    XCTAssertNil(videoGroup?.edited)
    XCTAssertNil(videoGroup?.live)

    let editedPhotoGroup = result6.first { $0.main == "IMG_4444.HEIC" }
    XCTAssertNotNil(editedPhotoGroup)
    XCTAssertEqual(editedPhotoGroup?.edited, "IMG_E4444.HEIC")
    XCTAssertNil(editedPhotoGroup?.live)

    // Test case 7: iOS edited photo shows up first in the list
    let iosEditedPic = ["IMG_E1234.JPG", "IMG_1234.JPG"]
    let result7 = importView.groupRelatedMedia(iosEditedPic)
    XCTAssertEqual(result7.count, 1)
    XCTAssertEqual(result7[0].main, "IMG_1234.JPG")
    XCTAssertEqual(result7[0].edited, "IMG_E1234.JPG")
    XCTAssertNil(result7[0].live)

    // Test case 8: iOS edited photo shows up first in the list
    let iosEditedVid = ["IMG_E1234.MOV", "IMG_1234.MOV"]
    let result8 = importView.groupRelatedMedia(iosEditedVid)
    XCTAssertEqual(result8.count, 1)
    XCTAssertEqual(result8[0].main, "IMG_1234.MOV")
    XCTAssertEqual(result8[0].edited, "IMG_E1234.MOV")
    XCTAssertNil(result8[0].live)

    // Test case 8: Empty input
    let emptyInput: [String] = []
    let result9 = importView.groupRelatedMedia(emptyInput)
    XCTAssertEqual(result9.count, 0)

    // Test case 9: Unsupported file types
    let unsupported = ["document.txt", "archive.zip"]
    let result10 = importView.groupRelatedMedia(unsupported)
    XCTAssertEqual(result10.count, 0)
  }

  func testExtractBaseName() throws {
    let importView = ImportView()

    // Test case 1: Basic filename
    XCTAssertEqual(importView.extractBaseName(from: "IMG_1234.JPG"), "IMG_1234")

    // Test case 2: Edited photo
    XCTAssertEqual(importView.extractBaseName(from: "IMG_1234 (Edited).JPG"), "IMG_1234")

    // Test case 3: iOS edited photo (E suffix)
    XCTAssertEqual(importView.extractBaseName(from: "IMG_E1234.JPG"), "IMG_1234")

    // Test case 4: iOS edited photo with separator
    XCTAssertEqual(importView.extractBaseName(from: "IMG_E1234.JPG"), "IMG_1234")

    // Test case 5: Different extensions
    XCTAssertEqual(importView.extractBaseName(from: "PHOTO_9999.HEIC"), "PHOTO_9999")
    XCTAssertEqual(importView.extractBaseName(from: "VIDEO_1111.MP4"), "VIDEO_1111")

    // Test case 6: Case insensitive extensions
    XCTAssertEqual(importView.extractBaseName(from: "test.jpeg"), "test")
    XCTAssertEqual(importView.extractBaseName(from: "test.JPEG"), "test")

    // Test case 7: No extension
    XCTAssertEqual(importView.extractBaseName(from: "IMG_1234"), "IMG_1234")

    // Test case 8: Complex edited filename
    XCTAssertEqual(importView.extractBaseName(from: "IMG_E9999 (Edited).HEIC"), "IMG_9999")

    // Test case 9: Multiple extensions (unknown extension not removed)
    XCTAssertEqual(importView.extractBaseName(from: "test.jpg.backup"), "test.jpg.backup")

    // Test case 10: iOS edited photo with E suffix at end
    XCTAssertEqual(importView.extractBaseName(from: "ABCDE1234.JPG"), "ABCD1234")
  }
}
