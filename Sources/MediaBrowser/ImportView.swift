import CryptoKit
import ImageCaptureCore
import SwiftUI

// MARK: - Import View

struct ImportView: View {
  @ObservedObject var importFromDevice = ImportFromDevice()
  @State private var isScanningDevices = false
  @State private var duplicateCount = 0
  @State private var importStatus: String?
  @State private var deviceConnectionError: String?
  @State private var isImportFromDeviceSelected: Bool = false
  @State private var deviceMediaItems: [ConnectedDeviceMediaItem] = []

  @State private var importApplePhotos = ImportApplePhotos()
  @State private var selectedApplePhotosLibrary: URL?
  @State private var isApplePhotosSelected: Bool = false
  @State private var isReadingApplePhotos: Bool = false
  @State private var appleMediaItems: [ApplePhotosMediaItem] = []

  @State private var localFilesItems: [LocalFileSystemMediaItem] = []
  @State private var isLocalFilesSelected: Bool = false

  @Environment(\.dismiss) private var dismiss

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
          Text("Total \(appleMediaItems.count)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Button("Import All") {
          Task {
            self.showStatus("Import started")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(appleMediaItems.isEmpty)
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
            selectedItems: $importApplePhotos.selectedMediaItems,
            onSelectionChange: { selectedItems in
              importApplePhotos.selectedMediaItems = selectedItems
            },
            onItemDoubleTap: { _ in },
            minCellWidth: 80
          )
          .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

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
          let availableCount = deviceMediaItems.count - duplicateCount
          let totalCount = deviceMediaItems.count
          Text("\(availableCount) available for import out of \(totalCount) total")
        }
        Button("Import All") {
          Task {
            self.showStatus("Download started")
            await importFromDevice.requestDownloads()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(deviceMediaItems.count <= duplicateCount)
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
              selectedItems: $importFromDevice.selectedMediaItems,
              onSelectionChange: { selectedItems in
                importFromDevice.selectedMediaItems = selectedItems
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
          Text("Total \(localFilesItems.count)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Button("Import All") {
          Task {
            self.showStatus("Import started")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(localFilesItems.isEmpty)
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
            selectedItems: .constant(Set<MediaItem>()),
            onSelectionChange: { _ in },
            onItemDoubleTap: { _ in },
            minCellWidth: 80
          )
          .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

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

  private func openLocalDirectoryPicker() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.image, .movie, .folder]
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.message = "Select photos and videos to import"
    panel.prompt = "Import"

    if panel.runModal() == .OK {
      do {
        // Clear existing items before starting new preview
        localFilesItems = []
        let localFiles = try ImportLocalFiles(directory: panel.urls.first!)
        Task {
          try await localFiles.previewPhotos { mediaItem in
            // Update applePhotosItems in real-time when new media is found
            localFilesItems.append(mediaItem)
          }
        }
      } catch {
        print("Error importing Local Files: \(error)")
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
      appleMediaItems = []
      Task {
        let _ = try await importApplePhotos.previewPhotos(
          from: panel.urls.first!,
          onMediaFound: { mediaItem in
            // Update applePhotosItems in real-time when new media is found
            appleMediaItems.insertSorted(mediaItem, by: \.thumbnailDate, order: .descending)
          },
          onComplete: {
            isReadingApplePhotos = false
          }
        )
      }
    }
  }

  private func scanForDevices() {
    let callbacks = ImportCallbacks(
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
      })

    importFromDevice.scanForDevices(with: callbacks)
  }

  private func browseMedia(from device: ICCameraDevice) {
    clearError()
    importFromDevice.selectDevice(device)
  }

  private func importManualFiles(_ urls: [URL]) {
    let importDirectory = DirectoryManager.shared.importDirectory
    var newImportedItems: [LocalFileSystemMediaItem] = []

    for url in urls {
      let fileName = url.lastPathComponent
      let destinationUrl = importDirectory.appendingPathComponent(fileName)

      do {
        // Copy file to import directory
        try FileManager.default.copyItem(at: url, to: destinationUrl)

        // Add to MediaScanner
        let mediaItem = LocalFileSystemMediaItem(
          id: -1,
          original: destinationUrl,
        )

        MediaScanner.shared.items.append(mediaItem)
        newImportedItems.append(mediaItem)

      } catch {
        print("Failed to import file \(url.lastPathComponent): \(error)")
      }
    }

    // Trigger metadata extraction and refresh
    Task {
      await MediaScanner.shared.scan(directories: DirectoryManager.shared.directories)

      // Notify about new imported items that are duplicates
      for item in newImportedItems {
        let baseName = item.displayName.extractBaseName()
        if DatabaseManager.shared.hasDuplicate(baseName: baseName, date: item.thumbnailDate) {
          NotificationCenter.default.post(name: .newMediaItemImported, object: item.id)
        }
      }

      dismiss()
    }
  }
}

// MARK: - Import Callback Handler

class ImportCallbacks {
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
