import XCTest

@testable import MediaBrowser

final class ThumbnailCacheTests: XCTestCase {
  @MainActor func testThumbnailCache() async throws {
    let cache = ThumbnailCache.shared
    let testItem = LocalFileSystemMediaItem(
      id: 1, original: URL(fileURLWithPath: "/nonexistent.jpg"))
    let image = cache.thumbnail(mediaItem: testItem)
    XCTAssertNil(image)  // Since file doesn't exist
  }
}
