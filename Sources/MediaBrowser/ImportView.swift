import CryptoKit
import ImageCaptureCore
import SwiftUI

// MARK: - Custom Disclosure Group Style

struct CustomDisclosureGroupStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: {
        withAnimation(.easeInOut(duration: 0.2)) {
          configuration.isExpanded.toggle()
        }
      }) {
        HStack {
          configuration.label
          Spacer()
          Image(systemName: configuration.isExpanded ? "chevron.up" : "chevron.down")
            .foregroundColor(.secondary)
            .font(.system(size: 12))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
      }
      .buttonStyle(.plain)

      if configuration.isExpanded {
        configuration.content
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .background(Color(NSColor.windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
    )
  }
}

// MARK: - Import View

struct ImportView: View {
  @ObservedObject private var directoryManager: DirectoryManager
  let gridCellSize: Double

  init(directoryManager: DirectoryManager, gridCellSize: Double) {
    self.directoryManager = directoryManager
    self.gridCellSize = gridCellSize
  }
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
  @State private var isImportingApplePhotos: Bool = false
  @State private var appleMediaItems: [ApplePhotosMediaItem] = []
  @State private var selectedAppleMediaItems: Set<ApplePhotosMediaItem> = Set()

  @State private var importLocalFiles = ImportLocalFiles()
  @State private var localFilesItems: [LocalFileSystemMediaItem] = []
  @State private var isLocalFilesSelected: Bool = false
  @State private var selectedLocalFilesItems: Set<LocalFileSystemMediaItem> = Set()
  @State private var selectedLocalDirectory: URL?

  @State private var duplicateCount = 0
  @State private var progressCounter: ImportProgressCounter? = nil
  @State private var progressUpdateTrigger = UUID()

  // MARK: - Apple Photo Contents
  var applePhotosContent: some View {
    VStack(spacing: 8) {
      // Import All button - only visible when there are items that can be imported
      if appleMediaItems.count > duplicateCount {
        HStack {
          Spacer()
          if let importProgress = self.progressCounter {
            HStack {
              Text("\(importProgress.doneItemsCount) / \(importProgress.totalItemsCount)")
              ProgressView(
                value: Double(importProgress.doneItemsCount),
                total: Double(importProgress.totalItemsCount)
              )
              .frame(width: 120)
              .id(progressUpdateTrigger)
            }
          } else if appleMediaItems.count > 0 {
            Text(availabilityLabelText(regarding: appleMediaItems))
          }

          Button(importButtonText(forSelection: selectedAppleMediaItems)) {
            Task {
              self.showStatus("Import started")

              let importProgress = URLImportProgressCounter()
              self.progressCounter = importProgress

              let importCallbacks = ImportCallbacks(
                onMediaImported: { mediaItem in
                  self.progressUpdateTrigger = UUID()
                },
                onMediaSkipped: { mediaItem in },
                onComplete: {
                  print("Done importing \(importProgress.doneItemsCount) items")
                  self.showStatus("Done importing \(importProgress.doneItemsCount) items")
                  self.progressCounter = nil
                },
                onError: { error in
                  showError("Failed to import: \(error.localizedDescription)")
                }
              )
              await self.doImportApplePhotos(
                importCallbacks: importCallbacks, progressCounter: importProgress)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(appleMediaItems.count <= duplicateCount || self.progressCounter != nil)
        }
        .padding(.trailing, 16)
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
            .padding(.bottom, 20)
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
            cellWidth: CGFloat(gridCellSize),
            disableDuplicates: true,
            onDuplicateCountChange: { duplicateCount = $0 }
          )
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - USB Device Contents
  var deviceContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Import All button - only visible when there are items that can be imported
      if deviceMediaItems.count > duplicateCount {
        HStack {
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
          .disabled(deviceMediaItems.count <= duplicateCount || self.progressCounter != nil)
        }
        .padding(.trailing, 16)
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
              cellWidth: CGFloat(gridCellSize),
              disableDuplicates: true,
              onDuplicateCountChange: { duplicateCount = $0 }
            )
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .padding(.bottom, 20)
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
            .padding(.bottom, 20)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - Local Files Contents
  var localFilesContent: some View {
    VStack(spacing: 8) {
      // Import All button - only visible when there are items that can be imported
      if localFilesItems.count > duplicateCount {
        HStack {
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
          .disabled(localFilesItems.count <= duplicateCount || self.progressCounter != nil)
        }
        .padding(.trailing, 16)
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
          .padding(.bottom, 20)
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
            cellWidth: CGFloat(gridCellSize),
            disableDuplicates: true,
            onDuplicateCountChange: { duplicateCount = $0 }
          )
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
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
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Import Photos")
            .font(.title2)
            .fontWeight(.semibold)
            .padding(.horizontal)

          // Collapsible Source Sections
          VStack(spacing: 8) {
            // Devices Section
            DisclosureGroup(
              isExpanded: $isImportFromDeviceSelected,
              content: {
                deviceContent
                  .padding(.vertical, 8)
              },
              label: {
                HStack {
                  Image(systemName: "iphone.and.arrow.forward")
                    .foregroundColor(.green)
                  Text("Devices")
                    .font(.headline)
                  Spacer()
                  if !importFromDevice.detectedDevices.isEmpty {
                    Text("\(importFromDevice.detectedDevices.count) connected")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }
              }
            )
            .disclosureGroupStyle(CustomDisclosureGroupStyle())
            .onChange(of: isImportFromDeviceSelected) { oldValue, newValue in
              if newValue {
                isLocalFilesSelected = false
                isApplePhotosSelected = false
              }
            }

            // Local Files Section
            DisclosureGroup(
              isExpanded: $isLocalFilesSelected,
              content: {
                localFilesContent
                  .padding(.vertical, 8)
              },
              label: {
                HStack {
                  Image(systemName: "folder")
                    .foregroundColor(.blue)
                  Text("Local Files")
                    .font(.headline)
                  Spacer()
                }
              }
            )
            .disclosureGroupStyle(CustomDisclosureGroupStyle())
            .onChange(of: isLocalFilesSelected) { oldValue, newValue in
              if newValue {
                isImportFromDeviceSelected = false
                isApplePhotosSelected = false
              }
            }

            // Apple Photos Section
            DisclosureGroup(
              isExpanded: $isApplePhotosSelected,
              content: {
                applePhotosContent
                  .padding(.vertical, 8)
              },
              label: {
                HStack {
                  Image(systemName: "photo.on.rectangle.angled")
                    .foregroundColor(.orange)
                  Text("Apple Photos")
                    .font(.headline)
                  Spacer()
                }
              }
            )
            .disclosureGroupStyle(CustomDisclosureGroupStyle())
            .onChange(of: isApplePhotosSelected) { oldValue, newValue in
              if newValue {
                isImportFromDeviceSelected = false
                isLocalFilesSelected = false
              }
            }
          }
          .padding(.horizontal)
        }
        .padding(.vertical)
      }

      // Import directory section at the bottom (fixed)
      ImportDirectorySection()
        .padding(.horizontal)
        .background(Color(NSColor.controlBackgroundColor))
    }
    .background(Color(NSColor.controlBackgroundColor))
    .onDisappear {
      Task {
        await importFromDevice.cancelAllThumbnails()
        await importFromDevice.cancelAllDownloads()
      }
      importFromDevice.stopScanning()
    }
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
      self.selectedApplePhotosLibrary = panel.urls.first!
      if let photosLib = self.selectedApplePhotosLibrary {
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
            from: photosLib,
            with: importCallbacks
          )
        }
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

  private func doImportApplePhotos(
    importCallbacks: ImportCallbacks,
    progressCounter: URLImportProgressCounter
  ) async {
    guard let photosLib = selectedApplePhotosLibrary else { return }

    self.progressCounter = progressCounter  // FIXME should remove self.progressCount if possible

    let items: [ApplePhotosMediaItem] =
      self.selectedAppleMediaItems.isEmpty
      ? self.appleMediaItems : Array(self.selectedAppleMediaItems) as! [ApplePhotosMediaItem]

    do {
      try await importApplePhotos.importItems(
        items: items,
        from: photosLib,
        to: directoryManager.importDirectory,
        with: importCallbacks,
        progress: progressCounter
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
        to: directoryManager.importDirectory,
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

class ScanCallbacks: @unchecked Sendable {
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

class ImportCallbacks: @unchecked Sendable {
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

class ImportProgressCounter: ObservableObject, @unchecked Sendable {
  private var allItems: Set<MediaItem> = Set()
  @Published var doneItemsCount: Int = 0
  @Published var totalItemsCount: Int = 0

  var inProgress: Bool {
    totalItemsCount > 0 && doneItemsCount < totalItemsCount
  }

  func setItems(items: [MediaItem]) {
    for item in items {
      self.add(mediaItem: item)
    }
    self.totalItemsCount = self.allItems.count
  }

  func add(mediaItem: MediaItem) {
    self.allItems.insert(mediaItem)
  }

  func processed(mediaItem: MediaItem) {
    self.allItems.remove(mediaItem)
    self.doneItemsCount += 1
  }

  func getAllMediaItems() -> Set<MediaItem> {
    return self.allItems
  }
}

class URLImportProgressCounter: ImportProgressCounter, @unchecked Sendable {
  private var allURLs: Set<URL> = Set()
  private var mediaItemLookup: [URL: MediaItem] = [:]
  private var doneURLsCount: Int = 0
  private var totalURLsCount: Int = 0

  override func add(mediaItem: MediaItem) {
    if let item = mediaItem as? LocalFileSystemMediaItem {
      self.allURLs.insert(item.originalUrl)
      self.totalURLsCount = self.allURLs.count
      self.mediaItemLookup[item.originalUrl] = mediaItem

      if let edited = item.editedUrl {
        self.allURLs.insert(edited)
        self.totalURLsCount = self.allURLs.count
        self.mediaItemLookup[edited] = mediaItem
      }

      if let live = item.liveUrl {
        self.allURLs.insert(live)
        self.totalURLsCount = self.allURLs.count
        self.mediaItemLookup[live] = mediaItem
      }

      super.add(mediaItem: mediaItem)
    }
  }

  func countTotalURLs() -> Int {
    return self.totalURLsCount
  }

  func countDoneURLs() -> Int {
    return self.doneURLsCount
  }

  func processed(url: URL) -> MediaItem? {
    self.allURLs.remove(url)
    self.doneURLsCount += 1
    let mediaItemRemoved = self.mediaItemLookup.removeValue(forKey: url)
    if let item = mediaItemRemoved {
      let setAfterRemoved = Set(self.mediaItemLookup.values)
      if setAfterRemoved.contains(item) == false {
        super.processed(mediaItem: item)
        return item
      }
    }
    return nil
  }
}

class CameraFileImportProgressCounter: ImportProgressCounter, @unchecked Sendable {
  private var allCameraItems: Set<ICCameraItem> = Set()
  private var mediaItemLookup: [ICCameraItem: MediaItem] = [:]
  private var doneCameraItemsCount: Int = 0
  private var totalCameraItemsCount: Int = 0

  override func add(mediaItem: MediaItem) {
    if let item = mediaItem as? ConnectedDeviceMediaItem {
      self.allCameraItems.insert(item.originalItem)
      self.totalCameraItemsCount = self.allCameraItems.count
      self.mediaItemLookup[item.originalItem] = mediaItem

      if let edited = item.editedItem {
        self.allCameraItems.insert(edited)
        self.totalCameraItemsCount = self.allCameraItems.count
        self.mediaItemLookup[edited] = mediaItem
      }

      if let live = item.liveItem {
        self.allCameraItems.insert(live)
        self.totalCameraItemsCount = self.allCameraItems.count
        self.mediaItemLookup[live] = mediaItem
      }

      super.add(mediaItem: mediaItem)
    }
  }

  func countTotalCameraItems() -> Int {
    return self.totalCameraItemsCount
  }

  func countDoneCameraItems() -> Int {
    return self.doneCameraItemsCount
  }

  func getAllCameraItems() -> Set<ICCameraItem> {
    return allCameraItems
  }

  func processed(cameraItem: ICCameraItem) -> MediaItem? {
    self.allCameraItems.remove(cameraItem)
    self.doneCameraItemsCount += 1
    let mediaItemRemoved = self.mediaItemLookup.removeValue(forKey: cameraItem)
    if let item = mediaItemRemoved {
      let setAfterRemoved = Set(self.mediaItemLookup.values)
      if setAfterRemoved.contains(item) == false {
        super.processed(mediaItem: item)
        return item
      }
    }
    return nil
  }
}
