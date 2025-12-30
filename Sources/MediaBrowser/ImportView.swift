import CryptoKit
import ImageCaptureCore
import SwiftUI

// MARK: - Import View

struct ImportView: View {
  @State private var isScanning = false
  @State private var connectionMessage = "Scanning for connected iPhones..."
  @State private var detectedDevices: [ICCameraDevice] = []
  @State private var deviceBrowser: ICDeviceBrowser?
  @State private var deviceDelegate: DeviceDelegate?
  @State private var hasInitialized = false
  @State private var selectedDevice: ICCameraDevice?
  @State private var selectedDeviceMediaItems: Set<MediaItem> = []
  @State private var deviceMediaItems: [ConnectedDeviceMediaItem] = []
  @State private var isLoadingDeviceContents = false
  @State private var deviceConnectionError: String?
  @State private var thumbnailOperationsCancelled = false
  @State private var importStatus: String?
  @State private var isDownloading = false

  @Environment(\.dismiss) private var dismiss

  // Thumbnail coordination
  private let thumbnailState = CameraItemState()
  private let thumbnailLimiter = ConcurrencyLimiter(limit: 15)
  private let downloadState = CameraItemState()
  private let downloadLimiter = ConcurrencyLimiter(limit: 2)

  var deviceContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "iphone")
          .foregroundColor(.green)
        Text("Photos from \(selectedDevice?.name ?? "iPhone")")
          .font(.title2)
          .fontWeight(.semibold)
        Spacer()
        Button("Import Selected") {
          Task {
            await requestDownloads()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(deviceMediaItems.isEmpty)
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
          VStack(spacing: 4) {
            SectionGridView(
              items: deviceMediaItems,
              selectedItems: $selectedDeviceMediaItems,
              onSelectionChange: { selectedItems in
                selectedDeviceMediaItems = selectedItems
              },
              onItemDoubleTap: { _ in },  // No-op for import view
              minCellWidth: 80,
              disableDuplicates: false
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
        if selectedDevice != nil {
          // Show device contents
          deviceContent
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
        // ThumbnailCache handles directory creation
        scanForDevices()
      }
    }
    .onDisappear {
      Task {
        await self.thumbnailState.cancelAll()
        await self.thumbnailLimiter.cancelAll()
        await self.downloadState.cancelAll()
        await self.downloadLimiter.cancelAll()
      }
      stopScanning()
    }
    .frame(minWidth: 700, minHeight: 500)
  }

  // Group related camera items (Live Photos, edited photos, etc.)
  private func groupRelatedCameraItems(_ items: [ICCameraItem]) -> [ConnectedDeviceMediaItem] {
    var itemLookup: [String: ICCameraItem] = [:]

    for item in items {
      if let itemName = item.name {
        itemLookup[itemName] = item
      }
    }

    let itemNames = items.map { $0.name! }
    let mediaGroups = groupRelatedMedia(itemNames)
    return mediaGroups.compactMap { group in
      if let original = itemLookup[group.main] {
        return ConnectedDeviceMediaItem(
          id: -1,  // Will be replaced with a unique sequence number
          original: original,
          edited: group.edited != nil ? itemLookup[group.edited!] : nil,
          live: group.live != nil ? itemLookup[group.live!] : nil
        )
      } else {
        return nil
      }
    }
  }

  struct MediaEntry {
    let main: String
    let edited: String?
    let live: String?
  }

  func groupRelatedMedia(_ items: [String]) -> [MediaEntry] {
    var groups: [String: MediaEntry] = [:]

    let photoExtensions = [
      "HEIC", "HEIF", "JPG", "JPEG", "PNG", "TIF", "TIFF",
      "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "pef", "rw2", "dng",
    ]
    let videoExtensions = [
      "mov", "mp4", "m4v", "3gp", "3g2", "mkv", "webm", "avi",
      "mts", "m2ts", "mxf", "xavc", "r3d", "braw",
      "prores",
    ]

    // 1st pass - take list of photos while grouping edited photos
    let photoNames = items.filter { name in
      let ext = (name as NSString).pathExtension
      return photoExtensions.contains { $0.caseInsensitiveCompare(ext) == .orderedSame }
    }
    for photoName in photoNames {
      let baseName = photoName.extractBaseName()
      if let group = groups[baseName] {
        if group.main.count > photoName.count {
          // longer name must be the edited name
          groups[baseName] = .init(main: photoName, edited: group.main, live: nil)
        } else {
          groups[baseName] = .init(main: group.main, edited: photoName, live: nil)
        }
      } else {
        groups[baseName] = .init(main: photoName, edited: nil, live: nil)
      }
    }

    // 2nd pass - find videos of live photos from 1st pass
    let videoNames = items.filter { name in
      let ext = (name as NSString).pathExtension
      return videoExtensions.contains { $0.caseInsensitiveCompare(ext) == .orderedSame }
    }
    for videoName in videoNames {
      let baseName = videoName.extractBaseName()
      if let group = groups[baseName] {
        groups[baseName] = .init(main: group.main, edited: group.edited, live: videoName)
      }
    }

    // 3rd pass - add rest of videos as separate videos
    for videoName in videoNames {
      let baseName = videoName.extractBaseName()
      if let group = groups[baseName] {
        if group.live == videoName {
          // it's other video's live video; skip
          continue
        }
        if group.main.count > videoName.count {
          // longer name must be the edited version
          groups[baseName] = .init(main: videoName, edited: group.main, live: nil)
        } else {
          groups[baseName] = .init(main: group.main, edited: videoName, live: nil)
        }
      } else {
        groups[baseName] = .init(main: videoName, edited: nil, live: nil)
      }
    }

    return Array(groups.values)
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

        if let cameraDevice = device as? ICCameraDevice {

          // Check for iPhone indicators
          let deviceName = cameraDevice.name ?? "Unknown"
          let deviceType = deviceName.lowercased()

          // Simple iPhone detection - just check the device name
          DispatchQueue.main.async {
            if deviceType.contains("iphone")
              && !self.detectedDevices.contains(where: { $0.name == cameraDevice.name })
            {
              self.detectedDevices.append(cameraDevice)

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
            print(
              "DEBUG: Selected device was removed, clearing selection and cancelling thumbnail operations"
            )
            self.selectedDevice = nil
            self.deviceMediaItems = []
            self.thumbnailOperationsCancelled = true
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
            Task {
              await self.thumbnailState.cancelAll()
              await self.thumbnailLimiter.cancelAll()
              await self.downloadState.cancelAll()
              await self.downloadLimiter.cancelAll()
            }
          }
        }
      },
      onDownloadError: { error, file in
        DispatchQueue.main.async {
          let nsError = error as NSError
          if nsError.domain == "com.apple.ImageCaptureCore" && nsError.code == -9934 {
            self.showError(
              "Download failed: Device is busy or not ready. Please ensure the device is not taking photos, recording video, or syncing. Try again in a moment."
            )
          } else {
            self.showError("Download failed: \(error.localizedDescription)")
          }
        }
      },
      onDownloadSuccess: { file in
        DispatchQueue.main.async {
          self.showStatus("Successfully imported \(file?.name ?? "file")")
        }
      },
      thumbnailStateRef: thumbnailState
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
    thumbnailOperationsCancelled = false

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

        // Try to access contents directly after opening session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          Task {
            await self.checkDeviceContents(device)
          }
        }
      }
    }
  }

  private func checkDeviceContents(_ device: ICCameraDevice) async {
    if let contents = device.contents {

      // Check if we found the DCIM folder - this is a good sign!
      let dcimFolder = contents.first { item in
        item.name?.uppercased() == "DCIM" && item is ICCameraFolder
      }

      if let dcimFolder = dcimFolder as? ICCameraFolder {

        // Check DCIM folder contents directly
        await self.checkDCIMContents(dcimFolder)
        return
      }

      // Fallback: filter for any media items at root level
      let cameraItems = contents.filter { item in
        return item.isMedia()
      }

      print("DEBUG: Found \(self.deviceMediaItems.count) raw items at root level")

      // Group related camera items and create DeviceMediaItem objects
      self.deviceMediaItems = self.groupRelatedCameraItems(cameraItems)

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

      DispatchQueue.main.async {
        self.isLoadingDeviceContents = false
      }
    } else {
      print("DEBUG: device.contents is nil, retrying...")
      // Retry after a short delay in case contents aren't ready yet
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        if self.isLoadingDeviceContents {
          print("DEBUG: Retrying content check...")
          Task {
            await self.checkDeviceContents(device)
          }
        }
      }
    }
  }

  private func checkDCIMContents(_ dcimFolder: ICCameraFolder) async {
    if let folderContents = dcimFolder.contents {

      // Look for subfolders (like 100APPLE, 101APPLE, etc.) or media files
      var allCameraItems: [ICCameraItem] = []

      for item in folderContents {
        if let subfolder = item as? ICCameraFolder {

          if let subfolderContents = subfolder.contents {
            let mediaInSubfolder = subfolderContents.filter { subItem in
              return subItem.isMedia()
            }
            allCameraItems.append(contentsOf: mediaInSubfolder)

          }
        } else if item.isMedia() {
          allCameraItems.append(item)
          print("DEBUG: Found media item: \(item.name ?? "unnamed")")
        }
      }

      // Create DeviceMediaItem objects

      self.deviceMediaItems = self.groupRelatedCameraItems(allCameraItems)
      self.isLoadingDeviceContents = false

      await self.requestThumbnails()

      if allCameraItems.isEmpty {
        await MainActor.run {
          self.deviceConnectionError = """
            ✅ DCIM folder found and accessible!

            However, no photos or videos were found inside. This could mean:
            1. Your Camera Roll is empty
            2. Photos are only in iCloud (not downloaded to device)
            3. Media files are in a different location

            Check your iPhone's Photos app - do you have any photos in your Camera Roll?
            """
        }
      }

      print("DEBUG: About to set isLoadingDeviceContents = false")
      await MainActor.run {
        self.isLoadingDeviceContents = false
        print(
          "DEBUG: Set isLoadingDeviceContents = false on MainActor, deviceMediaItems.count = \(self.deviceMediaItems.count)"
        )
      }
    } else {
      print("DEBUG: DCIM folder contents is nil")
      await MainActor.run {
        self.deviceConnectionError =
          "DCIM folder found but contents are not accessible. Try reconnecting the device."
        self.isLoadingDeviceContents = false
      }
    }
  }

  private func requestThumbnails() async {
    await withTaskGroup(of: Void.self) { group in
      for mediaItem in deviceMediaItems {
        // Check if thumbnail already exists in local cache
        if ThumbnailCache.shared.thumbnailExists(mediaItem: mediaItem) {
          continue
        }

        let id = String(describing: mediaItem.id)
        let requested = await thumbnailState.markRequestedIfNeeded(id: id)
        guard requested else { continue }

        group.addTask { [thumbnailState, thumbnailLimiter] in
          await thumbnailLimiter.acquire()
          let task = Task { [thumbnailState] in
            defer { Task { await thumbnailLimiter.release() } }
            if Task.isCancelled { return }
            await self.checkForThumbnail(for: mediaItem)
            await thumbnailState.clearRunningTask(for: id)
          }
          await thumbnailState.setRunningTask(task, for: id)
          await task.value
        }
      }
    }
  }

  private func checkForThumbnail(for mediaItem: ConnectedDeviceMediaItem) async {
    do {
      if Task.isCancelled { return }
      let thumbnail = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<NSImage?, Error>) in
        Task {
          await thumbnailState.setPending(for: mediaItem.displayItem, continuation: continuation)
        }
        mediaItem.displayItem.requestThumbnail()
      }
      if Task.isCancelled { return }
      if let thumbnail = thumbnail {
        await MainActor.run {
          storeThumbnail(mediaItem: mediaItem, thumbnail: thumbnail)
        }
      }
    } catch {
      print("requestThumbnail failed for \(mediaItem.displayName): \(error)")
    }
  }

  private func storeThumbnail(mediaItem: ConnectedDeviceMediaItem, thumbnail: NSImage) {
    guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return
    }

    let width = cgImage.width
    let height = cgImage.height
    let side = min(width, height)

    let cropRect = CGRect(
      x: (width - side) / 2,
      y: (height - side) / 2,
      width: side,
      height: side
    )

    guard let croppedCG = cgImage.cropping(to: cropRect) else {
      return
    }

    let squareThumbnail = NSImage(size: NSSize(width: side, height: side))
    squareThumbnail.addRepresentation(NSBitmapImageRep(cgImage: croppedCG))

    ThumbnailCache.shared.storePreGeneratedThumbnail(squareThumbnail, mediaItem: mediaItem)
  }

  private func requestDownloads() async {
    var cameraItems: [ICCameraItem] = []
    selectedDeviceMediaItems.forEach { mediaItem in
      guard let connectedDeviceMediaItem = mediaItem as? ConnectedDeviceMediaItem else { return }
      cameraItems.append(connectedDeviceMediaItem.originalItem)
      print("\(connectedDeviceMediaItem.originalItem.name ?? "unknown") originalItem added")
      if let edited = connectedDeviceMediaItem.editedItem {
        cameraItems.append(edited)
        print(
          "\(connectedDeviceMediaItem.originalItem.name ?? "unknown") \(edited.name ?? "unknown") editedItem added"
        )
      } else {
        print("\(connectedDeviceMediaItem.originalItem.name ?? "unknown") no editedItem added")
      }
      if let live = connectedDeviceMediaItem.liveItem {
        cameraItems.append(live)
        print(
          "\(connectedDeviceMediaItem.originalItem.name ?? "unknown") \(live.name ?? "unknown") liveItem added"
        )
      } else {
        print("\(connectedDeviceMediaItem.originalItem.name ?? "unknown") no liveItem available")
      }
    }
    print("Items to download: \(cameraItems.count)")
    for item in cameraItems {
      print("Camera item: \(item.name ?? "unknown")")
    }

    await withTaskGroup(of: Void.self) { group in
      for cameraItem in cameraItems {
        // ICCameraFile is the subclass that supports downloading
        guard let cameraFile = cameraItem as? ICCameraFile else {
          return
        }

        let cameraFileId = String(describing: cameraFile.name!)  // FIXME
        let requested = await downloadState.markRequestedIfNeeded(id: cameraFileId)
        guard requested else { return }

        group.addTask { [downloadState, downloadLimiter] in
          await downloadLimiter.acquire()
          let task = Task { [downloadState] in
            if Task.isCancelled { return }
            await self.checkForDownload(
              for: cameraFile,
              onComplete: {
                Task { await downloadLimiter.release() }
                await downloadState.clearRunningTask(for: cameraFileId)
              })
          }
          await downloadState.setRunningTask(task, for: cameraFileId)
          await task.value
        }
      }
    }
  }

  private func checkForDownload(
    for cameraFile: ICCameraFile, onComplete: @escaping () async -> Void
  ) async {
    let cameraFileId = String(describing: cameraFile.name!)  // FIXME
    do {
      if Task.isCancelled { return }
      let _ = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<NSImage?, Error>) in
        Task {
          await downloadState.setPending(for: cameraFile, continuation: continuation)
        }

        // Request download of the camera file with completion handler
        let importDir = DirectoryManager.shared.importDirectory
        let options: [ICDownloadOption: Any] = [
          .downloadsDirectoryURL: importDir
        ]
        cameraFile.requestDownload(options: options) { downloadID, error in
          print("DEBUG: Download ID for \(cameraFileId): \(downloadID ?? "unknown")")

          DispatchQueue.main.async {
            self.isDownloading = false
          }

          if let error = error {
            print(
              "DEBUG: Download request failed for \(cameraFileId): \(error.localizedDescription)")
          } else {
            print(
              "DEBUG: Download request successful for \(cameraFileId), ID: \(downloadID ?? "none")")
            self.showStatus("Download started successfully")
          }

          if let fileName = cameraFile.name {
            let importDir = DirectoryManager.shared.importDirectory
            let downloadedPath = importDir.appendingPathComponent(fileName)
            do {
              let attributes = try FileManager.default.attributesOfItem(atPath: downloadedPath.path)
              if let downloadedSize = attributes[.size] as? NSNumber {
                if downloadedSize.uint64Value == cameraFile.fileSize {
                  print("Downloaded file size matches: \(downloadedSize)")
                } else {
                  print(
                    "Downloaded file size does not match: downloaded \(downloadedSize), expected \(cameraFile.fileSize)"
                  )
                }
              }
            } catch {
              print("Failed to get downloaded file size: \(error)")
            }
          }
          Task { await onComplete() }
        }
      }
    } catch {
      print("requestDownload failed for \(cameraFileId): \(error)")
    }
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

// MARK: - Thumbnail Coordination Actors
actor CameraItemState {
  private var requested: Set<String> = []
  private var pending: [ObjectIdentifier: CheckedContinuation<NSImage?, Error>] = [:]
  private var runningTasks: [String: Task<Void, Never>] = [:]

  func markRequestedIfNeeded(id: String) -> Bool {
    if requested.contains(id) { return false }
    requested.insert(id)
    return true
  }

  func setPending(for item: ICCameraItem, continuation: CheckedContinuation<NSImage?, Error>) {
    pending[ObjectIdentifier(item)] = continuation
  }

  func takePending(for item: ICCameraItem) -> CheckedContinuation<NSImage?, Error>? {
    pending.removeValue(forKey: ObjectIdentifier(item))
  }

  func setRunningTask(_ task: Task<Void, Never>, for id: String) {
    runningTasks[id] = task
  }

  func clearRunningTask(for id: String) {
    runningTasks[id] = nil
  }

  func cancelAll() {
    for (_, task) in runningTasks { task.cancel() }
    runningTasks.removeAll()
    pending.values.forEach { $0.resume(returning: nil) }
    pending.removeAll()
    requested.removeAll()
  }

  func cancel(id: String) {
    runningTasks[id]?.cancel()
    runningTasks[id] = nil
  }
}

actor ConcurrencyLimiter {
  private let limit: Int
  private var running = 0
  private var queue: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) { self.limit = limit }

  func acquire() async {
    if Task.isCancelled { return }
    if running < limit {
      running += 1
      return
    }
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
      queue.append(c)
    }
  }

  func release() async {
    if Task.isCancelled {
      running = max(0, running - 1)
      return
    }
    if !queue.isEmpty {
      let c = queue.removeFirst()
      c.resume()
    } else {
      running = max(0, running - 1)
    }
  }

  func cancelAll() {
    // Drain queue so waiters don't hang
    for c in queue { c.resume() }
    queue.removeAll()
    running = 0
  }
}

// MARK: - Device Delegate for ImageCaptureCore
class DeviceDelegate: NSObject, ICDeviceBrowserDelegate, ICDeviceDelegate, ICCameraDeviceDelegate {
  weak var thumbnailStateRef: AnyObject?

  let onDeviceFound: (ICDevice) -> Void
  let onDeviceRemoved: (ICDevice) -> Void
  let onDeviceDisconnected: (ICDevice) -> Void
  let onDownloadError: (Error, ICCameraFile?) -> Void
  let onDownloadSuccess: (ICCameraFile?) -> Void

  init(
    onDeviceFound: @escaping (ICDevice) -> Void,
    onDeviceRemoved: @escaping (ICDevice) -> Void,
    onDeviceDisconnected: @escaping (ICDevice) -> Void,
    onDownloadError: @escaping (Error, ICCameraFile?) -> Void,
    onDownloadSuccess: @escaping (ICCameraFile?) -> Void,
    thumbnailStateRef: AnyObject? = nil
  ) {
    self.onDeviceFound = onDeviceFound
    self.onDeviceRemoved = onDeviceRemoved
    self.onDeviceDisconnected = onDeviceDisconnected
    self.onDownloadError = onDownloadError
    self.onDownloadSuccess = onDownloadSuccess
    self.thumbnailStateRef = thumbnailStateRef
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

  // ICCameraDeviceDelegate methods for downloads
  func cameraDevice(
    _ cameraDevice: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem,
    error: Error?
  ) {
    guard let receivedThumbnail = thumbnail else { return }
    let nsImage = NSImage(cgImage: receivedThumbnail, size: NSSize(width: 200, height: 200))

    Task { [weak self] in
      guard let state = self?.thumbnailStateRef as? CameraItemState else { return }
      if let continuation = await state.takePending(for: item) {
        continuation.resume(returning: nsImage)
      }
    }
  }

  func cameraDevice(
    _ cameraDevice: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?,
    for item: ICCameraItem, error: Error?
  ) {
    // Handle metadata reception
  }

  func cameraDevice(
    _ cameraDevice: ICCameraDevice, didDownloadFile fileURL: URL?, file: ICCameraFile?,
    destination: URL?, error: Error?
  ) {
    if let error = error {
      print(
        "DEBUG: Download failed for \(file?.name ?? "unknown file"): \(error.localizedDescription)")
      // Call the error handler
      onDownloadError(error, file)
    } else if let fileURL = fileURL {
      print(
        "DEBUG: Download completed: \(file?.name ?? "unknown file") -> \(fileURL.lastPathComponent)"
      )

      // Call the success handler
      onDownloadSuccess(file)

      // File is already in the correct location due to downloadsDirectoryURL option
      // No need to move it - trigger media scan to pick up the new file
      Task {
        await MediaScanner.shared.scan(directories: DirectoryManager.shared.directories)
      }
    }
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didCompleteDeleteFilesWithError error: Error?) {
    // Handle delete completion
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didAdd items: [ICCameraItem]) {
    // Handle items being added to the camera device

  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didRemove items: [ICCameraItem]) {
    // Handle items being removed from the camera device
    print("DEBUG: Camera device removed \(items.count) items")
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
    // Handle items being renamed on the camera device
    print("DEBUG: Camera device renamed \(items.count) items")
  }

  func cameraDeviceDidChangeCapability(_ cameraDevice: ICCameraDevice) {
    // Handle capability changes

  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didReceivePTPEvent eventData: Data) {
    // Handle PTP events from the camera device
    print("DEBUG: Camera device received PTP event")
  }

  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    // Handle when device is ready with complete content catalog

  }

  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
    // Handle access restriction removal

  }

  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
    // Handle access restriction enable
    print("DEBUG: Camera device access restriction enabled")
  }
}

// MARK: - extract base name
extension String {
  // Extract base name from filename (remove extension and edit markers)
  func extractBaseName() -> String {
    var baseName = self

    // Remove edit markers first (before extensions)
    // Remove edit markers (e.g., "IMG_1234" from "IMG_1234 (Edited)")
    if let editMarkerRange = baseName.range(of: " \\(Edited\\)", options: .regularExpression) {
      baseName = String(baseName[..<editMarkerRange.lowerBound])
    }

    // Remove iOS edit markers (E in the middle)
    if let firstDigitIndex = baseName.firstIndex(where: { $0.isNumber }) {
      let beforeDigits = baseName[..<firstDigitIndex]
      if beforeDigits.hasSuffix("E") {
        // Remove the E without adding separator
        let prefix = String(beforeDigits.dropLast())
        let digits = String(baseName[firstDigitIndex...])
        baseName = prefix + digits
      }
    }

    // Then remove common extensions (remove all extensions)
    if let dotIndex = baseName.lastIndex(of: ".") {
      baseName = String(baseName[..<dotIndex])
    }

    return baseName
  }
}

extension URL {
  private static let imageExtensions: Set<String> = [
    // Standard image formats
    "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "heic", "heif", "webp", "svg", "icns", "psd",
    "ico",

    // Raw image formats from various camera manufacturers
    "cr2", "crw", "nef", "nrw", "arw", "srf", "rw2", "rwl", "raf", "orf", "ori", "pef", "dng",
    "rwl", "3fr", "fff", "iiq", "mos", "dcr", "kdc", "x3f", "erf", "mef", "dng", "mrw", "orf",
    "rw2", "srw", "dng",
  ]

  private static let videoExtensions: Set<String> = [
    // Standard video formats
    "mp4", "avi", "mov", "m4v", "mpg", "mpeg", "3gp", "3g2", "dv", "flc", "m2ts", "mts", "m4v",
    "mkv", "webm", "wmv", "asf", "rm", "divx", "xvid", "ogv", "vob",
  ]

  func isImage() -> Bool {
    return Self.imageExtensions.contains(pathExtension.lowercased())
  }

  func isVideo() -> Bool {
    return Self.videoExtensions.contains(pathExtension.lowercased())
  }

  func isMedia() -> Bool {
    return isImage() || isVideo()
  }
}

// MARK: - Camera Item Hash
extension ICCameraItem {
  public static func == (lhs: ICCameraItem, rhs: ICCameraItem) -> Bool {
    // Compare stable properties
    lhs.name == rhs.name && lhs.uti == rhs.uti && lhs.creationDate == rhs.creationDate
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(name)
    hasher.combine(uti)
    hasher.combine(creationDate)
    return hasher.finalize()
  }

}

extension ICCameraItem {
  private static let imageUTIs: Set<String> = [
    // Standard image formats
    "public.jpeg",
    "public.png",
    "public.tiff",
    "public.gif",
    "public.bmp",
    "public.heic",
    "public.heif",
    "public.webp",
    "public.svg-image",
    "com.apple.icns",
    "com.adobe.photoshop-image",
    "com.microsoft.bmp",
    "com.microsoft.ico",

    // Raw image formats from various camera manufacturers
    "com.canon.cr2",
    "com.canon.crw",
    "com.nikon.nef",
    "com.nikon.nrw",
    "com.sony.arw",
    "com.sony.srf",
    "com.panasonic.rw2",
    "com.panasonic.rwl",
    "com.fuji.raw",
    "com.fuji.raf",
    "com.olympus.orf",
    "com.olympus.ori",
    "com.pentax.raw",
    "com.pentax.pef",
    "com.leica.raw",
    "com.leica.rwl",
    "com.hasselblad.3fr",
    "com.hasselblad.fff",
    "com.phaseone.iiq",
    "com.leaf.mos",
    "com.kodak.dcr",
    "com.kodak.kdc",
    "com.sigma.raw",
    "com.sigma.x3f",
    "com.epson.raw",
    "com.epson.erf",
    "com.mamiya.raw",
    "com.mamiya.mef",
    "com.ricoh.raw",
    "com.ricoh.dng",
    "com.konica.raw",
    "com.konica.mrw",
    "com.minolta.raw",
    "com.minolta.mrw",
    "com.casiodata.raw",
    "com.agfa.raw",
    "com.samsung.raw",
    "com.samsung.srw",
    "com.nokia.raw",
    "com.nokia.nrw",
  ]

  private static let videoUTIs: Set<String> = [
    // Standard video formats
    "public.mpeg-4",
    "public.avi",
    "com.apple.quicktime-movie",
    "public.mp4",
    "public.mpeg",
    "public.3gpp",
    "public.3gpp2",
    "public.dv",
    "public.flc",
    "public.m2ts",
    "public.mts",
    "public.m4v",
    "public.mkv",
    "org.webmproject.webm",
    "public.movie",
    "com.microsoft.wmv",
    "com.microsoft.asf",
    "com.real.realmedia",
    "com.divx.divx",
    "com.xvid.xvid",
    "public.ogv",
    "public.vob",

    // Additional formats from devices
    "com.apple.itunes.m4v",
    "com.google.webm",
    "com.microsoft.mpeg",
    "com.sony.mpeg",
    "com.panasonic.mpeg",
    "com.canon.mpeg",
    "com.nikon.mpeg",
    "com.olympus.mpeg",
  ]

  func isImage() -> Bool {
    return uti.map { Self.imageUTIs.contains($0) } ?? false
  }

  func isVideo() -> Bool {
    return uti.map { Self.videoUTIs.contains($0) } ?? false
  }

  func isMedia() -> Bool {
    return isImage() || isVideo()
  }
}
