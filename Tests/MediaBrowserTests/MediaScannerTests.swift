import XCTest

@testable import MediaBrowser

final class MediaScannerTests: XCTestCase {

  @MainActor func testMediaScannerIsEdited() throws {
    // Initialize shared instances
    let dbPath = DatabaseManager.defaultPath
    let databaseManager = DatabaseManager(path: dbPath)
    DatabaseManager.shared = databaseManager
    MediaScanner.shared = MediaScanner(databaseManager: databaseManager)

    let scanner = MediaScanner.shared!

    // Test original "E" naming scheme
    XCTAssertTrue(scanner.isEdited(base: "IMG_E1234"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_1234"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_1234E"))

    // Test new "_Edited" naming scheme
    XCTAssertTrue(scanner.isEdited(base: "IMG_1234_Edited"))
    XCTAssertTrue(scanner.isEdited(base: "DSC_0001_Edited"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_1234"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_Edited"))
  }

  @MainActor func testMediaScannerScan() async throws {
    // Initialize shared instances
    let dbPath = DatabaseManager.defaultPath
    let databaseManager = DatabaseManager(path: dbPath)
    let directoryManager = DirectoryManager(databaseManager: databaseManager)
    DatabaseManager.shared = databaseManager
    MediaScanner.shared = MediaScanner(databaseManager: databaseManager)
    DirectoryManager.shared = directoryManager

    let scanner = MediaScanner.shared!
    // Mock import directory to a non-existent path
    let originalCustom = DirectoryManager.shared!.customImportDirectory
    defer { DirectoryManager.shared!.customImportDirectory = originalCustom }
    DirectoryManager.shared!.customImportDirectory = URL(fileURLWithPath: "/nonexistent_import")
    DirectoryManager.shared!.directoryStates = []
    // Test scan with empty directories (no file system access)
    await scanner.scan(directories: [])
    XCTAssertEqual(scanner.items.count, 0)
  }

  @MainActor func testMediaScannerCountItems() async throws {
    // Initialize shared instances
    let dbPath = DatabaseManager.defaultPath
    let databaseManager = DatabaseManager(path: dbPath)
    DatabaseManager.shared = databaseManager
    MediaScanner.shared = MediaScanner(databaseManager: databaseManager)

    let scanner = MediaScanner.shared!
    let nonExistentURL = URL(fileURLWithPath: "/nonexistent")
    let count = await scanner.countItems(in: nonExistentURL)
    XCTAssertEqual(count, 0)
  }

  @MainActor func testMediaScannerScanDirectory() async throws {
    // Create a fresh scanner instance for this test (don't contaminate shared state)
    let dbPath = DatabaseManager.defaultPath
    let databaseManager = DatabaseManager(path: dbPath)
    databaseManager.clearAll()  // Clear any leftover data from previous tests
    let scanner = MediaScanner(databaseManager: databaseManager)

    let nonExistentURL = URL(fileURLWithPath: "/definitely/does/not/exist/no/way/this/exists")
    // Before
    let before = scanner.items.count
    await scanner.scanDirectory(nonExistentURL)
    // After - should not have added any items
    let after = scanner.items.count
    if after > before {
      print("Unexpected items found: \(scanner.items)")
    }
    XCTAssertEqual(after, before, "Scanning non-existent directory should not add items")
  }
}
