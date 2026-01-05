import CryptoKit
import ImageCaptureCore
import SwiftUI

// MARK: - Import View

struct ImportView: View {
  @State private var importFromDevice = ImportFromDevice()
  @State private var isScanningDevices = false
  @State private var importStatus: String?
  @State private var deviceConnectionError: String?
  @State private var isImportFromDeviceSelected: Bool = false
  @State private var deviceMediaItems: [ConnectedDeviceMediaItem] = []
  @State private var selectedDeviceMediaItems: Set<ConnectedDeviceMediaItem> = Set()

  @State private var importApplePhotos = ImportApplePhotos()
  @State private var selectedApplePhotosLibrary: URL?
  @State private var isApplePhotosSelected: Bool = false
  @State private var isReadingApplePhotos: Bool = false
  @State private var appleMediaItems: [ApplePhotosMediaItem] = []
  @State private var selectedAppleMediaItems: Set<ApplePhotosMediaItem> = Set()

  @State private var importLocalFiles = ImportLocalFiles()
  @State private var localFilesItems: [LocalFileSystemMediaItem] = []
  @State private var isLocalFilesSelected: Bool = false
  @State private var selectedLocalFilesItems: Set<LocalFileSystemMediaItem> = Set()
  @State private var selectedLocalDirectory: URL?

  @State private var duplicateCount = 0
  @State private var isImportInProgress = false
  @State private var progressCounter: ImportProgressCounter? = nil

  @Environment(\.dismiss) private var dismiss

  // MARK: - Apple Photo Contents
  var applePhotosContent: some View {
    VStack(spacing: 16) {
      HStack {
        Image(systemName: "photo.on.rectangle.angled")
          .foregroundColor(.green)
        Text("Photos from Apple Photos library")
          .font(.title2)
          .fontWeight(.semibold)

        Spacer()

        if appleMediaItems.count > 0 {
          Text(availabilityLabelText(regarding: appleMediaItems))
        }

        Button(importButtonText(forSelection: selectedAppleMediaItems)) {
          Task {
            self.showStatus("Import started")
            await self.doImportApplePhotos()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(appleMediaItems.count <= duplicateCount || isImportInProgress)
      }

      if appleMediaItems.isEmpty {
        // Show no photos found
        VStack(spacing: 20) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 80))
            .foregroundColor(.secondary)

          if isReadingApplePhotos {
            ProgressView()
            Text("Reading Apple Photos database...")
          } else {
            Button("Open Apple Photos") {
              Task {
                isReadingApplePhotos = true
                openApplePhotosPicker()
              }
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          SectionGridView(
            items: appleMediaItems,
            selectedItems: selectedAppleMediaItems,
            onSelectionChange: { selectedItems in
              selectedAppleMediaItems = selectedItems as! Set<ApplePhotosMediaItem>
            },
            onItemDoubleTap: { _ in },
            minCellWidth: 80,
            disableDuplicates: true,
            onDuplicateCountChange: { duplicateCount = $0 }
          )
          .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - USB Device Contents
  var deviceContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "iphone")
          .foregroundColor(.green)
        Text("Photos from \(importFromDevice.selectedDevice?.name ?? "Connected Device")")
          .font(.title2)
          .fontWeight(.semibold)
        Spacer()
        if deviceMediaItems.count > 0 {
          Text(availabilityLabelText(regarding: deviceMediaItems))
        }
        Button(importButtonText(forSelection: selectedDeviceMediaItems)) {
          Task {
            self.showStatus("Download started")
            await self.doImportMediaFromDevice()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(deviceMediaItems.count <= duplicateCount || isImportInProgress)
      }

      // Status messages
      if let status = importStatus {
        HStack {
          Image(systemName: "info.circle")
            .foregroundColor(.blue)
          Text(status)
            .foregroundColor(.blue)
          Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
      }

      if deviceMediaItems.isEmpty == false {
        ScrollView {
          VStack(spacing: 4) {
            SectionGridView(
              items: deviceMediaItems,
              selectedItems: selectedDeviceMediaItems,
              onSelectionChange: { selectedItems in
                selectedDeviceMediaItems = selectedItems as! Set<ConnectedDeviceMediaItem>
              },
              onItemDoubleTap: { _ in },  // No-op for import view
              minCellWidth: 80,
              disableDuplicates: true,
              onDuplicateCountChange: { duplicateCount = $0 }
            )
          }
          .padding()
        }
      } else if importFromDevice.isLoadingDeviceContents {
        VStack(spacing: 16) {
          ProgressView()
            .scaleEffect(1.5)
          Text("Loading photos from device...")
            .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = deviceConnectionError {
        VStack(spacing: 20) {
          Image(systemName: "lock.iphone")
            .font(.system(size: 80))
            .foregroundColor(.secondary)

          VStack(spacing: 12) {
            Text("Device Connection Issue")
              .font(.title2)
              .fontWeight(.semibold)

            Text(error)
              .font(.subheadline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
          }

          HStack(spacing: 16) {
            Button("Scan for Devices") {
              self.scanForDevices()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
      } else {  // no error, not loading, device must be empty
        VStack(spacing: 20) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 80))
            .foregroundColor(.secondary)

          if importFromDevice.isScanning {
            ProgressView()
            Text("Scanning available devices...")
            Button("Stop Scanning") {
              importFromDevice.stopScanning()
            }
          } else {
            Button("Scan for Devices") {
              self.scanForDevices()
            }
            .buttonStyle(.borderedProminent)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - Local Files Contents
  var localFilesContent: some View {
    VStack(spacing: 16) {
      HStack {
        Image(systemName: "photo.on.rectangle.angled")
          .foregroundColor(.green)
        Text("Photos from Local Files")
          .font(.title2)
          .fontWeight(.semibold)

        Spacer()

        if localFilesItems.count > 0 {
          Text(availabilityLabelText(regarding: localFilesItems))
        }

        Button(importButtonText(forSelection: selectedLocalFilesItems)) {
          Task {
            self.showStatus("Import started")
            await self.doImportLocalFiles()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(localFilesItems.count <= duplicateCount || isImportInProgress)
      }

      if localFilesItems.isEmpty {
        // Show no photos found
        VStack(spacing: 20) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 80))
            .foregroundColor(.secondary)

          Button("Open Directory") {
            Task {
              openLocalDirectoryPicker()
            }
          }
          .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          SectionGridView(
            items: localFilesItems,
            selectedItems: selectedLocalFilesItems,
            onSelectionChange: { selectedItems in
              selectedLocalFilesItems = selectedItems as! Set<LocalFileSystemMediaItem>
            },
            onItemDoubleTap: { _ in },
            minCellWidth: 80,
            disableDuplicates: true,
            onDuplicateCountChange: { duplicateCount = $0 }
          )
          .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - Devices List
  var connectedDevicesList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Available Devices")
        .font(.subheadline)
        .fontWeight(.medium)

      ForEach(importFromDevice.detectedDevices, id: \.name) { device in
        HStack {
          Image(systemName: "iphone")
            .foregroundColor(.green)
          Text(device.name ?? "Unknown iPhone")
            .frame(maxWidth: .infinity, alignment: .leading)

          Spacer()

          Button("Select") {
            deviceMediaItems = []
            browseMedia(from: device)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(importFromDevice.selectedDevice?.name == device.name)
        }
        .padding(.vertical, 4)
      }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(8)
  }

  // MARK: - Main Body
  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      // Sidebar
      VStack(alignment: .leading, spacing: 16) {
        Text("Sources")
          .font(.headline)
          .padding(.bottom, 8)

        VStack(spacing: 12) {
          Button(action: {
            Task {
              isLocalFilesSelected = false
              isApplePhotosSelected = false
              isImportFromDeviceSelected = true
            }
          }) {
            HStack {
              Image(systemName: "iphone.and.arrow.forward")
                .frame(width: 20)
              Text("Devices")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)

          Button(action: {
            Task {
              isApplePhotosSelected = false
              isImportFromDeviceSelected = false
              isLocalFilesSelected = true
            }
          }) {
            HStack {
              Image(systemName: "folder")
                .frame(width: 20)
              Text("Local Files")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)

          Button(action: {
            Task {
              isImportFromDeviceSelected = false
              isLocalFilesSelected = false
              isApplePhotosSelected = true
            }
          }) {
            HStack {
              Image(systemName: "folder")
                .frame(width: 20)
              Text("Apple Photos")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
        }

        if !importFromDevice.detectedDevices.isEmpty {
          connectedDevicesList
        }

        Spacer()
      }
      .padding()
      .frame(minWidth: 280)
    } detail: {
      // Main content area
      VStack(spacing: 24) {
        if isApplePhotosSelected {
          applePhotosContent
            .padding()
        } else if isImportFromDeviceSelected {
          deviceContent
            .padding()
        } else if isLocalFilesSelected {
          localFilesContent
            .padding()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(NSColor.controlBackgroundColor))

      // Import directory section at the bottom
      ImportDirectorySection()
        .padding(.horizontal)
        .background(Color(NSColor.controlBackgroundColor))
    }
    .navigationTitle("Import Photos")
    .onDisappear {
      Task {
        await importFromDevice.cancelAllThumbnails()
        await importFromDevice.cancelAllDownloads()
      }
      importFromDevice.stopScanning()
    }
    .frame(minWidth: 700, minHeight: 500)
  }

  // MARK: - Supporting Functions

  private func showStatus(_ message: String) {
    importStatus = message
    // Auto-clear after 10 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
      if self.importStatus == message {
        self.importStatus = nil
      }
    }
  }

  private func showError(_ message: String) {
    deviceConnectionError = message
    // Keep error visible until user acknowledges or retries
  }
  private func clearError() {
    deviceConnectionError = nil
  }

  private func importButtonText(forSelection selectedItems: Set<MediaItem>) -> String {
    if selectedItems.count > 0 {
      return "Import \(selectedItems.count) Selected"
    }
    return "Import All"
  }

  private func availabilityLabelText(regarding items: [MediaItem]) -> String {
    if items.count > 0 {
      let totalCount = items.count
      if duplicateCount > 0 {
        let availableCount = items.count - duplicateCount
        return "\(availableCount) available for import out of total \(totalCount)"
      }
      return "Total \(totalCount) available for import"
    }
    return ""
  }

  private func openLocalDirectoryPicker() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.image, .movie, .folder]
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.message = "Select photos and videos to import"
    panel.prompt = "Import"

    if panel.runModal() == .OK {
      // take the source directory
      self.selectedLocalDirectory = panel.urls.first!

      // Clear existing items before starting new preview
      localFilesItems = []

      if let sourceDir = self.selectedLocalDirectory {
        Task {
          try await importLocalFiles.previewPhotos(
            sourceDirectory: sourceDir,
            scanCallbacks: ScanCallbacks(
              onMediaFound: { mediaItem in
                localFilesItems.append(mediaItem as! LocalFileSystemMediaItem)
              },
              onComplete: {},
              onError: { error in }
            )
          )
        }
      }
    }
  }

  private func openApplePhotosPicker() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.folder]
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Select Apple Photos to import"
    panel.prompt = "Import"

    if panel.runModal() == .OK {
      // Clear existing items before starting new preview
      self.appleMediaItems = []

      let importCallbacks = ScanCallbacks(
        onMediaFound: { mediaItem in
          // Update applePhotosItems in real-time when new media is found
          self.appleMediaItems.insertSorted(
            mediaItem as! ApplePhotosMediaItem,
            by: \.thumbnailDate,
            order: .descending
          )
        },
        onComplete: {
          self.isReadingApplePhotos = false
        },
        onError: { error in }
      )
      Task {
        let _ = try await importApplePhotos.previewPhotos(
          from: panel.urls.first!,
          with: importCallbacks
        )
      }
    }
  }

  private func scanForDevices() {
    let callbacks = ScanCallbacks(
      onMediaFound: { mediaItem in
        // Update deviceMediaItems in real-time when new media is found
        self.deviceMediaItems.insertSorted(
          mediaItem as! ConnectedDeviceMediaItem,
          by: \.thumbnailDate,
          order: .descending
        )
      },
      onComplete: {
        // no op
      },
      onError: { error in
        print("device media browsing error \(error.localizedDescription)")
        self.showError(error.localizedDescription)
      }
    )

    importFromDevice.scanForDevices(with: callbacks)
  }

  private func browseMedia(from device: ICCameraDevice) {
    clearError()
    importFromDevice.selectDevice(device)
  }

  private func doImportMediaFromDevice() async {
    let items: [ConnectedDeviceMediaItem] =
      self.selectedDeviceMediaItems.isEmpty
      ? self.deviceMediaItems : Array(self.selectedDeviceMediaItems)

    let cameraItemProgressCounter = CameraFileImportProgressCounter()
    self.progressCounter = cameraItemProgressCounter
    await importFromDevice.requestDownloads(
      items: items,
      with: ImportCallbacks(
        onMediaImported: { mediaItem in },
        onMediaSkipped: { mediaItem in },
        onComplete: {},
        onError: { error in
          showError("Failed to finish importing: \(error.localizedDescription)")
        }
      ),
      progress: cameraItemProgressCounter
    )
  }

  private func doImportApplePhotos() async {
    guard let photosLib = selectedApplePhotosLibrary else { return }

    let urlProgressCounter = URLImportProgressCounter()
    self.progressCounter = urlProgressCounter

    let items: [ApplePhotosMediaItem] =
      self.selectedAppleMediaItems.isEmpty
      ? self.appleMediaItems : Array(self.selectedAppleMediaItems) as! [ApplePhotosMediaItem]

    do {
      try await importApplePhotos.importItems(
        items: items,
        from: photosLib,
        to: DirectoryManager.shared.importDirectory,
        with: ImportCallbacks(
          onMediaImported: { mediaItem in },
          onMediaSkipped: { mediaItem in },
          onComplete: {},
          onError: { error in
            showError("Failed to import: \(error.localizedDescription)")
          }
        ),
        progress: urlProgressCounter
      )
    } catch {
      showError("Failed to import Apple Photos: \(error.localizedDescription)")
    }
  }

  private func doImportLocalFiles() async {
    guard let sourceDir = selectedLocalDirectory else { return }

    let urlProgressCounter = URLImportProgressCounter()
    self.progressCounter = urlProgressCounter

    let items: [LocalFileSystemMediaItem] =
      self.selectedLocalFilesItems.isEmpty
      ? self.localFilesItems : Array(self.selectedLocalFilesItems)

    do {
      try await importLocalFiles.importPhotos(
        items: items,
        from: sourceDir,
        to: DirectoryManager.shared.importDirectory,
        callbacks: ImportCallbacks(
          onMediaImported: { mediaItem in },
          onMediaSkipped: { mediaItem in },
          onComplete: {},
          onError: { error in
            showError("Failed to import: \(error.localizedDescription)")
          }
        ),
        progress: urlProgressCounter
      )
    } catch {
      showError("Failed to import from local directory: \(error.localizedDescription)")
    }
  }
}

// MARK: - Import Callback Handlers

class ScanCallbacks {
  let onMediaFound: (MediaItem) -> Void
  let onComplete: () -> Void
  let onError: (Error) -> Void

  init(
    onMediaFound: @escaping (MediaItem) -> Void,
    onComplete: @escaping () -> Void,
    onError: @escaping (Error) -> Void
  ) {
    self.onMediaFound = onMediaFound
    self.onComplete = onComplete
    self.onError = onError
  }
}

class ImportCallbacks {
  let onMediaImported: (MediaItem) -> Void
  let onMediaSkipped: (MediaItem) -> Void
  let onComplete: () -> Void
  let onError: (Error) -> Void

  init(
    onMediaImported: @escaping (MediaItem) -> Void,
    onMediaSkipped: @escaping (MediaItem) -> Void,
    onComplete: @escaping () -> Void,
    onError: @escaping (Error) -> Void
  ) {
    self.onMediaImported = onMediaImported
    self.onMediaSkipped = onMediaSkipped
    self.onComplete = onComplete
    self.onError = onError
  }
}

// MARK: - Import Progress Counters

class ImportProgressCounter {
  private var allItems: Set<MediaItem> = Set()

  func add(mediaItem: MediaItem) {
    self.allItems.insert(mediaItem)
  }

  func remove(mediaItem: MediaItem) {
    self.allItems.remove(mediaItem)
  }

  func getAllMediaItems() -> Set<MediaItem> {
    return self.allItems
  }

  func countAll() -> Int { return 0 }

  func countItems() -> Int {
    return allItems.count
  }
}

class URLImportProgressCounter: ImportProgressCounter {
  private var allURLs: Set<URL> = Set()
  private var mediaItemLookup: [URL: MediaItem] = [:]

  override func add(mediaItem: MediaItem) {
    if let item = mediaItem as? LocalFileSystemMediaItem {
      self.allURLs.insert(item.originalUrl)
      self.mediaItemLookup[item.originalUrl] = mediaItem

      if let edited = item.editedUrl {
        self.allURLs.insert(edited)
        self.mediaItemLookup[edited] = mediaItem
      }

      if let live = item.liveUrl {
        self.allURLs.insert(live)
        self.mediaItemLookup[live] = mediaItem
      }

      super.add(mediaItem: mediaItem)
    }
  }

  override func countAll() -> Int {
    return self.allURLs.count
  }

  override func countItems() -> Int {
    return Set(self.mediaItemLookup.values).count
  }

  func processed(url: URL) -> MediaItem? {
    self.allURLs.remove(url)
    let mediaItemRemoved = self.mediaItemLookup.removeValue(forKey: url)
    if let item = mediaItemRemoved {
      let setAfterRemoved = Set(self.mediaItemLookup.values)
      if setAfterRemoved.contains(item) == false {
        super.remove(mediaItem: item)
        return item
      }
    }
    return nil
  }
}

class CameraFileImportProgressCounter: ImportProgressCounter {
  private var allCameraItems: Set<ICCameraItem> = Set()
  private var mediaItemLookup: [ICCameraItem: MediaItem] = [:]

  override func add(mediaItem: MediaItem) {
    if let item = mediaItem as? ConnectedDeviceMediaItem {
      self.allCameraItems.insert(item.originalItem)
      self.mediaItemLookup[item.originalItem] = mediaItem

      if let edited = item.editedItem {
        self.allCameraItems.insert(edited)
        self.mediaItemLookup[edited] = mediaItem
      }

      if let live = item.liveItem {
        self.allCameraItems.insert(live)
        self.mediaItemLookup[live] = mediaItem
      }

      super.add(mediaItem: mediaItem)
    }
  }

  override func countAll() -> Int {
    return self.allCameraItems.count
  }

  override func countItems() -> Int {
    return Set(self.mediaItemLookup.values).count
  }

  func getAllCameraItems() -> Set<ICCameraItem> {
    return allCameraItems
  }

  func processed(cameraItem: ICCameraItem) -> MediaItem? {
    self.allCameraItems.remove(cameraItem)
    let mediaItemRemoved = self.mediaItemLookup.removeValue(forKey: cameraItem)
    if let item = mediaItemRemoved {
      let setAfterRemoved = Set(self.mediaItemLookup.values)
      if setAfterRemoved.contains(item) == false {
        super.remove(mediaItem: item)
        return item
      }
    }
    return nil
  }
}
