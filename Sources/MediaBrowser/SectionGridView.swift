import SwiftUI

struct SectionGridView: View {
  let group: (month: String, items: [MediaItem])
  @Binding var selectedItem: MediaItem?
  let onItemTap: (MediaItem) -> Void

  var body: some View {
    Section(header: Text(group.month).font(.headline).padding(.horizontal)) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
        ForEach(group.items) { item in
          MediaItemView(
            item: item,
            onTap: {
              onItemTap(item)
            }, isSelected: item.id == selectedItem?.id
          ).id(item.id)
        }
      }
      .padding(.horizontal, 8)
    }
  }
}
