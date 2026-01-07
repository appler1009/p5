import XCTest

@testable import MediaBrowser

final class ToolsTests: XCTestCase {
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

  func testExtractApplePhotosBaseName() throws {
    // Test case 1: UUID-based filename with HEIC extension
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3.jpeg".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3"
    )
    // Test case 2: UUID-based filename with MOV extension and sequence suffix
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_3.mov".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3"
    )
    // Test case 3: UUID with single digit sequence
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_1.HEIC".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3"
    )
    // Test case 4: UUID with two digit sequence
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_12.HEIC".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3"
    )
    // Test case 5: UUID with camera variant suffix (should NOT be removed)
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_L.HEIC".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_L"
    )
    // Test case 6: UUID with E suffix (should NOT be removed)
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3E.HEIC".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3E"
    )
    // Test case 7: Standard filename without sequence
    XCTAssertEqual(
      "IMG_1234.HEIC".extractApplePhotosBaseName(),
      "IMG_1234"
    )
    // Test case 8: Standard filename with sequence
    XCTAssertEqual(
      "IMG_1234_3.HEIC".extractApplePhotosBaseName(),
      "IMG_1234"
    )
    // Test case 9: No extension (with sequence)
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_4".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3"
    )
    // Test case 10: No extension (without sequence)
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3"
    )
    // Test case 11: Filename with no sequence (should return unchanged)
    XCTAssertEqual(
      "test_file.HEIC".extractApplePhotosBaseName(),
      "test_file"
    )
    // Test case 12: Mixed case extension
    XCTAssertEqual(
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3_2.JPEG".extractApplePhotosBaseName(),
      "C1B92E12-56C5-46A8-9DD7-807F54F01AF3"
    )
  }
}
