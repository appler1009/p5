import SwiftUI

struct MediaGridView: View {
  @ObservedObject private var mediaScanner = MediaScanner.shared
  let searchQuery: String
  let onSelected: (Set<MediaItem>) -> Void
  let onFullScreen: (MediaItem) -> Void
  let onScrollToItem: ((Int) -> Void)?
  @ObservedObject var selectionState: GridSelectionState

  @State private var scrollTarget: Int? = nil
  @State private var scrollAnchor: UnitPoint = .center
  @State private var sectionUpdateClosures: [String: (Set<MediaItem>) -> Void] = [:]
  @State private var visibleItemIds: Set<Int> = Set()

  private let lightboxOpeningDelay = 0.1

  init(
    searchQuery: String,
    onSelected: @escaping (Set<MediaItem>) -> Void,
    onFullScreen: @escaping (MediaItem) -> Void,
    selectionState: GridSelectionState,
    onScrollToItem: ((Int) -> Void)? = nil
  ) {
    self.searchQuery = searchQuery
    self.onSelected = onSelected
    self.onFullScreen = onFullScreen
    self.onScrollToItem = onScrollToItem
    self.selectionState = selectionState
  }

  private var sortedItems: [MediaItem] {
    let allItems = mediaScanner.items
    let filteredItems =
      searchQuery.isEmpty
      ? allItems
      : allItems.filter { item in
        // Search in filename
        if item.displayName.localizedCaseInsensitiveContains(searchQuery) {
          return true
        }

        // Search in file extension (without dot)
        let fileExtension = (item.displayName as NSString).pathExtension.lowercased()
        if fileExtension.localizedCaseInsensitiveContains(searchQuery) {
          return true
        }

        // Search in camera make
        if let make = item.metadata?.make,
          make.localizedCaseInsensitiveContains(searchQuery)
        {
          return true
        }

        // Search in camera model
        if let model = item.metadata?.model,
          model.localizedCaseInsensitiveContains(searchQuery)
        {
          return true
        }

        return false
      }

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
          ForEach(monthlyGroups, id: \.month) { group in
            SectionGridView(
              title: group.month,
              items: group.items,
              selectedItems: selectionState.selectedItems,
              onSelectionChange: { newSelectedItems in
                selectionState.selectedItems = newSelectedItems
                onSelected(newSelectedItems)
                handleSelectionScroll(newSelectedItems, proxy: proxy)
              },
              onItemDoubleTap: { item in
                withAnimation(.easeInOut(duration: lightboxOpeningDelay)) {
                  onFullScreen(item)
                }
              },
              minCellWidth: 80,
              selectionState: selectionState,
              onItemAppearanceChange: changedItemAppearance
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
      .scrollPosition(id: $scrollTarget, anchor: scrollAnchor)
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
