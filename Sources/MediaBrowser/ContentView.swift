import SwiftUI

struct ContentView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared
  @ObservedObject private var mediaScanner = MediaScanner.shared
  @Environment(\.openWindow) private var openWindow
  @State private var selectedItem: MediaItem?

  private var sortedItems: [MediaItem] {
    mediaScanner.items.sorted(by: {
      ($0.metadata?.creationDate ?? Date.distantPast)
        > ($1.metadata?.creationDate ?? Date.distantPast)
    })
  }

  private var monthlyGroups: [(month: String, items: [MediaItem])] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: sortedItems) { item -> Date? in
      guard let date = item.metadata?.creationDate else { return nil }
      return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }
    let sortedGroups = grouped.sorted { (lhs, rhs) -> Bool in
      guard let lhsDate = lhs.key, let rhsDate = rhs.key else { return lhs.key != nil }
      return lhsDate > rhsDate
    }
    return sortedGroups.map {
      (
        month: $0.key?.formatted(.dateTime.year().month(.wide)) ?? "Unknown",
        items: $0.value.sorted {
          ($0.metadata?.creationDate ?? Date.distantPast)
            > ($1.metadata?.creationDate ?? Date.distantPast)
        }
      )
    }
  }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        HStack {
          Button(action: {
            openWindow(id: "settings")
          }) {
            Image(systemName: "gear")
          }
          .help("Settings")
          .keyboardShortcut(",", modifiers: .command)

          Button("Scan") {
            Task {
              await MediaScanner.shared.scan(directories: directoryManager.directories)
            }
          }
          .disabled(directoryManager.directories.isEmpty)

          Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)

        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            ForEach(monthlyGroups, id: \.month) { group in
              Section(header: Text(group.month).font(.headline).padding(.horizontal)) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                  ForEach(group.items) { item in
                    MediaItemView(item: item, onTap: { selectedItem = item })
                  }
                }
                .padding(.horizontal, 8)
              }
            }
          }
          .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      if let selected = selectedItem {
        FullMediaView(
          item: selected,
          onClose: { selectedItem = nil },
          onNext: { nextItem() },
          onPrev: { prevItem() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
      }
    }
    .navigationTitle("Media Browser")
  }

  private func nextItem() {
    guard let index = sortedItems.firstIndex(where: { $0.id == selectedItem?.id }) else { return }
    let nextIndex = (index + 1) % sortedItems.count
    selectedItem = sortedItems[nextIndex]
  }

  private func prevItem() {
    guard let index = sortedItems.firstIndex(where: { $0.id == selectedItem?.id }) else { return }
    let prevIndex = (index - 1 + sortedItems.count) % sortedItems.count
    selectedItem = sortedItems[prevIndex]
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
