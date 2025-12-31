import XCTest

@testable import MediaBrowser

final class MediaScannerTests: XCTestCase {
  func testMediaScannerIsEdited() throws {
    let scanner = MediaScanner.shared
    XCTAssertTrue(scanner.isEdited(base: "IMG_E1234"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_1234"))
    XCTAssertFalse(scanner.isEdited(base: "IMG_1234E"))
  }

  func testMediaScannerScan() async throws {
    let scanner = MediaScanner.shared
    // Test scan with empty directories (no file system access)
    await scanner.scan(directories: [])
    XCTAssertEqual(scanner.items.count, 0)
  }

  func testMediaScannerCountItems() async throws {
    let scanner = MediaScanner.shared
    let nonExistentURL = URL(fileURLWithPath: "/nonexistent")
    let count = await scanner.countItems(in: nonExistentURL)
    XCTAssertEqual(count, 0)
  }

  func testMediaScannerScanDirectory() async throws {
    let scanner = MediaScanner.shared
    let nonExistentURL = URL(fileURLWithPath: "/nonexistent")
    // Before
    let before = scanner.items.count
    await scanner.scanDirectory(nonExistentURL)
    // After, should be same
    XCTAssertEqual(scanner.items.count, before)
  }
}
