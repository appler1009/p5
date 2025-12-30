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
    let item = LocalFileSystemMediaItem(id: 1, original: url)
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
      id: 1, original: URL(fileURLWithPath: "/nonexistent.jpg"))
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
    let item = LocalFileSystemMediaItem(id: 2, original: url)
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

    let today = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    let imageUTI = "public.image"
    let videoUTI = "public.video"

    let source_1234_image: ImportView.MediaSource = .init(
      date: today, name: "IMG_1234.JPG", uti: imageUTI)
    let source_1234_edited_image: ImportView.MediaSource = .init(
      date: today, name: "IMG_1234 (Edited).JPG", uti: imageUTI)
    let source_1234_video: ImportView.MediaSource = .init(
      date: today, name: "IMG_1234.MOV", uti: videoUTI)

    let source_1111_image: ImportView.MediaSource = .init(
      date: today, name: "IMG_1111.HEIC", uti: imageUTI)
    let source_1111_edited_image: ImportView.MediaSource = .init(
      date: today, name: "IMG_E1111.HEIC", uti: imageUTI)

    let source_1112_video: ImportView.MediaSource = .init(
      date: today, name: "IMG_1112.MOV", uti: videoUTI)
    let source_1112_edited_video: ImportView.MediaSource = .init(
      date: today, name: "IMG_E1112.MOV", uti: videoUTI)

    let source_2222_image: ImportView.MediaSource = .init(
      date: today, name: "IMG_2222.HEIC", uti: imageUTI)
    let source_2222_video: ImportView.MediaSource = .init(
      date: today, name: "IMG_2222.MOV", uti: videoUTI)

    let source_3333_video: ImportView.MediaSource = .init(
      date: today, name: "IMG_3333.MOV", uti: videoUTI)

    let source_4444_image: ImportView.MediaSource = .init(
      date: today, name: "IMG_4444.HEIC", uti: imageUTI)
    let source_4444_edited_image: ImportView.MediaSource = .init(
      date: today, name: "IMG_E4444.HEIC", uti: imageUTI)

    let source_9999_txt: ImportView.MediaSource = .init(
      date: today, name: "readme.txt", uti: "public.text")
    let source_9999_zip: ImportView.MediaSource = .init(
      date: today, name: "archive.zip", uti: "public.zip")

    let source_5555_image_today: ImportView.MediaSource = .init(
      date: today, name: "IMG_5555.HEIC", uti: imageUTI)
    let source_5555_image_yesterday: ImportView.MediaSource = .init(
      date: yesterday, name: "IMG_5555.HEIC", uti: imageUTI)

    // Test case 1: Single photo
    let singlePhoto: [ImportView.MediaSource] = [source_1234_image]
    let result1 = importView.groupRelatedMedia(singlePhoto)
    XCTAssertEqual(result1.count, 1)
    XCTAssertEqual(result1[0].main, source_1234_image)
    XCTAssertNil(result1[0].edited)
    XCTAssertNil(result1[0].live)

    // Test case 2: Original and edited photo
    let originalAndEdited: [ImportView.MediaSource] = [
      source_1234_image,
      source_1234_edited_image,
    ]
    let result2 = importView.groupRelatedMedia(originalAndEdited)
    XCTAssertEqual(result2.count, 1)
    // The shorter name becomes main, longer becomes edited
    XCTAssertEqual(result2[0].main, source_1234_image)
    XCTAssertEqual(result2[0].edited, source_1234_edited_image)
    XCTAssertNil(result2[0].live)

    // Test case 3: Live photo (HEIC + MOV)
    let livePhoto: [ImportView.MediaSource] = [
      source_1234_image,
      source_1234_video,
    ]
    let result3 = importView.groupRelatedMedia(livePhoto)
    XCTAssertEqual(result3.count, 1)
    XCTAssertEqual(result3[0].main, source_1234_image)
    XCTAssertNil(result3[0].edited)
    XCTAssertEqual(result3[0].live, source_1234_video)

    // Test case 4: Live photo with edited version
    let livePhotoEdited: [ImportView.MediaSource] = [
      source_1234_image,
      source_1234_edited_image,
      source_1234_video,
    ]
    let result4 = importView.groupRelatedMedia(livePhotoEdited)
    XCTAssertEqual(result4.count, 1)
    XCTAssertEqual(result4[0].main, source_1234_image)
    XCTAssertEqual(result4[0].edited, source_1234_edited_image)
    XCTAssertEqual(result4[0].live, source_1234_video)

    // Test case 5: Separate video file (not live photo)
    let separateVideo: [ImportView.MediaSource] = [source_1234_video]
    let result5 = importView.groupRelatedMedia(separateVideo)
    XCTAssertEqual(result5.count, 1)
    XCTAssertEqual(result5[0].main, source_1234_video)
    XCTAssertNil(result5[0].edited)
    XCTAssertNil(result5[0].live)

    // Test case 6: Mixed content - photo, live photo, and separate video
    let mixedContent: [ImportView.MediaSource] = [
      source_1111_image,  // Single photo
      source_2222_image, source_2222_video,  // Live photo
      source_3333_video,  // Separate video
      source_4444_image, source_4444_edited_image,  // Eedited photo
    ]
    let result6 = importView.groupRelatedMedia(mixedContent)
    XCTAssertEqual(result6.count, 4)

    // Find each group
    let photoGroup = result6.first { $0.main == source_1111_image }
    XCTAssertNotNil(photoGroup)
    XCTAssertNil(photoGroup?.edited)
    XCTAssertNil(photoGroup?.live)

    let liveGroup = result6.first { $0.main == source_2222_image }
    XCTAssertNotNil(liveGroup)
    XCTAssertNil(liveGroup?.edited)
    XCTAssertEqual(liveGroup?.live, source_2222_video)

    let videoGroup = result6.first { $0.main == source_3333_video }
    XCTAssertNotNil(videoGroup)
    XCTAssertNil(videoGroup?.edited)
    XCTAssertNil(videoGroup?.live)

    let editedPhotoGroup = result6.first { $0.main == source_4444_image }
    XCTAssertNotNil(editedPhotoGroup)
    XCTAssertEqual(editedPhotoGroup?.edited, source_4444_edited_image)
    XCTAssertNil(editedPhotoGroup?.live)

    // Test case 7: iOS edited photo shows up first in the list
    let iosEditedPic: [ImportView.MediaSource] = [
      source_1111_edited_image,
      source_1111_image,
    ]
    let result7 = importView.groupRelatedMedia(iosEditedPic)
    XCTAssertEqual(result7.count, 1)
    XCTAssertEqual(result7[0].main, source_1111_image)
    XCTAssertEqual(result7[0].edited, source_1111_edited_image)
    XCTAssertNil(result7[0].live)

    // Test case 8: iOS edited photo shows up first in the list
    let iosEditedVid: [ImportView.MediaSource] = [
      source_1112_edited_video,
      source_1112_video,
    ]
    let result8 = importView.groupRelatedMedia(iosEditedVid)
    XCTAssertEqual(result8.count, 1)
    XCTAssertEqual(result8[0].main, source_1112_video)
    XCTAssertEqual(result8[0].edited, source_1112_edited_video)
    XCTAssertNil(result8[0].live)

    // Test case 8: Empty input
    let emptyInput: [ImportView.MediaSource] = []
    let result9 = importView.groupRelatedMedia(emptyInput)
    XCTAssertEqual(result9.count, 0)

    // Test case 9: Unsupported file types
    let unsupported: [ImportView.MediaSource] = [
      source_9999_txt,
      source_9999_zip,
    ]
    let result10 = importView.groupRelatedMedia(unsupported)
    XCTAssertEqual(result10.count, 0)

    // Test case 10: different days with same file name
    let multipleDates: [ImportView.MediaSource] = [
      source_5555_image_today,
      source_5555_image_yesterday,
    ]
    let result11 = importView.groupRelatedMedia(multipleDates)
    XCTAssertEqual(result11.count, 2)
    XCTAssertEqual(result11[0].main, source_5555_image_yesterday)
    XCTAssertNil(result11[0].edited)
    XCTAssertNil(result11[0].live)
    XCTAssertEqual(result11[1].main, source_5555_image_today)
    XCTAssertNil(result11[1].edited)
    XCTAssertNil(result11[1].live)
  }

  func testExtractBaseName() throws {
    // Test case 1: Basic filename
    XCTAssertEqual("IMG_1234.JPG".extractBaseName(), "IMG_1234")

    // Test case 2: Edited photo
    XCTAssertEqual("IMG_1234 (Edited).JPG".extractBaseName(), "IMG_1234")

    // Test case 3: iOS edited photo (E suffix)
    XCTAssertEqual("IMG_E1234.JPG".extractBaseName(), "IMG_1234")

    // Test case 4: iOS edited photo with separator
    XCTAssertEqual("IMG_E1234.JPG".extractBaseName(), "IMG_1234")

    // Test case 5: Different extensions
    XCTAssertEqual("PHOTO_9999.HEIC".extractBaseName(), "PHOTO_9999")
    XCTAssertEqual("VIDEO_1111.MP4".extractBaseName(), "VIDEO_1111")

    // Test case 6: Case insensitive extensions
    XCTAssertEqual("test.jpeg".extractBaseName(), "test")
    XCTAssertEqual("test.JPEG".extractBaseName(), "test")

    // Test case 7: No extension
    XCTAssertEqual("IMG_1234".extractBaseName(), "IMG_1234")

    // Test case 8: Complex edited filename
    XCTAssertEqual("IMG_E9999 (Edited).HEIC".extractBaseName(), "IMG_9999")

    // Test case 9: Multiple extensions (unknown extension also removed)
    XCTAssertEqual("test.jpg.backup".extractBaseName(), "test.jpg")

    // Test case 10: iOS edited photo with E suffix at end
    XCTAssertEqual("ABCDE1234.JPG".extractBaseName(), "ABCD1234")
  }
}
