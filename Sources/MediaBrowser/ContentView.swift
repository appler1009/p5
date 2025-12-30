import AppKit
import MapKit
import SwiftUI

struct ContentView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared
  @ObservedObject private var mediaScanner = MediaScanner.shared
  @Environment(\.openWindow) private var openWindow
  @State private var selectedItems: Set<MediaItem> = []
  @State private var lightboxItemId: Int?
  @AppStorage("viewMode") private var viewMode = "Grid"
  @State private var searchQuery = ""

  @FocusState private var focusedField: String?
  @State private var searchTextField: NSTextField?
  @State private var scrollTarget: Int? = nil

  private var sortedItems: [LocalFileSystemMediaItem] {
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

  private var monthlyGroups: [(month: String, items: [LocalFileSystemMediaItem])] {
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
    ZStack {
      // Hidden button for `/` shortcut for search
      Button("") {
        DispatchQueue.main.async {
          self.searchTextField?.window?.makeFirstResponder(self.searchTextField)
        }
      }
      .keyboardShortcut("/", modifiers: [])
      .hidden()

      VStack(spacing: 0) {
        if viewMode == "Grid" {
          MediaGridView(
            selectedItems: $selectedItems,
            lightboxItemId: $lightboxItemId,
            searchQuery: $searchQuery
          )
        } else if viewMode == "Map" {
          MediaMapView(
            lightboxItemId: $lightboxItemId,
            searchQuery: $searchQuery
          )
        }
      }

      if let selectedIdForLightbox = lightboxItemId,
        let selectedItemForLightbox = mediaScanner.items.first(where: { item in
          item.id == selectedIdForLightbox
        })
      {
        FullMediaView(
          item: selectedItemForLightbox,
          onClose: { lightboxItemId = nil },
          onNext: { nextItem() },
          onPrev: { prevItem() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
      }
    }

    .navigationTitle("Media Browser")
    .onAppear {
      setupS3SyncNotifications()
    }
    .toolbar {
      ToolbarItem {
        Picker("View Mode", selection: $viewMode) {
          Image(systemName: "square.grid.2x2").tag("Grid")
          Image(systemName: "map").tag("Map")
        }
        .pickerStyle(.segmented)
      }
      ToolbarItem {
        Button(action: {
          openWindow(id: "settings")
        }) {
          Image(systemName: "gear")
        }
        .help("Settings")
        .keyboardShortcut(",", modifiers: .command)
      }
      ToolbarItem {
        Button(action: {
          openWindow(id: "import")
        }) {
          Image(systemName: "iphone.and.arrow.forward")
        }
        .help("Import (⌘O)")
        .keyboardShortcut("O", modifiers: .command)
      }

      ToolbarItemGroup(placement: .principal) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
          FocusableTextField(text: $searchQuery, textField: $searchTextField)
            .frame(minWidth: 200, maxWidth: 300)
        }
        .padding(.leading, 8)
        .overlay(alignment: .trailing) {
          if !searchQuery.isEmpty {
            Button(action: {
              searchQuery = ""
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
          }
        }
      }
    }

  }

  private func nextItem() {
    guard let firstSelected = selectedItems.first,
      let index = sortedItems.firstIndex(where: { $0.id == firstSelected.id })
    else { return }
    let nextIndex = (index + 1) % sortedItems.count
    selectedItems = [sortedItems[nextIndex]]
    withAnimation(.easeInOut(duration: 0.1)) {
      lightboxItemId = sortedItems[nextIndex].id
    }
  }

  private func prevItem() {
    guard let firstSelected = selectedItems.first,
      let index = sortedItems.firstIndex(where: { $0.id == firstSelected.id })
    else { return }
    let prevIndex = (index - 1 + sortedItems.count) % sortedItems.count
    selectedItems = [sortedItems[prevIndex]]
    withAnimation(.easeInOut(duration: 0.1)) {
      lightboxItemId = sortedItems[prevIndex].id
    }
  }

  /// Update a media item
  func updateItem(itemId: Int, statusRaw: String) {
    DispatchQueue.main.async {
      guard let status = S3SyncStatus(rawValue: statusRaw),
        let sourceIndex = mediaScanner.items.firstIndex(where: { $0.id == itemId })
      else { return }

      mediaScanner.items[sourceIndex].s3SyncStatus = status
    }
  }

  /// Listen for S3 sync status updates
  private func setupS3SyncNotifications() {
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("S3SyncStatusUpdated"),
      object: nil,
      queue: .main
    ) { notification in
      if let userInfo = notification.userInfo,
        let itemId = userInfo["itemId"] as? Int,
        let statusRaw = userInfo["status"] as? String
      {
        updateItem(itemId: itemId, statusRaw: statusRaw)
      }
    }
  }
}

class ToolbarSearchField: NSTextField {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.keyCode == 53 {  // Escape
      window?.makeFirstResponder(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

struct FocusableTextField: NSViewRepresentable {
  @Binding var text: String
  @Binding var textField: NSTextField?

  func makeNSView(context: Context) -> NSTextField {
    let textField = ToolbarSearchField()
    textField.stringValue = text
    textField.placeholderString = "Search..."
    textField.delegate = context.coordinator
    // Store reference for focusing
    self.textField = textField
    return textField
  }

  func updateNSView(_ nsView: NSTextField, context: Context) {
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
    // Update binding
    if self.textField !== nsView {
      self.textField = nsView
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: FocusableTextField

    init(_ parent: FocusableTextField) {
      self.parent = parent
    }

    func controlTextDidChange(_ obj: Notification) {
      if let textField = obj.object as? NSTextField {
        parent.text = textField.stringValue
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
