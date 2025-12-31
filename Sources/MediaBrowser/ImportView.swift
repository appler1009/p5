import CryptoKit
import SwiftUI

// MARK: - Import View

struct ImportView: View {
  @ObservedObject var importFromDevice = ImportFromDevice()
  @State private var hasInitialized = false
  @State private var duplicateCount = 0
  @State private var importStatus: String?
  @State private var deviceConnectionError: String?

  @Environment(\.dismiss) private var dismiss

  var deviceContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "iphone")
          .foregroundColor(.green)
        Text("Photos from \(importFromDevice.selectedDevice?.name ?? "iPhone")")
          .font(.title2)
          .fontWeight(.semibold)
        Spacer()
        Text(
          """
          \(importFromDevice.deviceMediaItems.count - duplicateCount) available for import out of \(importFromDevice.deviceMediaItems.count) total
          """
        )
        Button(
          "Import \(importFromDevice.selectedDeviceMediaItems.count > 0 ? "\(importFromDevice.selectedDeviceMediaItems.count) Selected" : "All")"
        ) {
          Task {
            self.showStatus("Download started")
            await importFromDevice.requestDownloads()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(importFromDevice.deviceMediaItems.count == duplicateCount)
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

      if let error = deviceConnectionError {
        HStack {
          Image(systemName: "exclamationmark.triangle")
            .foregroundColor(.red)
          Text(error)
            .foregroundColor(.red)
            .lineLimit(nil)
          Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
      }

      if importFromDevice.isLoadingDeviceContents {
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
            Button("Try Again") {
              if let device = importFromDevice.selectedDevice {
                importFromDevice.selectDevice(device)
              }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Scan for Devices") {
              importFromDevice.scanForDevices()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
      } else if importFromDevice.deviceMediaItems.isEmpty {
        VStack(spacing: 20) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 80))
            .foregroundColor(.secondary)

          VStack(spacing: 12) {
            Text("No Photos Found")
              .font(.title2)
              .fontWeight(.semibold)

            Text("This device doesn't have any photos or videos")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(spacing: 4) {
            SectionGridView(
              items: importFromDevice.deviceMediaItems,
              selectedItems: $importFromDevice.selectedDeviceMediaItems,
              onSelectionChange: { selectedItems in
                importFromDevice.selectedDeviceMediaItems = selectedItems
              },
              onItemDoubleTap: { _ in },  // No-op for import view
              minCellWidth: 80,
              disableDuplicates: true,
              onDuplicateCountChange: { duplicateCount = $0 }
            )
          }
          .padding()
        }
      }
    }
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
            importFromDevice.scanForDevices()
          }) {
            HStack {
              Image(systemName: "iphone.and.arrow.forward")
                .frame(width: 20)
              Text("iPhone (USB)")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)

          Button(action: {
            openFilePicker()
          }) {
            HStack {
              Image(systemName: "folder")
                .frame(width: 20)
              Text("Browse Files")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
        }

        if !importFromDevice.detectedDevices.isEmpty {
          Divider()

          VStack(alignment: .leading, spacing: 8) {
            Text("Connected Devices")
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
                  importFromDevice.selectDevice(device)
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

        Spacer()
      }
      .padding()
      .frame(minWidth: 280)
    } detail: {
      // Main content area
      VStack(spacing: 24) {
        if importFromDevice.selectedDevice != nil {
          // Show device contents
          deviceContent
            .padding()
        } else if importFromDevice.isScanning {
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Scanning for connected devices...")
              .font(.headline)
              .foregroundColor(.primary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if importFromDevice.detectedDevices.isEmpty {
          VStack(spacing: 20) {
            Image(systemName: "iphone.slash")
              .font(.system(size: 80))
              .foregroundColor(.secondary)

            VStack(spacing: 12) {
              Text("No iPhone Detected")
                .font(.title2)
                .fontWeight(.semibold)

              Text("Connect your iPhone via USB and select a device from the sidebar")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
              Button("Scan Devices") {
                importFromDevice.scanForDevices()
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)

              Button("Browse Files") {
                openFilePicker()
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
            }
          }
          .padding(40)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          VStack(spacing: 20) {
            Image(systemName: "iphone")
              .font(.system(size: 80))
              .foregroundColor(.secondary)

            VStack(spacing: 12) {
              Text("Select a Device")
                .font(.title2)
                .fontWeight(.semibold)

              Text("Choose an iPhone from the sidebar to view its photos")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(NSColor.controlBackgroundColor))
    }
    .navigationTitle("Import from iPhone")
    .onAppear {
      if !hasInitialized {
        hasInitialized = true
        // ThumbnailCache handles directory creation
        importFromDevice.scanForDevices()
      }
    }
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

  private func openFilePicker() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.image, .movie]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.message = "Select photos and videos to import"
    panel.prompt = "Import"

    if panel.runModal() == .OK {
      let urls = panel.urls
      importManualFiles(urls)
    }
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
