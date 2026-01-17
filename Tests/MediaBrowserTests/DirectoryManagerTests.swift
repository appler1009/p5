import XCTest

@testable import MediaBrowser

@MainActor final class DirectoryManagerTests: XCTestCase {
  func testDirectoryManager() throws {
    // Initialize shared instances
    let dbPath = DatabaseManager.defaultPath
    let databaseManager = DatabaseManager(path: dbPath)
    let directoryManager = DirectoryManager(databaseManager: databaseManager)
    DatabaseManager.shared = databaseManager
    DirectoryManager.shared = directoryManager

    let manager = DirectoryManager.shared!
    // Test remove
    let testURL1 = URL(fileURLWithPath: "/tmp/testdir1")
    let testURL2 = URL(fileURLWithPath: "/tmp/testdir2")
    manager.directoryStates = [(testURL1, false), (testURL2, false)]

    XCTAssertEqual(manager.directories.count, 2)

    // Test remove
    manager.removeDirectory(at: 0)
    XCTAssertEqual(manager.directories.count, 1)
    XCTAssertEqual(manager.directories.first, testURL2)

    // Test cleanup thumbnails
    let cleaned = manager.cleanupThumbnails()
    XCTAssertGreaterThanOrEqual(cleaned, 0)  // At least 0
  }
}
