import SwiftUI

struct MediaGridView: View {
  @ObservedObject private var mediaScanner = MediaScanner.shared
  let searchQuery: String
  let onSelected: (Set<MediaItem>) -> Void
  let onFullScreen: (MediaItem) -> Void
  @ObservedObject var selectionState: GridSelectionState

  @State private var scrollTarget: Int? = nil
  @State private var scrollAnchor: UnitPoint = .center
  @State private var sectionUpdateClosures: [String: (Set<MediaItem>) -> Void] = [:]

  @FocusState private var isGridFocused: Bool

  private let lightboxOpeningDelay = 0.1

  init(
    searchQuery: String,
    onSelected: @escaping (Set<MediaItem>) -> Void,
    onFullScreen: @escaping (MediaItem) -> Void,
    selectionState: GridSelectionState
  ) {
    self.searchQuery = searchQuery
    self.onSelected = onSelected
    self.onFullScreen = onFullScreen
    self.selectionState = selectionState
  }

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
              selectedItems: selectionState.selectedItems,
              onSelectionChange: { newSelectedItems in
                selectionState.selectedItems = newSelectedItems
                onSelected(newSelectedItems)
              },
              onItemDoubleTap: { item in
                withAnimation(.easeInOut(duration: lightboxOpeningDelay)) {
                  onFullScreen(item)
                }
              },
              minCellWidth: 80,
              selectionState: selectionState
            )
            .id(group.month)
          }
        }
        .padding(.bottom, 8)
      }
      .scrollPosition(id: $scrollTarget, anchor: scrollAnchor)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .focusable()
      .focused($isGridFocused)
      .onAppear {
        isGridFocused = true
      }
      .onKeyPress { press in
        let windowWidth = geo.size.width

        if selectionState.selectedItems.count == 1,
          let firstSelectedItem = selectionState.selectedItems.first,
          let currentIndex = sortedItems.firstIndex(where: { $0.id == firstSelectedItem.id })
        {
          let availableWidth = windowWidth - 16
          let columns = max(1, Int(floor((availableWidth + 10) / 90)))
          let currentRow = currentIndex / columns
          let currentCol = currentIndex % columns

          var newRow = currentRow
          let newCol = currentCol
          let newIndex: Int

          switch press.key {
          case .upArrow:
            newRow = max(0, currentRow - 1)
            let upIndex = newRow * columns + currentCol
            if upIndex < sortedItems.count {
              let newItem = sortedItems[upIndex]
              DispatchQueue.main.async {
                selectionState.selectedItems = [newItem]
              }
              onSelected([newItem])
            }
            return .handled
          case .downArrow:
            newRow = min((sortedItems.count + columns - 1) / columns - 1, currentRow + 1)
            let downIndex = newRow * columns + currentCol
            if downIndex < sortedItems.count {
              let newItem = sortedItems[downIndex]
              DispatchQueue.main.async {
                selectionState.selectedItems = [newItem]
              }
              onSelected([newItem])
            }
            return .handled
          case .leftArrow:
            newIndex = max(currentIndex - 1, 0)
            let newItem = sortedItems[newIndex]
            DispatchQueue.main.async {
              selectionState.selectedItems = [newItem]
            }
            onSelected([newItem])
            return .handled
          case .rightArrow:
            newIndex = min(currentIndex + 1, sortedItems.count - 1)
            let newItem = sortedItems[newIndex]
            DispatchQueue.main.async {
              selectionState.selectedItems = [newItem]
            }
            onSelected([newItem])
            return .handled
          case .space, .return:
            if let item = selectionState.selectedItems.first {
              withAnimation(.easeInOut(duration: lightboxOpeningDelay)) {
                onFullScreen(item)
              }
            }
            return .handled
          default:
            return .ignored
          }
        }
        return .ignored
      }
    }
  }
}
