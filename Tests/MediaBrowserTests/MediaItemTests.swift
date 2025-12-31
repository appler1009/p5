import XCTest

@testable import MediaBrowser

final class MediaItemTests: XCTestCase {
  func testExample() throws {
    // Test something simple
    XCTAssertEqual(2 + 2, 4)
  }

  func testMediaItemInit() throws {
    let url = URL(fileURLWithPath: "/test.jpg")
    let item = LocalFileSystemMediaItem(id: 1, original: url)
    XCTAssertEqual(item.originalUrl, url)
    XCTAssertEqual(item.type, MediaType.photo)
  }
}
