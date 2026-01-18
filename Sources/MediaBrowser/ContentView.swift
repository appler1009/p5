import AppKit
import MapKit
import SwiftUI

struct ConditionalKeyboardShortcut: ViewModifier {
  let key: KeyEquivalent
  let modifiers: EventModifiers
  let condition: Bool

  func body(content: Content) -> some View {
    if condition {
      content.keyboardShortcut(key, modifiers: modifiers)
    } else {
      content
    }
  }
}

// Observable object for lightbox state
@MainActor
class LightboxStateManager: ObservableObject {
  static let shared = LightboxStateManager()

  @Published var isLightboxOpen = false
}

struct ContentView: View {
  let databasePath: String?

  let databaseManager: DatabaseManager
  @ObservedObject private var directoryManager: DirectoryManager
  @ObservedObject private var mediaScanner: MediaScanner
  @ObservedObject private var s3Service: S3Service
  @ObservedObject private var lightboxStateManager = LightboxStateManager.shared
  @Environment(\.openWindow) private var openWindow
  @State private var lightboxItem: MediaItem?
  @State private var viewMode = "Grid"
  @State private var gridCellSize: Double = 80
  @State private var searchQuery = ""
  @StateObject private var selectionState = GridSelectionState()

  @FocusState private var focusedField: String?
  @State private var searchTextField: NSTextField?
  @State private var scrollTarget: Int? = nil
  @State private var showSettingsSidebar = false
  @State private var showImportSidebar = false

  init(databasePath: String? = nil) {
    self.databasePath = databasePath
    let dbPath = databasePath ?? DatabaseManager.defaultPath
    self.databaseManager = DatabaseManager(path: dbPath)
    self.directoryManager = DirectoryManager(databaseManager: databaseManager)
    self.mediaScanner = MediaScanner(databaseManager: databaseManager)
    self.s3Service = S3Service(databaseManager: databaseManager)
    DatabaseManager.shared = databaseManager
    MediaScanner.shared = mediaScanner
    DirectoryManager.shared = directoryManager
    S3Service.shared = s3Service
    GeocodingService.shared = GeocodingService(databaseManager: databaseManager)
  }

  private var sortedItems: [LocalFileSystemMediaItem] {
    let allItems = mediaScanner.items
    let filteredItems =
      searchQuery.isEmpty
      ? allItems
      : allItems.filter { $0.matchesSearchQuery(searchQuery) }

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

  var keyCaptureView: some View {
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
  }

  var mainContentView: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        if viewMode == "Grid" {
          MediaGridView(
            mediaScanner: mediaScanner,
            databaseManager: databaseManager,
            searchQuery: searchQuery,
            onSelected: selectItems,
            onFullScreen: goFullScreen,
            onScrollToItem: nil,
            selectionState: selectionState,
            gridCellSize: gridCellSize
          )
        } else if viewMode == "Map" {
          MediaMapView(
            mediaScanner: mediaScanner,
            lightboxItem: lightboxItem,
            searchQuery: searchQuery,
            onFullScreen: goFullScreen
          )
        } else if viewMode == "Trash" {
          TrashView(
            databaseManager: databaseManager,
            s3Service: s3Service,
            mediaScanner: mediaScanner,
            gridCellSize: gridCellSize
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if showSettingsSidebar {
        Divider()

        SettingsView(
          directoryManager: directoryManager, s3Service: s3Service,
          databaseManager: databaseManager, mediaScanner: mediaScanner
        )
        .frame(width: 455)
        .frame(maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
      } else if showImportSidebar {
        Divider()

        ImportView(directoryManager: directoryManager, gridCellSize: gridCellSize)
          .frame(width: 600)
          .frame(maxHeight: .infinity)
          .background(Color(.windowBackgroundColor))
      }
    }
    .onAppear {
      self.viewMode = self.databaseManager.getSetting("viewMode") ?? "Grid"
      self.gridCellSize = Double(self.databaseManager.getSetting("gridCellSize") ?? "80") ?? 80
    }
    .onChange(of: viewMode) { _, newValue in
      databaseManager.setSetting("viewMode", value: newValue)
    }
    .onChange(of: gridCellSize) { _, newValue in
      databaseManager.setSetting("gridCellSize", value: String(Int(newValue)))
    }
    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsChanged"))) {
      _ in
      self.viewMode = self.databaseManager.getSetting("viewMode") ?? "Grid"
      self.gridCellSize = Double(self.databaseManager.getSetting("gridCellSize") ?? "80") ?? 80
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("switchToGridView"))) {
      _ in
      self.viewMode = "Grid"
      self.databaseManager.setSetting("viewMode", value: "Grid")
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("switchToMapView"))) {
      _ in
      self.viewMode = "Map"
      self.databaseManager.setSetting("viewMode", value: "Map")
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("switchToTrashView"))) {
      _ in
      self.viewMode = "Trash"
      self.databaseManager.setSetting("viewMode", value: "Trash")
    }
  }

  var lightboxView: some View {
    Group {
      if let selectedLightboxItem = lightboxItem {
        FullMediaView(
          item: selectedLightboxItem as! LocalFileSystemMediaItem,
          onClose: {
            lightboxItem = nil
            lightboxStateManager.isLightboxOpen = false
          },
          onNext: nextFullScreenItem,
          onPrev: prevFullScreenItem,
          databaseManager: databaseManager,
          mediaScanner: mediaScanner,
          s3Service: s3Service
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .onAppear {
          lightboxStateManager.isLightboxOpen = true
        }
        .onDisappear {
          lightboxStateManager.isLightboxOpen = false
        }
      }
    }
  }

  var viewModePickerToolbar: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      Picker("View Mode", selection: $viewMode) {
        Image(systemName: "square.grid.2x2").tag("Grid")
        Image(systemName: "map").tag("Map")
        Image(systemName: "trash").tag("Trash")
      }
      .pickerStyle(.segmented)
    }
  }

  var actionButtonsToolbar: some ToolbarContent {
    Group {
      ToolbarItem {
        Button(action: {
          withAnimation(.easeInOut(duration: 0.2)) {
            showImportSidebar = false
            showSettingsSidebar.toggle()
          }
        }) {
          Image(systemName: "gear")
        }
        .help("Settings")
        .keyboardShortcut(",", modifiers: .command)
      }
      ToolbarItem {
        Button(action: {
          withAnimation(.easeInOut(duration: 0.2)) {
            showSettingsSidebar = false
            showImportSidebar.toggle()
          }
        }) {
          Image(systemName: "iphone.and.arrow.forward")
        }
        .help("Import (⌘M)")
        .modifier(
          ConditionalKeyboardShortcut(
            key: KeyEquivalent("m"),
            modifiers: .command,
            condition: lightboxItem == nil
          )
        )
      }
    }
  }

  var searchToolbar: some ToolbarContent {
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
      keyCaptureView

      mainContentView

      lightboxView
    }
    .onAppear {

      // Save the current database path as last opened
      if let databasePath = databasePath {

        UserDefaults.standard.set(databasePath, forKey: "lastOpenedDatabasePath")
        // Add to recent databases
        UserDefaults.addRecentDatabase(databasePath)
      } else {
        print("Not saving lastOpenedDatabasePath because databasePath is nil")
      }

      setupS3SyncNotifications()

      // Start auto-sync if enabled
      if s3Service.autoSyncEnabled && s3Service.config.isValid {
        Task {
          await s3Service.uploadNextItem()
        }
      }
    }
    .toolbar {
      viewModePickerToolbar
      actionButtonsToolbar
      searchToolbar
    }
    .navigationTitle(databasePath.map { ($0 as NSString).lastPathComponent } ?? "")
    .background(WindowStateRestorer(databasePath: databasePath))
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
    lightboxStateManager.isLightboxOpen = true
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
      databaseManager.updateEditedUrl(for: item.id, editedUrl: editedURL)

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
        withAnimation(.easeInOut(duration: 0.2)) {
          showImportSidebar = false
          showSettingsSidebar.toggle()
        }
      }
    }

    NotificationCenter.default.addObserver(
      forName: .openImport,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        // Only respond to import notification when not viewing full-screen media
        guard lightboxItem == nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
          showSettingsSidebar = false
          showImportSidebar.toggle()
        }
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

    NotificationCenter.default.addObserver(
      forName: .openNewDatabase,
      object: nil,
      queue: .main
    ) { notification in
      if let userInfo = notification.userInfo, let path = userInfo["path"] as? String {
        Task { @MainActor in
          openWindow(id: "database", value: path)
        }
      }
    }

    NotificationCenter.default.addObserver(
      forName: .openDatabase,
      object: nil,
      queue: .main
    ) { notification in
      if let userInfo = notification.userInfo, let path = userInfo["path"] as? String {
        Task { @MainActor in
          openWindow(id: "database", value: path)
        }
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

struct WindowStateRestorer: NSViewRepresentable {
  let databasePath: String?

  func makeCoordinator() -> Coordinator {
    Coordinator(databasePath: databasePath)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard let databasePath = databasePath else { return }

    if let window = nsView.window {
      // Set represented URL for window identification
      window.representedURL = URL(fileURLWithPath: databasePath)

      let state = UserDefaults.windowState(for: databasePath)
      if let frame = state.frame {
        // Restore frame
        window.setFrame(frame, display: true)

        // Restore fullscreen if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          if state.isFullscreen && !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
          } else if !state.isFullscreen && window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
          }
        }
      }

      // Set delegate to save on changes
      window.delegate = context.coordinator
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let window = nsView.window {
          // Set represented URL for window identification
          window.representedURL = URL(fileURLWithPath: databasePath)

          let state = UserDefaults.windowState(for: databasePath)
          if let frame = state.frame {
            // Restore frame
            window.setFrame(frame, display: true)

            // Restore fullscreen if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              if state.isFullscreen && !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
              } else if !state.isFullscreen && window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
              }
            }
          }

          // Set delegate to save on changes
          window.delegate = context.coordinator
        }
      }
    }
  }

  class Coordinator: NSObject, NSWindowDelegate {
    let databasePath: String

    init(databasePath: String?) {
      self.databasePath = databasePath ?? ""
    }

    func windowDidResize(_ notification: Notification) {
      guard let window = notification.object as? NSWindow else { return }
      let frame = window.frame
      let isFullscreen = window.styleMask.contains(.fullScreen)
      UserDefaults.saveWindowState(for: databasePath, frame: frame, isFullscreen: isFullscreen)
    }

    func windowDidMove(_ notification: Notification) {
      guard let window = notification.object as? NSWindow else { return }
      let frame = window.frame
      let isFullscreen = window.styleMask.contains(.fullScreen)
      UserDefaults.saveWindowState(for: databasePath, frame: frame, isFullscreen: isFullscreen)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
      guard let window = notification.object as? NSWindow else { return }
      let frame = window.frame
      UserDefaults.saveWindowState(for: databasePath, frame: frame, isFullscreen: true)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
      guard let window = notification.object as? NSWindow else { return }
      let frame = window.frame
      UserDefaults.saveWindowState(for: databasePath, frame: frame, isFullscreen: false)
    }

    func windowDidBecomeMain(_ notification: Notification) {

      // Add this window to the open windows list
      if !databasePath.isEmpty {
        UserDefaults.addOpenDatabaseWindow(databasePath)
      }
    }

    func windowWillClose(_ notification: Notification) {

      // Remove this window from the open windows list only if app is not terminating
      if !databasePath.isEmpty && !AppDelegate.isTerminating {
        UserDefaults.removeOpenDatabaseWindow(databasePath)
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
