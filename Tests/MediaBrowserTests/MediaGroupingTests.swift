import ImageCaptureCore
import XCTest

@testable import MediaBrowser

final class MediaGroupingTests: XCTestCase {
  func testGroupRelatedMedia() throws {
    let today = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    let imageUTI = "public.image"
    let videoUTI = "public.video"

    let source_1234_image: MediaSource = .init(
      date: today, name: "IMG_1234.JPG", uti: imageUTI)
    let source_1234_edited_image: MediaSource = .init(
      date: today, name: "IMG_1234 (Edited).JPG", uti: imageUTI)
    let source_1234_video: MediaSource = .init(
      date: today, name: "IMG_1234.MOV", uti: videoUTI)

    let source_1111_image: MediaSource = .init(
      date: today, name: "IMG_1111.HEIC", uti: imageUTI)
    let source_1111_edited_image: MediaSource = .init(
      date: today, name: "IMG_E1111.HEIC", uti: imageUTI)

    let source_1112_video: MediaSource = .init(
      date: today, name: "IMG_1112.MOV", uti: videoUTI)
    let source_1112_edited_video: MediaSource = .init(
      date: today, name: "IMG_E1112.MOV", uti: videoUTI)

    let source_2222_image: MediaSource = .init(
      date: today, name: "IMG_2222.HEIC", uti: imageUTI)
    let source_2222_video: MediaSource = .init(
      date: today, name: "IMG_2222.MOV", uti: videoUTI)

    let source_3333_video: MediaSource = .init(
      date: today, name: "IMG_3333.MOV", uti: videoUTI)

    let source_4444_image: MediaSource = .init(
      date: today, name: "IMG_4444.HEIC", uti: imageUTI)
    let source_4444_edited_image: MediaSource = .init(
      date: today, name: "IMG_E4444.HEIC", uti: imageUTI)

    let source_9999_txt: MediaSource = .init(
      date: today, name: "readme.txt", uti: "public.text")
    let source_9999_zip: MediaSource = .init(
      date: today, name: "archive.zip", uti: "public.zip")

    let source_5555_image_today: MediaSource = .init(
      date: today, name: "IMG_5555.HEIC", uti: imageUTI)
    let source_5555_image_yesterday: MediaSource = .init(
      date: yesterday, name: "IMG_5555.HEIC", uti: imageUTI)

    // Test case 1: Single photo
    let singlePhoto: [MediaSource] = [source_1234_image]
    let result1 = groupRelatedMedia(singlePhoto)
    XCTAssertEqual(result1.count, 1)
    XCTAssertEqual(result1[0].main, source_1234_image)
    XCTAssertNil(result1[0].edited)
    XCTAssertNil(result1[0].live)

    // Test case 2: Original and edited photo
    let originalAndEdited: [MediaSource] = [
      source_1234_image,
      source_1234_edited_image,
    ]
    let result2 = groupRelatedMedia(originalAndEdited)
    XCTAssertEqual(result2.count, 1)
    // The shorter name becomes main, longer becomes edited
    XCTAssertEqual(result2[0].main, source_1234_image)
    XCTAssertEqual(result2[0].edited, source_1234_edited_image)
    XCTAssertNil(result2[0].live)

    // Test case 3: Live photo (HEIC + MOV)
    let livePhoto: [MediaSource] = [
      source_1234_image,
      source_1234_video,
    ]
    let result3 = groupRelatedMedia(livePhoto)
    XCTAssertEqual(result3.count, 1)
    XCTAssertEqual(result3[0].main, source_1234_image)
    XCTAssertNil(result3[0].edited)
    XCTAssertEqual(result3[0].live, source_1234_video)

    // Test case 4: Live photo with edited version
    let livePhotoEdited: [MediaSource] = [
      source_1234_image,
      source_1234_edited_image,
      source_1234_video,
    ]
    let result4 = groupRelatedMedia(livePhotoEdited)
    XCTAssertEqual(result4.count, 1)
    XCTAssertEqual(result4[0].main, source_1234_image)
    XCTAssertEqual(result4[0].edited, source_1234_edited_image)
    XCTAssertEqual(result4[0].live, source_1234_video)

    // Test case 5: Separate video file (not live photo)
    let separateVideo: [MediaSource] = [source_1234_video]
    let result5 = groupRelatedMedia(separateVideo)
    XCTAssertEqual(result5.count, 1)
    XCTAssertEqual(result5[0].main, source_1234_video)
    XCTAssertNil(result5[0].edited)
    XCTAssertNil(result5[0].live)

    // Test case 6: Mixed content - photo, live photo, and separate video
    let mixedContent: [MediaSource] = [
      source_1111_image,  // Single photo
      source_2222_image, source_2222_video,  // Live photo
      source_3333_video,  // Separate video
      source_4444_image, source_4444_edited_image,  // Eedited photo
    ]
    let result6 = groupRelatedMedia(mixedContent)
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
    let iosEditedPic: [MediaSource] = [
      source_1111_edited_image,
      source_1111_image,
    ]
    let result7 = groupRelatedMedia(iosEditedPic)
    XCTAssertEqual(result7.count, 1)
    XCTAssertEqual(result7[0].main, source_1111_image)
    XCTAssertEqual(result7[0].edited, source_1111_edited_image)
    XCTAssertNil(result7[0].live)

    // Test case 8: iOS edited photo shows up first in the list
    let iosEditedVid: [MediaSource] = [
      source_1112_edited_video,
      source_1112_video,
    ]
    let result8 = groupRelatedMedia(iosEditedVid)
    XCTAssertEqual(result8.count, 1)
    XCTAssertEqual(result8[0].main, source_1112_video)
    XCTAssertEqual(result8[0].edited, source_1112_edited_video)
    XCTAssertNil(result8[0].live)

    // Test case 8: Empty input
    let emptyInput: [MediaSource] = []
    let result9 = groupRelatedMedia(emptyInput)
    XCTAssertEqual(result9.count, 0)

    // Test case 9: Unsupported file types
    let unsupported: [MediaSource] = [
      source_9999_txt,
      source_9999_zip,
    ]
    let result10 = groupRelatedMedia(unsupported)
    XCTAssertEqual(result10.count, 0)

    // Test case 10: different days with same file name
    let multipleDates: [MediaSource] = [
      source_5555_image_today,
      source_5555_image_yesterday,
    ]
    let result11 = groupRelatedMedia(multipleDates)
    XCTAssertEqual(result11.count, 2)
    XCTAssertEqual(result11[0].main, source_5555_image_yesterday)
    XCTAssertNil(result11[0].edited)
    XCTAssertNil(result11[0].live)
    XCTAssertEqual(result11[1].main, source_5555_image_today)
    XCTAssertNil(result11[1].edited)
    XCTAssertNil(result11[1].live)
  }

  func testGroupRelatedCameraItems() throws {
    // Mock ICCameraItem for testing
    class MockICCameraItem: ICCameraItem {
      let itemName: String
      let itemUti: String
      let itemCreationDate: Date

      init(name: String, uti: String, creationDate: Date) {
        self.itemName = name
        self.itemUti = uti
        self.itemCreationDate = creationDate
      }

      override var name: String? { return itemName }
      override var uti: String? { return itemUti }
      override var creationDate: Date? { return itemCreationDate }
    }

    let today = Date()

    let mockItem1 = MockICCameraItem(name: "IMG_1234.JPG", uti: "public.image", creationDate: today)
    let mockItem2 = MockICCameraItem(
      name: "IMG_1234 (Edited).JPG", uti: "public.image", creationDate: today)
    let mockItem3 = MockICCameraItem(name: "IMG_1234.MOV", uti: "public.video", creationDate: today)

    let mockCameraItems = [mockItem1, mockItem2, mockItem3].map { $0 as ICCameraItem }

    let result = groupRelatedCameraItems(mockCameraItems)

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].originalItem.name!, "IMG_1234.JPG")
    XCTAssertNotNil(result[0].editedItem)
    XCTAssertEqual(result[0].editedItem!.name!, "IMG_1234 (Edited).JPG")
    XCTAssertNotNil(result[0].liveItem)
    XCTAssertEqual(result[0].liveItem!.name!, "IMG_1234.MOV")
  }

  func testGroupRelatedURLs() throws {
    // Create temporary directory for test files
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let today = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    // Create test image files
    let imageURL1 = tempDir.appendingPathComponent("IMG_1234.JPG")
    let imageURL2 = tempDir.appendingPathComponent("IMG_1234 (Edited).JPG")
    let videoURL1 = tempDir.appendingPathComponent("IMG_1234.MOV")
    let imageURL3 = tempDir.appendingPathComponent("IMG_5555.JPG")

    // Write empty files (just for testing grouping logic)
    try? Data().write(to: imageURL1)
    try? Data().write(to: imageURL2)
    try? Data().write(to: videoURL1)
    try? Data().write(to: imageURL3)

    // Set creation dates
    try (imageURL1 as NSURL).setResourceValue(today, forKey: .creationDateKey)
    try (imageURL2 as NSURL).setResourceValue(today, forKey: .creationDateKey)
    try (videoURL1 as NSURL).setResourceValue(today, forKey: .creationDateKey)
    try (imageURL3 as NSURL).setResourceValue(yesterday, forKey: .creationDateKey)

    let testURLs = [imageURL1, imageURL2, videoURL1, imageURL3]

    let result = groupRelatedURLs(testURLs)

    XCTAssertEqual(result.count, 2)

    // Check first group (today's files)
    let todayGroup = result.first { $0.originalUrl.lastPathComponent == "IMG_1234.JPG" }
    XCTAssertNotNil(todayGroup)
    XCTAssertEqual(todayGroup?.originalUrl, imageURL1)
    XCTAssertEqual(todayGroup?.editedUrl?.lastPathComponent, "IMG_1234 (Edited).JPG")
    XCTAssertEqual(todayGroup?.liveUrl?.lastPathComponent, "IMG_1234.MOV")

    // Check second group (yesterday's file)
    let yesterdayGroup = result.first { $0.originalUrl.lastPathComponent == "IMG_5555.JPG" }
    XCTAssertNotNil(yesterdayGroup)
    XCTAssertEqual(yesterdayGroup?.originalUrl, imageURL3)
    XCTAssertNil(yesterdayGroup?.editedUrl)
    XCTAssertNil(yesterdayGroup?.liveUrl)
  }

  func testGroupRelatedApplePhotoItems() throws {
    let today = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    // Create MediaSource instances with forApplePhotos flag
    let uuid1_heic = MediaSource(
      date: today,
      name: "C1B92E12-56C5-46A8-9DD7-807F54F01AF3.jpeg",
      uti: "public.image",
      forApplePhotos: true
    )

    let uuid1_mov = MediaSource(
      date: today,
      name: "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_3.mov",
      uti: "public.video",
      forApplePhotos: true
    )

    let uuid2_heic = MediaSource(
      date: today,
      name: "D2A81C33-5B9C-4D3A-9E8F-123456789ABC.jpeg",
      uti: "public.image",
      forApplePhotos: true
    )

    let uuid3_heic_yesterday = MediaSource(
      date: yesterday,
      name: "E3B92D44-6C0B-4E1B-8F2A-987654321DEF.jpeg",
      uti: "public.image",
      forApplePhotos: true
    )

    let uuid3_heic_today = MediaSource(
      date: today,
      name: "E3B92D44-6C0B-4E1B-8F2A-987654321DEF.jpeg",
      uti: "public.image",
      forApplePhotos: true
    )

    // Test case 1: Live photo grouping (HEIC + MOV with same UUID)
    let livePhotoItems: [MediaSource] = [uuid1_heic, uuid1_mov]
    let result1 = groupRelatedMedia(livePhotoItems)

    XCTAssertEqual(result1.count, 1)
    XCTAssertEqual(result1[0].main.fullName, uuid1_heic.fullName)
    XCTAssertNotNil(result1[0].live)
    XCTAssertEqual(result1[0].live!.fullName, uuid1_mov.fullName)

    // Test case 2: Separate Apple Photos items (different UUIDs)
    let separateItems: [MediaSource] = [uuid1_heic, uuid2_heic]
    let result2 = groupRelatedMedia(separateItems)

    XCTAssertEqual(result2.count, 2)
    XCTAssertTrue(result2.contains { $0.main.fullName == uuid1_heic.fullName })
    XCTAssertTrue(result2.contains { $0.main.fullName == uuid2_heic.fullName })

    // Test case 3: Same filename, different dates (should be separate groups)
    let sameNameDifferentDates: [MediaSource] = [uuid3_heic_yesterday, uuid3_heic_today]
    let result3 = groupRelatedMedia(sameNameDifferentDates)

    XCTAssertEqual(result3.count, 2)
    // Both should have same baseName but different dates
    XCTAssertEqual(result3[0].main.baseName, result3[1].main.baseName)

    // Test case 4: Complex grouping with multiple items
    let complexItems: [MediaSource] = [uuid1_heic, uuid1_mov, uuid2_heic]
    let result4 = groupRelatedMedia(complexItems)

    XCTAssertEqual(result4.count, 2)
    // First group should be live photo (HEIC + MOV)
    let liveGroup = result4.first { $0.main.fullName == uuid1_heic.fullName }
    XCTAssertNotNil(liveGroup?.live)
    XCTAssertEqual(liveGroup!.live!.fullName, uuid1_mov.fullName)
    // Second group should be single photo
    let photoGroup = result4.first { $0.main.fullName == uuid2_heic.fullName }
    XCTAssertNil(photoGroup?.live)
  }

  func testApplePhotosBaseNameConsistency() throws {
    // Test that extractApplePhotosBaseName() produces consistent results for grouping
    let testFilenames = [
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3.jpeg",
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_3.mov",
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_12.HEIC",
      "IMG_1234.HEIC",
      "IMG_1234_1.HEIC",
      "IMG_1234_12.HEIC",
    ]

    // Group by extractApplePhotosBaseName()
    var grouped: [String: [String]] = [:]
    for filename in testFilenames {
      let baseName = filename.extractApplePhotosBaseName()
      if grouped[baseName] == nil {
        grouped[baseName] = []
      }
      grouped[baseName]?.append(filename)
    }

    // Verify expected groupings
    XCTAssertEqual(grouped["C1B92E12-56C5-46A8-9DD7-807F54F01AF3"]?.count, 3)
    XCTAssertEqual(grouped["IMG_1234"]?.count, 3)
    XCTAssertEqual(grouped.count, 2)

    // Verify all files in same group share same base name
    for (baseName, filenames) in grouped {
      for filename in filenames {
        XCTAssertEqual(
          filename.extractApplePhotosBaseName(),
          baseName,
          "\(filename) should group to \(baseName)"
        )
      }
    }
  }
}
