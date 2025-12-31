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
}
