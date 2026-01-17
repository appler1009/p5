import XCTest

@testable import MediaBrowser

@MainActor final class DatabaseManagerTests: XCTestCase {
  func testDatabaseInsertAndRetrieve() throws {
    // Initialize shared instances
    let dbPath = DatabaseManager.defaultPath
    let databaseManager = DatabaseManager(path: dbPath)
    DatabaseManager.shared = databaseManager

    // Test database operations
    let db = DatabaseManager.shared!

    // Clear DB first
    db.clearAll()

    let url = URL(fileURLWithPath: "/test/photo.jpg")
    let metadata = MediaMetadata(
      creationDate: Date(),
      modificationDate: Date(),
      dimensions: CGSize(width: 1920, height: 1080),
      exifDate: Date(),
      gps: GPSLocation(latitude: 37.7749, longitude: -122.4194),
      duration: 60.0,
      make: "Test",
      model: "Test",
      lens: nil,
      iso: 100,
      aperture: 2.8,
      shutterSpeed: "1/100",
      extraEXIF: [:]
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
}
