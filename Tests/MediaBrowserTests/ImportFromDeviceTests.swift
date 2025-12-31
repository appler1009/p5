import XCTest

@testable import MediaBrowser

final class ImportFromDeviceTests: XCTestCase {
  func testGroupRelatedMedia() throws {
    // Create a mock ImportFromDevice to access the private method
    let importFromDevice = ImportFromDevice()

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
}
