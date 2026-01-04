import SwiftUI

// Simplified version that works specifically with MediaItem and supports multiple selection
struct SectionGridView: View {
  let title: String?
  let items: [MediaItem]
  let onSelectionChange: (Set<MediaItem>) -> Void
  let onItemDoubleTap: (MediaItem) -> Void
  let minCellWidth: CGFloat
  let disableDuplicates: Bool
  let onDuplicateCountChange: ((Int) -> Void)?

  @State private var selectedItems: Set<MediaItem>
  @State private var itemsNeedingThumbnailUpdate: Set<Int> = []
  @State private var thumbnailObserver: NSObjectProtocol?
  @State private var lastSelectedItem: MediaItem?
  @State private var duplicateIds: Set<Int> = []
  @State private var hoveredItemId: Int? = nil

  // Default initializer for standard MediaItemView usage with multiple selection
  init(
    title: String? = nil,
    items: [MediaItem],
    selectedItems: Set<MediaItem>,
    onSelectionChange: @escaping (Set<MediaItem>) -> Void,
    onItemDoubleTap: @escaping (MediaItem) -> Void,
    minCellWidth: CGFloat = 80,
    disableDuplicates: Bool = false,
    onDuplicateCountChange: ((Int) -> Void)? = nil
  ) {
    self.title = title
    self.items = items
    self.selectedItems = Set(selectedItems)
    self.onSelectionChange = onSelectionChange
    self.onItemDoubleTap = onItemDoubleTap
    self.minCellWidth = minCellWidth
    self.disableDuplicates = disableDuplicates
    self.onDuplicateCountChange = onDuplicateCountChange
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title = title {
        Text(title)
          .font(.headline)
          .padding(.horizontal)
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: minCellWidth))], spacing: 10) {
        ForEach(items) { item in
          MediaItemView(
            item: item,
            onTap: nil,
            isSelected: selectedItems.contains(item),
            isDuplicate: duplicateIds.contains(item.id),
            externalThumbnail: nil,
            shouldReloadThumbnail: itemsNeedingThumbnailUpdate.contains(item.id)
          )
          .onHover { hovering in
            hoveredItemId = hovering ? item.id : nil
          }
          .scaleEffect(hoveredItemId == item.id ? 1.05 : 1.0)
          .animation(.easeInOut(duration: 0.2), value: hoveredItemId)
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
      checkForDuplicates()
    }
    .onDisappear {
      cleanupThumbnailObserver()
    }
    .onReceive(NotificationCenter.default.publisher(for: .newMediaItemImported)) { notification in
      if let itemId = notification.object as? Int {
        duplicateIds.insert(itemId)
      }
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

  private func checkForDuplicates() {
    guard disableDuplicates else { return }
    Task {
      var newDuplicates: Set<Int> = []
      for item in items {
        let baseName = item.displayName.extractBaseName()
        if DatabaseManager.shared.hasDuplicate(baseName: baseName, date: item.thumbnailDate) {
          newDuplicates.insert(item.id)
        }
      }
      duplicateIds = newDuplicates
      onDuplicateCountChange?(duplicateIds.count)
    }
  }

  private func handleItemSelection(_ item: MediaItem) {
    if duplicateIds.contains(item.id) {
      return  // ignore duplicates
    }

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
        lastSelectedItem = item
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
    let itemsInRange = items[range].filter { !duplicateIds.contains($0.id) }

    // Replace current selection with items in range
    selectedItems = Set(itemsInRange)
  }
}
