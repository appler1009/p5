import ImageCaptureCore
import SwiftUI

// MARK: - Device Media Item

struct DeviceMediaItem: Identifiable {
  let id = UUID()
  let cameraItem: ICCameraItem
  var thumbnail: Image?
  var isThumbnailLoading = false

  var name: String? { cameraItem.name }
  var uti: String? { cameraItem.uti }

  init(cameraItem: ICCameraItem) {
    self.cameraItem = cameraItem
  }
}

// MARK: - Import View

struct ImportView: View {
  @State private var isScanning = false
  @State private var connectionMessage = "Scanning for connected iPhones..."
  @State private var detectedDevices: [ICCameraDevice] = []
  @State private var deviceBrowser: ICDeviceBrowser?
  @State private var deviceDelegate: DeviceDelegate?
  @State private var hasInitialized = false
  @State private var selectedDevice: ICCameraDevice?
  @State private var deviceMediaItems: [DeviceMediaItem] = []
  @State private var isLoadingDeviceContents = false
  @State private var deviceConnectionError: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      // Sidebar
      VStack(alignment: .leading, spacing: 16) {
        Text("Sources")
          .font(.headline)
          .padding(.bottom, 8)

        VStack(spacing: 12) {
          Button(action: {
            scanForDevices()
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

        if !detectedDevices.isEmpty {
          Divider()

          VStack(alignment: .leading, spacing: 8) {
            Text("Connected Devices")
              .font(.subheadline)
              .fontWeight(.medium)

            ForEach(detectedDevices, id: \.name) { device in
              HStack {
                Image(systemName: "iphone")
                  .foregroundColor(.green)
                Text(device.name ?? "Unknown iPhone")
                  .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button("Select") {
                  selectDevice(device)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedDevice?.name == device.name)
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
        if let selectedDevice = selectedDevice {
          // Show device contents
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              Image(systemName: "iphone")
                .foregroundColor(.green)
              Text("Photos from \(selectedDevice.name ?? "iPhone")")
                .font(.title2)
                .fontWeight(.semibold)
              Spacer()
              Button("Import Selected") {
                // TODO: Implement import selected items
              }
              .buttonStyle(.borderedProminent)
              .disabled(deviceMediaItems.isEmpty)
            }

            if isLoadingDeviceContents {
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
                    if let device = self.selectedDevice {
                      selectDevice(device)
                    }
                  }
                  .buttonStyle(.borderedProminent)
                  .controlSize(.large)

                  Button("Scan for Devices") {
                    scanForDevices()
                  }
                  .buttonStyle(.bordered)
                  .controlSize(.large)
                }
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .padding()
            } else if deviceMediaItems.isEmpty {
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                  ForEach(deviceMediaItems.indices, id: \.self) { index in
                    let item = deviceMediaItems[index]
                    VStack {
                      // Display thumbnail if available, otherwise show placeholder
                      ZStack {
                        RoundedRectangle(cornerRadius: 8)
                          .fill(Color.gray.opacity(0.2))
                          .frame(height: 120)

                        if let thumbnail = item.thumbnail {
                          thumbnail
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if item.isThumbnailLoading {
                          ProgressView()
                            .scaleEffect(0.8)
                        } else {
                          Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        }
                      }

                      Text(item.name ?? "Unnamed")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                  }
                }
                .padding()
              }
            }
          }
          .padding()
        } else if isScanning {
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Scanning for connected devices...")
              .font(.headline)
              .foregroundColor(.primary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if detectedDevices.isEmpty {
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
                scanForDevices()
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
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
    .onAppear {
      if !hasInitialized {
        hasInitialized = true
        scanForDevices()
      }
    }
    .onDisappear {
      stopScanning()
    }
    .frame(minWidth: 700, minHeight: 500)
  }

  private func scanForDevices() {
    isScanning = true
    detectedDevices.removeAll()

    // Stop existing browser if it's running
    if let existingBrowser = deviceBrowser {
      existingBrowser.stop()
      deviceBrowser = nil
    }

    // Create a new device browser
    let browser = ICDeviceBrowser()

    // Create delegate - no weak reference needed for struct
    let delegate = DeviceDelegate(
      onDeviceFound: { device in
        print("DEBUG: ICDevice found: \(device.name ?? "Unknown")")

        if let cameraDevice = device as? ICCameraDevice {
          print("DEBUG: ICCameraDevice found: \(cameraDevice.name ?? "Unknown")")
          print("DEBUG: Device capabilities: \(cameraDevice.capabilities)")
          print("DEBUG: Device name: \(cameraDevice.name ?? "Unknown")")

          // Check for iPhone indicators
          let deviceName = cameraDevice.name ?? "Unknown"
          let deviceType = deviceName.lowercased()

          // Simple iPhone detection - just check the device name
          DispatchQueue.main.async {
            if deviceType.contains("iphone")
              && !self.detectedDevices.contains(where: { $0.name == cameraDevice.name })
            {
              self.detectedDevices.append(cameraDevice)
              print("DEBUG: Added iPhone via ImageCapture: \(deviceName)")
            } else {
              print("DEBUG: Device found but not identified as iPhone: \(deviceName)")
            }
          }
        }
      },
      onDeviceRemoved: { device in
        print("DEBUG: ICDevice removed: \(device.name ?? "Unknown")")
        DispatchQueue.main.async {
          self.detectedDevices.removeAll { $0.name == device.name }
          // If the removed device was selected, clear selection
          if self.selectedDevice?.name == device.name {
            self.selectedDevice = nil
            self.deviceMediaItems = []
          }
        }
      },
      onDeviceDisconnected: { device in
        print("DEBUG: Device disconnected: \(device.name ?? "Unknown")")

        // Handle device removal - clear selection if this was our selected device
        DispatchQueue.main.async {
          if device.name == self.selectedDevice?.name {
            print("DEBUG: Selected device was removed, clearing selection")
            self.selectedDevice = nil
            self.deviceMediaItems = []
            self.deviceConnectionError = """
              iPhone was disconnected. Please:

              1. Check that your iPhone is still connected via USB
              2. Wake up your iPhone if it went to sleep
              3. Try selecting the device again from the sidebar

              If the device keeps disconnecting, try:
              • Using a different USB port
              • Using a different USB cable
              • Disabling USB power management in System Settings > Energy Saver
              """
          }
        }
      }
    )

    browser.delegate = delegate
    browser.start()

    // Store references
    deviceBrowser = browser
    deviceDelegate = delegate

    // Keep browser running longer to maintain device connections
    // Only stop after a much longer timeout to prevent device disconnection
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {  // 60 seconds instead of 5
      self.stopScanning()
    }
  }

  private func selectDevice(_ device: ICCameraDevice) {
    selectedDevice = device
    deviceMediaItems = []
    deviceConnectionError = nil
    isLoadingDeviceContents = true

    // Set the device delegate
    device.delegate = deviceDelegate

    // Request to open session with the device
    device.requestOpenSession { error in
      DispatchQueue.main.async {
        if let error = error {
          self.isLoadingDeviceContents = false
          print("Failed to open session with device: \(error)")

          // Handle specific error cases
          let errorCode = (error as NSError).code
          if errorCode == -9943 {
            // Device is locked or not trusted - provide comprehensive guidance
            self.deviceConnectionError = """
              iPhone access denied. Please ensure:

              1. Your iPhone is unlocked
              2. When prompted on your iPhone, select "Allow" for "Trust This Computer"
              3. On your iPhone, when asked about USB accessories, choose "Allow access to photos/media"
                 (NOT just "Trust for charging")
              4. Try a different USB port or cable if connection issues persist

              Disconnect and reconnect the USB cable, then unlock your iPhone and select the media access option.
              """
          } else {
            self.deviceConnectionError =
              "Failed to connect to device: \(error.localizedDescription)"
          }
          return
        }

        print("DEBUG: Session opened successfully, accessing contents...")

        // Try to access contents directly after opening session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self.checkDeviceContents(device)
        }
      }
    }
  }

  private func checkDeviceContents(_ device: ICCameraDevice) {
    print("DEBUG: Checking device contents...")
    print("DEBUG: Device capabilities: \(device.capabilities)")
    print("DEBUG: Device contents count: \(device.contents?.count ?? 0)")

    // Debug: print all contents regardless of type
    if let contents = device.contents {
      print("DEBUG: All contents items:")
      for (index, item) in contents.enumerated() {
        print(
          "DEBUG: Item \(index): name=\(item.name ?? "nil"), uti=\(item.uti ?? "nil"), type=\(type(of: item))"
        )
      }

      // Check if we found the DCIM folder - this is a good sign!
      let dcimFolder = contents.first { item in
        item.name?.uppercased() == "DCIM" && item is ICCameraFolder
      }

      if let dcimFolder = dcimFolder as? ICCameraFolder {
        print("DEBUG: Found DCIM folder! Checking its contents...")
        // Check DCIM folder contents directly
        self.checkDCIMContents(dcimFolder)
        return
      }

      // Fallback: filter for any media items at root level
      let cameraItems = contents.filter { item in
        if let uti = item.uti {
          let isMedia = uti.hasPrefix("public.image") || uti.hasPrefix("public.video")
          print("DEBUG: Item uti=\(uti), isMedia=\(isMedia)")
          return isMedia
        }
        print("DEBUG: Item has no uti")
        return false
      }

      self.deviceMediaItems = cameraItems.map { DeviceMediaItem(cameraItem: $0) }

      print("DEBUG: Found \(self.deviceMediaItems.count) media items at root level")

      if self.deviceMediaItems.isEmpty {
        print("DEBUG: No media items found at root level")
        // Check if we have DCIM folder but couldn't access it
        let hasDCIM = contents.contains { item in
          item.name?.uppercased() == "DCIM"
        }

        if hasDCIM {
          self.deviceConnectionError = """
            ✅ Good news! Found DCIM folder on your iPhone, but can't access its contents yet.

            The device is connecting with media access capabilities: \(device.capabilities)

            Try:
            1. Ensure your iPhone screen is unlocked
            2. Check that you selected "Allow access to photos/media" (not just charging)
            3. Try disconnecting and reconnecting the USB cable
            4. If using a USB hub, connect directly to your Mac

            The DCIM folder was detected, which means media access is partially working.
            """
        } else {
          self.deviceConnectionError = """
            Device connected with capabilities: \(device.capabilities)

            No DCIM folder found. This could mean:
            1. Your iPhone has no photos/videos to share
            2. Photos are only stored in iCloud (not accessible via USB)
            3. Device permissions are still restricted

            Check if your Camera Roll has any photos.
            """
        }
      }

      self.isLoadingDeviceContents = false
    } else {
      print("DEBUG: device.contents is nil, retrying...")
      // Retry after a short delay in case contents aren't ready yet
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        if self.isLoadingDeviceContents {
          print("DEBUG: Retrying content check...")
          self.checkDeviceContents(device)
        }
      }
    }
  }

  private func checkDCIMContents(_ dcimFolder: ICCameraFolder) {
    print("DEBUG: Checking DCIM folder contents...")
    if let folderContents = dcimFolder.contents {
      print("DEBUG: DCIM folder has \(folderContents.count) items")

      // Look for subfolders (like 100APPLE, 101APPLE, etc.) or media files
      var allCameraItems: [ICCameraItem] = []

      for item in folderContents {
        if let subfolder = item as? ICCameraFolder {
          print("DEBUG: Found subfolder: \(subfolder.name ?? "unnamed")")
          if let subfolderContents = subfolder.contents {
            let mediaInSubfolder = subfolderContents.filter { subItem in
              if let uti = subItem.uti {
                return uti.hasPrefix("public.image") || uti.hasPrefix("public.video")
              }
              return false
            }
            allCameraItems.append(contentsOf: mediaInSubfolder)
            print(
              "DEBUG: Found \(mediaInSubfolder.count) media items in \(subfolder.name ?? "unnamed")"
            )
          }
        } else if let uti = item.uti, uti.hasPrefix("public.image") || uti.hasPrefix("public.video")
        {
          allCameraItems.append(item)
          print("DEBUG: Found media item: \(item.name ?? "unnamed")")
        }
      }

      // Create DeviceMediaItem objects
      self.deviceMediaItems = allCameraItems.map { DeviceMediaItem(cameraItem: $0) }
      print("DEBUG: Total media items found: \(allCameraItems.count)")

      // TODO: Implement thumbnail loading through ICDeviceDelegate or alternative approach
      self.requestThumbnailsForVisibleItems()

      if allCameraItems.isEmpty {
        self.deviceConnectionError = """
          ✅ DCIM folder found and accessible!

          However, no photos or videos were found inside. This could mean:
          1. Your Camera Roll is empty
          2. Photos are only in iCloud (not downloaded to device)
          3. Media files are in a different location

          Check your iPhone's Photos app - do you have any photos in your Camera Roll?
          """
      }

      self.isLoadingDeviceContents = false
    } else {
      print("DEBUG: DCIM folder contents is nil")
      self.deviceConnectionError =
        "DCIM folder found but contents are not accessible. Try reconnecting the device."
      self.isLoadingDeviceContents = false
    }
  }

  private func requestThumbnailsForVisibleItems() {
    // Load thumbnails in smaller batches to avoid overwhelming the device
    // Start with first 20, then load more as needed
    let initialBatchSize = min(20, deviceMediaItems.count)

    for i in 0..<initialBatchSize {
      let mediaItem = deviceMediaItems[i]
      if mediaItem.thumbnail == nil && !mediaItem.isThumbnailLoading {
        requestThumbnail(for: mediaItem, at: i)
      }
    }

    // Schedule loading of additional thumbnails after the first batch
    if deviceMediaItems.count > initialBatchSize {
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        self.loadNextThumbnailBatch(startingFrom: initialBatchSize)
      }
    }
  }

  private func loadNextThumbnailBatch(startingFrom startIndex: Int) {
    let batchSize = 15  // Load 15 more thumbnails
    let endIndex = min(startIndex + batchSize, deviceMediaItems.count)

    for i in startIndex..<endIndex {
      let mediaItem = deviceMediaItems[i]
      if mediaItem.thumbnail == nil && !mediaItem.isThumbnailLoading {
        requestThumbnail(for: mediaItem, at: i)
      }
    }

    // Continue loading more batches if needed
    if endIndex < deviceMediaItems.count {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        self.loadNextThumbnailBatch(startingFrom: endIndex)
      }
    }
  }

  private func requestThumbnail(for mediaItem: DeviceMediaItem, at index: Int) {
    // Mark as loading
    var updatedItem = mediaItem
    updatedItem.isThumbnailLoading = true
    deviceMediaItems[index] = updatedItem

    print("DEBUG: Requesting thumbnail for item: \(mediaItem.name ?? "unnamed")")

    // Request thumbnail asynchronously
    mediaItem.cameraItem.requestThumbnail()

    // Check for thumbnail after a longer delay (some thumbnails take time to generate)
    // Use different delays for different batches to avoid overwhelming the device
    let delay = index < 20 ? 1.0 : 2.0
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      self.checkForThumbnail(mediaItem, at: index)
    }
  }

  private func checkForThumbnail(_ mediaItem: DeviceMediaItem, at index: Int) {
    // Check if thumbnail became available using KVC
    let thumbnailImage: CGImage? = {
      // Try to access thumbnail property
      if mediaItem.cameraItem.responds(to: Selector("thumbnail")) {
        return mediaItem.cameraItem.value(forKey: "thumbnail") as! CGImage?
      }
      return nil
    }()

    if let thumbnailImage = thumbnailImage {
      var finalItem = deviceMediaItems[index]
      finalItem.isThumbnailLoading = false

      #if canImport(UIKit)
        let uiImage = UIImage(cgImage: thumbnailImage)
        finalItem.thumbnail = Image(uiImage: uiImage)
      #elseif canImport(AppKit)
        let nsImage = NSImage(
          cgImage: thumbnailImage,
          size: NSSize(width: thumbnailImage.width, height: thumbnailImage.height))
        finalItem.thumbnail = Image(nsImage: nsImage)
      #endif

      deviceMediaItems[index] = finalItem
      print("DEBUG: Loaded thumbnail for \(finalItem.name ?? "unnamed")")
    } else {
      // No thumbnail available
      var finalItem = deviceMediaItems[index]
      finalItem.isThumbnailLoading = false
      deviceMediaItems[index] = finalItem
      print("DEBUG: No thumbnail available for \(finalItem.name ?? "unnamed")")
    }
  }

  private func stopScanning() {
    isScanning = false

    // Don't stop the browser if we have active device connections
    if let browser = deviceBrowser, selectedDevice == nil {
      print("DEBUG: Stopping device browser (no active device connections)")
      browser.stop()
      deviceBrowser = nil
      deviceDelegate = nil
    } else if selectedDevice != nil {
      print("DEBUG: Keeping device browser running (active device connection)")
      // Keep browser running for active device connections
    }

    if detectedDevices.isEmpty {
      connectionMessage = """
        No iPhones detected via USB.

        Try:
        • Unlock your iPhone
        • Tap "Trust This Computer" on iPhone
        • Use Apple USB-C cable
        • Check if iPhone appears in Image Capture app
        • Grant Full Disk Access in System Settings
        • Restart your iPhone
        """
    }
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

    for url in urls {
      let fileName = url.lastPathComponent
      let destinationUrl = importDirectory.appendingPathComponent(fileName)

      do {
        // Copy file to import directory
        try FileManager.default.copyItem(at: url, to: destinationUrl)

        // Add to MediaScanner
        let mediaType: MediaType
        if url.pathExtension.lowercased().contains("jpg")
          || url.pathExtension.lowercased().contains("heic")
          || url.pathExtension.lowercased().contains("png")
        {
          mediaType = .photo
        } else {
          mediaType = .video
        }

        let mediaItem = MediaItem(
          id: Int.random(in: 1...Int.max),
          url: destinationUrl,
          type: mediaType,
          metadata: nil,
          displayName: nil
        )

        MediaScanner.shared.items.append(mediaItem)

      } catch {
        print("Failed to import file \(url.lastPathComponent): \(error)")
      }
    }

    // Trigger metadata extraction and refresh
    Task {
      await MediaScanner.shared.scan(directories: DirectoryManager.shared.directories)
      dismiss()
    }
  }
}

// MARK: - Device Delegate for ImageCaptureCore
class DeviceDelegate: NSObject, ICDeviceBrowserDelegate, ICDeviceDelegate {
  let onDeviceFound: (ICDevice) -> Void
  let onDeviceRemoved: (ICDevice) -> Void
  let onDeviceDisconnected: (ICDevice) -> Void

  init(
    onDeviceFound: @escaping (ICDevice) -> Void,
    onDeviceRemoved: @escaping (ICDevice) -> Void,
    onDeviceDisconnected: @escaping (ICDevice) -> Void
  ) {
    self.onDeviceFound = onDeviceFound
    self.onDeviceRemoved = onDeviceRemoved
    self.onDeviceDisconnected = onDeviceDisconnected
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    onDeviceFound(device)
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    onDeviceRemoved(device)
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
    print("DEBUG: ICDevice name changed: \(device.name ?? "Unknown")")
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeSharingState device: ICDevice) {
    print("DEBUG: ICDevice sharing state changed: \(device.name ?? "Unknown")")
  }

  // ICDeviceDelegate methods
  func deviceDidBecomeReady(_ device: ICDevice) {
    print("DEBUG: ICDevice became ready: \(device.name ?? "Unknown")")
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    print(
      "DEBUG: ICDevice session opened: \(device.name ?? "Unknown"), error: \(error?.localizedDescription ?? "none")"
    )
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    print(
      "DEBUG: ICDevice session closed: \(device.name ?? "Unknown"), error: \(error?.localizedDescription ?? "none")"
    )
  }

  func didRemove(_ device: ICDevice) {
    print("DEBUG: ICDevice removed: \(device.name ?? "Unknown")")
    // Use the callback to handle device disconnection
    onDeviceDisconnected(device)
  }
}

// ICCameraDeviceDelegate methods for thumbnails
