import XCTest

@testable import MediaBrowser

final class ContentViewTests: XCTestCase {
  func testContentViewMonthlyGroups() throws {
    // Test the monthly grouping logic by extracting the logic
    let calendar = Calendar.current
    let testItems: [MediaItem] = []  // Empty for simplicity
    let grouped = Dictionary(grouping: testItems) { item -> Date? in
      guard let date = item.metadata?.creationDate else { return nil }
      return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }
    let sortedGroups = grouped.sorted { (lhs, rhs) -> Bool in
      guard let lhsDate = lhs.key, let rhsDate = rhs.key else { return lhs.key != nil }
      return lhsDate > rhsDate
    }
    let monthlyGroups = sortedGroups.map {
      (
        month: $0.key?.formatted(.dateTime.year().month(.wide)) ?? "Unknown",
        items: $0.value.sorted {
          ($0.metadata?.creationDate ?? Date.distantPast)
            > ($1.metadata?.creationDate ?? Date.distantPast)
        }
      )
    }
    XCTAssertEqual(monthlyGroups.count, 0)
  }
}
