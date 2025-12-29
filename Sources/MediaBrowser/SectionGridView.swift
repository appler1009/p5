import SwiftUI

// Simplified version that works specifically with MediaItem
struct SectionGridView: View {
  let title: String?
  let items: [MediaItem]
  @Binding var selectedItem: MediaItem?
  let onItemTap: (MediaItem) -> Void
  let minCellWidth: CGFloat

  @State private var itemsNeedingThumbnailUpdate: Set<Int> = []
  @State private var thumbnailObserver: NSObjectProtocol?

  // Default initializer for standard MediaItemView usage
  init(
    title: String? = nil,
    items: [MediaItem],
    selectedItem: Binding<MediaItem?>,
    onItemTap: @escaping (MediaItem) -> Void,
    minCellWidth: CGFloat = 120
  ) {
    self.title = title
    self.items = items
    self._selectedItem = selectedItem
    self.onItemTap = onItemTap
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
        ForEach(items) { item in
          MediaItemView(
            item: item,
            onTap: { onItemTap(item) },
            isSelected: item.id == selectedItem?.id,
            shouldReloadThumbnail: itemsNeedingThumbnailUpdate.contains(item.id)
          )
          .onTapGesture {
            selectedItem = item
          }
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
}
