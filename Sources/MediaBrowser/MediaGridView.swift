import SwiftUI

struct MediaGridView: View {
  @ObservedObject private var mediaScanner = MediaScanner.shared
  @Binding var selectedItem: MediaItem?
  @Binding var lightboxItemId: Int?
  @Binding var searchQuery: String

  @State private var scrollTarget: Int? = nil
  @State private var scrollAnchor: UnitPoint = .center

  private var sortedItems: [MediaItem] {
    let filteredItems =
      searchQuery.isEmpty
      ? mediaScanner.items
      : mediaScanner.items.filter { item in
        return item.displayName.localizedCaseInsensitiveContains(searchQuery)
      }

    return filteredItems.sorted { item1, item2 in
      let date1 = item1.metadata?.creationDate ?? Date.distantPast
      let date2 = item2.metadata?.creationDate ?? Date.distantPast
      return date1 > date2  // Most recent first
    }
  }

  private var monthlyGroups: [(month: String, items: [MediaItem])] {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"

    let grouped = Dictionary(grouping: sortedItems) { item in
      guard let date = item.metadata?.creationDate else {
        return "Unknown"
      }
      return formatter.string(from: date)
    }

    return grouped.map { (month: $0.key, items: $0.value) }
      .sorted { group1, group2 in
        // Sort by the earliest date in each group for chronological order
        let date1 = group1.items.first?.metadata?.creationDate ?? Date.distantPast
        let date2 = group2.items.first?.metadata?.creationDate ?? Date.distantPast
        return date1 > date2  // Most recent first (descending)
      }
  }

  var body: some View {
    GeometryReader { geo in
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(monthlyGroups, id: \.month) { group in
            SectionGridView(
              title: group.month,
              items: group.items,
              selectedItem: $selectedItem,
              onItemTap: { item in
                selectedItem = item
                lightboxItemId = item.id
              },
              minCellWidth: 80
            )
          }
        }
        .padding(.bottom, 8)
      }
      .scrollPosition(id: $scrollTarget, anchor: scrollAnchor)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .focusable()
      .onKeyPress { press in
        // Update window width for dynamic column calculation
        let windowWidth = geo.size.width
        // Grid navigation when lightbox is not open
        if lightboxItemId == nil,
          let currentIndex = sortedItems.firstIndex(where: { $0.id == selectedItem?.id })
        {
          let availableWidth = windowWidth - 16  // subtract horizontal padding
          let columns = max(1, Int(floor((availableWidth + 10) / 90)))  // spacing = 10, minWidth = 80
          let currentRow = currentIndex / columns
          let currentCol = currentIndex % columns

          var newRow = currentRow
          var newCol = currentCol

          switch press.key {
          case .upArrow:
            newRow = max(0, currentRow - 1)
          case .downArrow:
            newRow = min((sortedItems.count + columns - 1) / columns - 1, currentRow + 1)
          case .leftArrow:
            if currentCol == 0 && currentRow > 0 {
              // Wrap to previous row's last column
              newRow = currentRow - 1
              newCol = min(columns - 1, sortedItems.count - newRow * columns - 1)
            } else {
              newCol = max(0, currentCol - 1)
            }
          case .rightArrow:
            let maxColInRow = min(columns - 1, sortedItems.count - currentRow * columns - 1)
            if currentCol == maxColInRow
              && currentRow < (sortedItems.count + columns - 1) / columns - 1
            {
              // Wrap to next row's first column
              newRow = currentRow + 1
              newCol = 0
            } else {
              newCol = min(maxColInRow, currentCol + 1)
            }
          case .space, .return:
            if let item = selectedItem {
              lightboxItemId = item.id
            }
            return .handled
          default:
            return .ignored
          }

          let newIndex = newRow * columns + newCol
          if newIndex < sortedItems.count {
            selectedItem = sortedItems[newIndex]

            // Calculate total rows and visible rows to determine optimal anchor
            let totalRows = (sortedItems.count + columns - 1) / columns
            let estimatedItemHeight: CGFloat = 90  // Approximate height of grid item
            let estimatedHeaderHeight: CGFloat = 40  // Approximate height of section headers
            let visibleRows = Int(
              (geo.size.height - estimatedHeaderHeight) / (estimatedItemHeight + 16))  // 16 is spacing

            // Determine anchor based on position
            if newRow <= visibleRows / 3 {
              // Top third - anchor to top
              scrollAnchor = .top
            } else if newRow >= totalRows - visibleRows / 3 {
              // Bottom third - anchor to bottom
              scrollAnchor = .bottom
            } else {
              // Middle - center
              scrollAnchor = .center
            }
            scrollTarget = selectedItem?.id
          }
          return .handled
        }
        return .ignored
      }
    }
  }
}
