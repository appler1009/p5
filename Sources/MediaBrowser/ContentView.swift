import AppKit
import MapKit
import SwiftUI

struct ContentView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared
  @ObservedObject private var mediaScanner = MediaScanner.shared
  @Environment(\.openWindow) private var openWindow
  @State private var lightboxItem: MediaItem?
  @AppStorage("viewMode") private var viewMode = "Grid"
  @State private var searchQuery = ""
  @StateObject private var selectionState = GridSelectionState()

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

      // Keyboard shortcuts for grid navigation
      KeyCaptureView(onKey: { event in
        guard lightboxItem == nil else { return event }
        switch event.keyCode {
        case 36, 49:  // Enter or Space
          if let selectedItem = selectionState.selectedItems.first {
            withAnimation(.easeInOut(duration: 0.1)) {
              goFullScreen(selectedItem)
            }
          }
          return nil
        case 123:  // Left arrow
          moveSelectionLeft()
          return nil
        case 124:  // Right arrow
          moveSelectionRight()
          return nil
        case 53:  // ESC
          // When the search field (NSTextView editor) has focus, let ESC pass to the custom ToolbarSearchField.performKeyEquivalent
          // which clears the text if not empty or loses focus if empty.
          // Otherwise, consume ESC to clear the grid selection.
          if NSApp.keyWindow?.firstResponder is NSTextView {
            return event  // let the search field handle ESC
          } else {
            selectionState.selectedItems.removeAll()
            return nil
          }
        default: return event
        }
      })
      .opacity(0)
      .allowsHitTesting(false)

      VStack(spacing: 0) {
        if viewMode == "Grid" {
          MediaGridView(
            searchQuery: searchQuery,
            onSelected: selectItems,
            onFullScreen: goFullScreen,
            selectionState: selectionState,
            onScrollToItem: nil
          )
        } else if viewMode == "Map" {
          MediaMapView(
            lightboxItem: lightboxItem,
            searchQuery: searchQuery,
            onFullScreen: goFullScreen
          )
        }
      }

      if let selectedLightboxItem = lightboxItem {
        FullMediaView(
          item: selectedLightboxItem as! LocalFileSystemMediaItem,
          onClose: {
            lightboxItem = nil
          },
          onNext: nextFullScreenItem,
          onPrev: prevFullScreenItem
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
      }
    }

    .onAppear {

      setupS3SyncNotifications()

      DispatchQueue.main.async {

        NSApp.windows.first?.title = ""

      }

    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
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
        .help("Import (⌘I)")
        .keyboardShortcut("I", modifiers: .command)
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

    .navigationTitle("")
  }
  private func nextFullScreenItem() {
    guard let currentLightboxItem = lightboxItem,
      let index = sortedItems.firstIndex(where: { $0.id == currentLightboxItem.id })
    else { return }

    guard index < sortedItems.count - 1 else { return }
    let nextIndex = index + 1
    let nextItem = sortedItems[nextIndex]
    lightboxItem = nextItem
    selectionState.selectedItems = [nextItem]
    selectionState.scrollToItem = nextItem
  }

  private func prevFullScreenItem() {
    guard let currentLightboxItem = lightboxItem,
      let index = sortedItems.firstIndex(where: { $0.id == currentLightboxItem.id })
    else { return }

    guard index > 0 else { return }
    let prevIndex = index - 1
    let prevItem = sortedItems[prevIndex]
    lightboxItem = prevItem
    selectionState.selectedItems = [prevItem]
    selectionState.scrollToItem = prevItem
  }

  private func selectItems(_ items: Set<MediaItem>) {
    DispatchQueue.main.async {
      selectionState.selectedItems = items
    }
  }

  private func moveSelectionLeft() {
    guard !sortedItems.isEmpty else { return }
    let currentItem = selectionState.selectedItems.first

    let targetIndex: Int
    if let currentItem = currentItem,
      let idx = sortedItems.firstIndex(where: { $0.id == currentItem.id })
    {
      targetIndex = max(0, idx - 1)
    } else {
      targetIndex = sortedItems.count - 1
    }
    let targetItem = sortedItems[targetIndex]
    selectionState.selectedItems = [targetItem]
    selectionState.lastSelectedByKeyboard = targetItem
  }

  private func moveSelectionRight() {
    guard !sortedItems.isEmpty else { return }
    let currentItem = selectionState.selectedItems.first

    let targetIndex: Int
    if let currentItem = currentItem,
      let idx = sortedItems.firstIndex(where: { $0.id == currentItem.id })
    {
      targetIndex = min(sortedItems.count - 1, idx + 1)
    } else {
      targetIndex = 0
    }
    let targetItem = sortedItems[targetIndex]
    selectionState.selectedItems = [targetItem]
    selectionState.lastSelectedByKeyboard = targetItem
  }

  private func goFullScreen(_ item: MediaItem) {
    self.lightboxItem = item
  }

  /// Update a media item
  func updateItem(itemId: Int, statusRaw: String) {
    guard let status = S3SyncStatus(rawValue: statusRaw),
      let sourceIndex = mediaScanner.items.firstIndex(where: { $0.id == itemId })
    else { return }

    mediaScanner.items[sourceIndex].s3SyncStatus = status
  }

  private func handleRotateClockwise() async {
    guard let selectedItem = selectionState.selectedItems.first as? LocalFileSystemMediaItem,
      selectedItem.type == .photo
    else { return }

    await rotatePhoto(selectedItem, clockwise: true)
  }

  private func handleRotateCounterClockwise() async {
    guard let selectedItem = selectionState.selectedItems.first as? LocalFileSystemMediaItem,
      selectedItem.type == .photo
    else { return }

    await rotatePhoto(selectedItem, clockwise: false)
  }

  private func rotatePhoto(_ item: LocalFileSystemMediaItem, clockwise: Bool) async {
    do {
      // Load the current image
      guard let image = NSImage(contentsOf: item.displayURL) else { return }

      // Rotate the image
      let rotatedImage =
        clockwise
        ? ImageProcessing.shared.rotateImageClockwise(image)
        : ImageProcessing.shared.rotateImageCounterClockwise(image)

      guard let rotatedImage = rotatedImage else { return }

      // Create edited file URL
      let editedURL = item.originalUrl.createEditedFileURL()

      // Save rotated image with EXIF preservation
      try await ImageProcessing.shared.saveRotatedImage(
        rotatedImage,
        to: editedURL,
        preservingEXIF: true,
        sourceURL: item.originalUrl
      )

      // Update the media item
      item.editedUrl = editedURL

      // Update database
      DatabaseManager.shared.updateEditedUrl(for: item.id, editedUrl: editedURL)

      // Regenerate thumbnail
      _ = await ThumbnailCache.shared.generateAndCacheThumbnail(for: editedURL, mediaItem: item)

      // Update UI
      mediaScanner.objectWillChange.send()

    } catch {
      print("Error rotating photo: \(error)")
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
        Task { @MainActor in
          updateItem(itemId: itemId, statusRaw: statusRaw)
        }
      }
    }

    // Add observers for rotation commands
    NotificationCenter.default.addObserver(
      forName: .rotateClockwise,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        await handleRotateClockwise()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .rotateCounterClockwise,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        await handleRotateCounterClockwise()
      }
    }

    NotificationCenter.default.addObserver(
      forName: .openSettings,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        openWindow(id: "settings")
      }
    }

    NotificationCenter.default.addObserver(
      forName: .openImport,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        openWindow(id: "import")
      }
    }

    NotificationCenter.default.addObserver(
      forName: .databaseSwitched,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        await mediaScanner.loadFromDB()
      }
    }
  }
}

class ToolbarSearchField: NSTextField {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.keyCode == 53 {  // Escape
      if !stringValue.isEmpty {
        stringValue = ""  // Clear the text
        // Update the SwiftUI binding since programmatic changes don't trigger delegate
        (delegate as? FocusableTextField.Coordinator)?.parent.text = ""
      } else {
        NSApp.keyWindow?.makeFirstResponder(nil)  // Lose focus if empty
      }
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
