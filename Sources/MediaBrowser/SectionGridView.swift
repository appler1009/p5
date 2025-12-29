import SwiftUI

// Simplified version that works specifically with MediaItem and supports multiple selection
struct SectionGridView: View {
  let title: String?
  let items: [MediaItem]
  @Binding var selectedItems: Set<MediaItem>
  let onSelectionChange: (Set<MediaItem>) -> Void
  let onItemDoubleTap: (MediaItem) -> Void
  let minCellWidth: CGFloat

  @State private var itemsNeedingThumbnailUpdate: Set<Int> = []
  @State private var thumbnailObserver: NSObjectProtocol?
  @State private var lastSelectedItem: MediaItem?

  // Default initializer for standard MediaItemView usage with multiple selection
  init(
    title: String? = nil,
    items: [MediaItem],
    selectedItems: Binding<Set<MediaItem>>,
    onSelectionChange: @escaping (Set<MediaItem>) -> Void,
    onItemDoubleTap: @escaping (MediaItem) -> Void,
    minCellWidth: CGFloat = 120
  ) {
    self.title = title
    self.items = items
    self._selectedItems = selectedItems
    self.onSelectionChange = onSelectionChange
    self.onItemDoubleTap = onItemDoubleTap
    self.minCellWidth = minCellWidth
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title = title {
        Text(title)
          .font(.headline)
          .padding(.horizontal)
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: minCellWidth))], spacing: 10) {
        ForEach(items.sorted(by: { $0.thumbnailDate > $1.thumbnailDate })) { item in
          MediaItemView(
            item: item,
            onTap: nil,
            isSelected: selectedItems.contains(item),
            shouldReloadThumbnail: itemsNeedingThumbnailUpdate.contains(item.id)
          )
          .contentShape(Rectangle())
          .onTapGesture {
            handleItemSelection(item)
          }
          .simultaneousGesture(
            TapGesture(count: 2).onEnded { _ in
              onItemDoubleTap(item)
            }
          )
        }
      }
      .padding(.horizontal, 8)
    }
    .onAppear {
      setupThumbnailObserver()
    }
    .onDisappear {
      cleanupThumbnailObserver()
    }
  }

  private func setupThumbnailObserver() {
    thumbnailObserver = NotificationCenter.default.addObserver(
      forName: .thumbnailDidBecomeAvailable,
      object: nil,
      queue: .main
    ) { [self] notification in
      guard let mediaItemId = notification.userInfo?["mediaItemId"] as? Int else {
        return
      }

      // Check if this item is in our current items list
      if self.items.contains(where: { $0.id == mediaItemId }) {
        // Mark this item as needing thumbnail update
        itemsNeedingThumbnailUpdate.insert(mediaItemId)

        // Clear all items after a short delay to allow views to update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          self.itemsNeedingThumbnailUpdate.removeAll()
        }
      }
    }
  }

  private func cleanupThumbnailObserver() {
    if let observer = thumbnailObserver {
      NotificationCenter.default.removeObserver(observer)
      thumbnailObserver = nil
    }
  }

  private func handleItemSelection(_ item: MediaItem) {
    let eventModifierFlags = NSApp.currentEvent?.modifierFlags ?? []

    if eventModifierFlags.contains(.command) {
      // CMD+click: Toggle individual item
      if selectedItems.contains(item) {
        selectedItems.remove(item)
      } else {
        selectedItems.insert(item)
        lastSelectedItem = item
      }
    } else if eventModifierFlags.contains(.shift) {
      // SHIFT+click: Select range from last selected item to current item
      if let lastSelected = lastSelectedItem ?? selectedItems.first {
        selectRange(from: lastSelected, to: item)
      } else {
        // No previous selection, just select this item
        selectedItems = [item]
        lastSelectedItem = item
      }
    } else {
      // Regular click: Select only this item
      selectedItems = [item]
      lastSelectedItem = item
    }

    onSelectionChange(selectedItems)
  }

  private func selectRange(from startItem: MediaItem, to endItem: MediaItem) {
    guard let startIndex = items.firstIndex(where: { $0.id == startItem.id }),
      let endIndex = items.firstIndex(where: { $0.id == endItem.id })
    else {
      return
    }

    let range = min(startIndex, endIndex)...max(startIndex, endIndex)
    let itemsInRange = items[range]

    // Replace current selection with items in range
    selectedItems = Set(itemsInRange)
  }
}
