import SwiftUI

struct MediaGridView: View {
  @ObservedObject private var mediaScanner = MediaScanner.shared
  let searchQuery: String
  let onSelected: (Set<MediaItem>) -> Void
  let onFullScreen: (MediaItem) -> Void

  @StateObject private var selectionState = GridSelectionState()
  @State private var selectedItems: Set<MediaItem> = Set()
  @State private var scrollTarget: Int? = nil
  @State private var scrollAnchor: UnitPoint = .center
  @State private var sectionUpdateClosures: [String: (Set<MediaItem>) -> Void] = [:]
  @State private var notificationObserver: NSObjectProtocol?

  @FocusState private var isGridFocused: Bool

  private let lightboxOpeningDelay = 0.1

  init(
    searchQuery: String,
    onSelected: @escaping (Set<MediaItem>) -> Void,
    onFullScreen: @escaping (MediaItem) -> Void,
    updateSelectionFromOutside: Binding<((MediaItem) -> Void)?> = .constant(nil)
  ) {
    self.searchQuery = searchQuery
    self.onSelected = onSelected
    self.onFullScreen = onFullScreen
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
              selectedItems: selectedItems,
              onSelectionChange: { newSelectedItems in
                selectedItems = newSelectedItems
                selectionState.selectedItems = newSelectedItems
                onSelected(newSelectedItems)
                if let firstSelectedItem = selectedItems.first,
                  let currentIndex = sortedItems.firstIndex(where: { $0.id == firstSelectedItem.id })
                {
                  print("currentIndex \(currentIndex) \(firstSelectedItem.displayName)")
                }
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
        notificationObserver = NotificationCenter.default.addObserver(
          forName: .mediaGridSelectItem,
          object: nil,
          queue: .main
        ) { notification in
          if let item = notification.userInfo?["item"] as? MediaItem {
            self.selectItem(item)
          }
        }
      }
      .onDisappear {
        if let observer = notificationObserver {
          NotificationCenter.default.removeObserver(observer)
          notificationObserver = nil
        }
      }
      .onKeyPress { press in
        // Update window width for dynamic column calculation
        let windowWidth = geo.size.width

        // Grid navigation when lightbox is not open
        print("\(sortedItems.count), \(selectedItems.count)")
        selectedItems.forEach({ body in print("\(body.displayName)")})
        if selectedItems.count == 1,
          let firstSelectedItem = selectedItems.first,
          let currentIndex = sortedItems.firstIndex(where: { $0.id == firstSelectedItem.id })
        {
          print("currentIndex \(currentIndex) \(firstSelectedItem.displayName)")
          let availableWidth = windowWidth - 16  // subtract horizontal padding
          let columns = max(1, Int(floor((availableWidth + 10) / 90)))  // spacing = 10, minWidth = 80
          let currentRow = currentIndex / columns
          let currentCol = currentIndex % columns

          var newRow = currentRow
          var newCol = currentCol
          var newIndex = 0

          switch press.key {
          case .upArrow:
            newRow = max(0, currentRow - 1)
          case .downArrow:
            newRow = min((sortedItems.count + columns - 1) / columns - 1, currentRow + 1)
          case .leftArrow:
            newIndex = max(currentIndex - 1, 0)
            selectedItems = [sortedItems[newIndex]]
            DispatchQueue.main.async {
              selectionState.selectedItems = selectedItems
            }
            onSelected(selectedItems)
            return .handled
          case .rightArrow:
            newIndex = min(currentIndex + 1, sortedItems.count - 1)
            selectedItems = [sortedItems[newIndex]]
            DispatchQueue.main.async {
              selectionState.selectedItems = selectedItems
            }
            onSelected(selectedItems)
            return .handled
          case .space, .return:
            if let item = selectedItems.first {
              withAnimation(.easeInOut(duration: lightboxOpeningDelay)) {
                onFullScreen(item)
              }
            }
            return .handled
          default:
            return .ignored
          }

            // Determine anchor based on position
//            if newRow <= visibleRows / 3 {
//              // Top third - anchor to top
//              scrollAnchor = .top
//            } else if newRow >= totalRows - visibleRows / 3 {
//              // Bottom third - anchor to bottom
//              scrollAnchor = .bottom
//            } else {
//              // Middle - center
//              scrollAnchor = .center
//            }
//            scrollTarget = selectedItems.first?.id
        }
        return .ignored
      }
    }
  }

  func selectItem(_ item: MediaItem) {
    selectedItems = [item]
    selectionState.selectedItems = selectedItems
    onSelected(selectedItems)
  }
}
