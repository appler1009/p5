import SwiftUI

struct MediaGridView: View {
  @ObservedObject var mediaScanner: MediaScanner
  let databaseManager: DatabaseManager
  let searchQuery: String
  let onSelected: (Set<MediaItem>) -> Void
  let onFullScreen: (MediaItem) -> Void
  let onScrollToItem: ((Int) -> Void)?
  @ObservedObject var selectionState: GridSelectionState

  private let lightboxOpeningDelay = 0.1

  @State private var sectionUpdateClosures: [String: (Set<MediaItem>) -> Void] = [:]
  @State private var visibleItemIds: Set<Int> = []
  @State private var itemsWithGPS: [LocalFileSystemMediaItem] = []

  private var sortedItems: [MediaItem] {
    let allItems = mediaScanner.items
    let filteredItems =
      searchQuery.isEmpty
      ? allItems
      : allItems.filter { $0.matchesSearchQuery(searchQuery) }

    return filteredItems.sorted { item1, item2 in
      let date1 = item1.metadata?.creationDate ?? Date.distantPast
      let date2 = item2.metadata?.creationDate ?? Date.distantPast
      return date1 > date2
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
        return date1 > date2
      }
  }

  var body: some View {
    ScrollView {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 16) {
          ForEach(self.monthlyGroups, id: \.month) { group in
            SectionGridView(
              title: group.month,
              items: group.items,
              selectedItems: self.selectionState.selectedItems,
              onSelectionChange: { newSelectedItems in
                self.selectionState.selectedItems = newSelectedItems
                self.onSelected(newSelectedItems)
                self.handleSelectionScroll(newSelectedItems, proxy: proxy)
              },
              onItemDoubleTap: { item in
                withAnimation(.easeInOut(duration: 0.1)) {
                  self.onFullScreen(item)
                }
              },
              minCellWidth: 80,
              selectionState: self.selectionState,
              onItemAppearanceChange: self.changedItemAppearance
            )
            .id(group.month)
          }
        }
        .padding(.bottom, 8)
        .onChange(of: selectionState.lastSelectedByKeyboard) { _, newValue in
          if let item = newValue {
            withAnimation(.easeInOut(duration: 0.1)) {
              proxy.scrollTo("item-\(item.id)", anchor: .center)
            }
          }
        }
        .onChange(of: selectionState.scrollToItem) { _, newValue in
          if let item = newValue {
            withAnimation(.easeInOut(duration: 0.1)) {
              proxy.scrollTo("item-\(item.id)", anchor: .center)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func changedItemAppearance(itemId: Int, visible: Bool) {
    if visible {
      visibleItemIds.insert(itemId)
    } else {
      visibleItemIds.remove(itemId)
    }
  }

  private func handleSelectionScroll(_ newSelectedItems: Set<MediaItem>, proxy: ScrollViewProxy) {
    guard let selectedFirst = newSelectedItems.first else { return }

    if visibleItemIds.contains(selectedFirst.id) {
      return
    }

    withAnimation(.easeInOut(duration: 0.1)) {
      proxy.scrollTo("item-\(selectedFirst.id)", anchor: .center)
    }
  }
}

struct NoFocusRingView: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.focusRingType = .none
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    nsView.focusRingType = .none
  }
}
