import SwiftUI

// Generic version that can work with different item types
struct SectionGridView<Item: Identifiable, Content: View>: View {
  let title: String?
  let items: [Item]
  @Binding var selectedItem: Item?
  let itemView: (Item) -> Content
  let minCellWidth: CGFloat

  init(
    title: String? = nil,
    items: [Item],
    selectedItem: Binding<Item?>,
    minCellWidth: CGFloat = 80,
    @ViewBuilder itemView: @escaping (Item) -> Content
  ) {
    self.title = title
    self.items = items
    self._selectedItem = selectedItem
    self.minCellWidth = minCellWidth
    self.itemView = itemView
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
          itemView(item)
            .onTapGesture {
              selectedItem = item
            }
        }
      }
      .padding(.horizontal, 8)
    }
  }
}

// Convenience initializer for MediaItem (backwards compatibility)
extension SectionGridView where Item == MediaItem, Content == MediaItemView {
  init(
    title: String? = nil,
    items: [MediaItem],
    selectedItem: Binding<MediaItem?>,
    onItemTap: @escaping (MediaItem) -> Void,
    minCellWidth: CGFloat = 120
  ) {
    self.init(
      title: title,
      items: items,
      selectedItem: selectedItem,
      minCellWidth: minCellWidth
    ) { item in
      MediaItemView(
        item: item,
        onTap: { onItemTap(item) },
        isSelected: item.id == selectedItem.wrappedValue?.id
      )
    }
  }
}
