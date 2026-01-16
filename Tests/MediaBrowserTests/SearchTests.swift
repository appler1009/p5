import XCTest

@testable import MediaBrowser

final class SearchTests: XCTestCase {

  // Create a mock media item for testing
  private func createMockItem(displayName: String, make: String?, model: String?)
    -> LocalFileSystemMediaItem
  {
    let item = LocalFileSystemMediaItem(
      id: 1,
      original: URL(fileURLWithPath: "/test/\(displayName)")
    )
    if make != nil || model != nil {
      item.metadata = MediaMetadata(
        creationDate: Date(),
        modificationDate: nil,
        dimensions: nil,
        exifDate: nil,
        gps: nil,
        duration: nil,
        make: make,
        model: model,
        lens: nil,
        iso: nil,
        aperture: nil,
        shutterSpeed: nil,
        extraEXIF: [:]
      )
    }
    return item
  }

  func testSearchByFilename() {
    let item1 = createMockItem(displayName: "vacation_canon.jpg", make: "Canon", model: "EOS R5")
    let item2 = createMockItem(displayName: "portrait.jpg", make: "Apple", model: "iPhone")

    XCTAssertTrue(item1.matchesSearchQuery("vacation"))
    XCTAssertFalse(item2.matchesSearchQuery("vacation"))
  }

  func testSearchByCameraMake() {
    let item1 = createMockItem(displayName: "photo.jpg", make: "Canon", model: "EOS R5")
    let item2 = createMockItem(displayName: "photo.jpg", make: "Apple", model: "iPhone")

    XCTAssertTrue(item1.matchesSearchQuery("canon"))
    XCTAssertTrue(item1.matchesSearchQuery("CANON"))
    XCTAssertFalse(item2.matchesSearchQuery("canon"))
  }

  func testSearchByCameraModel() {
    let item1 = createMockItem(displayName: "photo.jpg", make: "Apple", model: "iPhone 15 Pro")
    let item2 = createMockItem(displayName: "photo.jpg", make: "Canon", model: "EOS R5")

    XCTAssertTrue(item1.matchesSearchQuery("iPhone"))
    XCTAssertTrue(item1.matchesSearchQuery("15"))
    XCTAssertFalse(item2.matchesSearchQuery("iPhone"))
  }

  func testSearchByFileExtension() {
    let item1 = createMockItem(displayName: "vacation_canon.jpg", make: "Canon", model: "EOS R5")
    let item2 = createMockItem(displayName: "portrait_iphone.heic", make: "Apple", model: "iPhone")
    let item3 = createMockItem(displayName: "video.mp4", make: nil, model: nil)

    XCTAssertTrue(item1.matchesSearchQuery("jpg"))
    XCTAssertTrue(item2.matchesSearchQuery("heic"))
    XCTAssertFalse(item3.matchesSearchQuery("jpg"))
  }

  func testSearchMultipleMatches() {
    // Filename contains "photo"
    let item1 = createMockItem(displayName: "vacation_photo.jpg", make: "Canon", model: "EOS R5")
    // Model contains "iPhone"
    let item2 = createMockItem(displayName: "portrait.jpg", make: "Apple", model: "iPhone 15 Pro")

    XCTAssertTrue(item1.matchesSearchQuery("photo"))
    XCTAssertTrue(item2.matchesSearchQuery("iPhone"))
  }

  func testSearchNoMatches() {
    let item1 = createMockItem(displayName: "vacation_canon.jpg", make: "Canon", model: "EOS R5")
    let item2 = createMockItem(displayName: "portrait.jpg", make: "Apple", model: "iPhone")

    XCTAssertFalse(item1.matchesSearchQuery("nonexistent"))
    XCTAssertFalse(item2.matchesSearchQuery("nikon"))
  }

  func testSearchCaseInsensitive() {
    let item1 = createMockItem(displayName: "vacation_canon.jpg", make: "Canon", model: "EOS R5")
    let item2 = createMockItem(displayName: "PORTRAIT.JPG", make: "Apple", model: "iPhone")

    XCTAssertTrue(item1.matchesSearchQuery("CANON"))
    XCTAssertTrue(item2.matchesSearchQuery("portrait"))
  }

  func testSearchPartialMatch() {
    let item1 = createMockItem(displayName: "photo.jpg", make: "Canon", model: "EOS R5")
    let item2 = createMockItem(displayName: "photo.jpg", make: "Apple", model: "iPhone 15 Pro")

    XCTAssertTrue(item1.matchesSearchQuery("eos"))
    XCTAssertTrue(item2.matchesSearchQuery("phone"))
  }

  func testSearchEmptyQuery() {
    // Empty query should not match anything in this logic
    // (the actual UI handles empty query by returning all items)
    let item = createMockItem(displayName: "photo.jpg", make: "Canon", model: "EOS R5")
    XCTAssertFalse(item.matchesSearchQuery(""))
  }

  func testSearchVideoExtension() {
    let item = createMockItem(displayName: "video.mp4", make: nil, model: nil)

    XCTAssertTrue(item.matchesSearchQuery("mp4"))
    XCTAssertFalse(item.matchesSearchQuery("avi"))
  }

  func testSearchNEFExtension() {
    let item = createMockItem(displayName: "landscape_nikon.nef", make: "Nikon", model: "D850")

    XCTAssertTrue(item.matchesSearchQuery("nef"))
    XCTAssertFalse(item.matchesSearchQuery("jpg"))
  }

  func testSearchNilMetadata() {
    // Items without metadata should only match on filename/extension
    let item = createMockItem(displayName: "video.mp4", make: nil, model: nil)

    XCTAssertTrue(item.matchesSearchQuery("video"))
    XCTAssertTrue(item.matchesSearchQuery("mp4"))
    XCTAssertFalse(item.matchesSearchQuery("canon"))
  }
}
