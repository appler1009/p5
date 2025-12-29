import CryptoKit
import ImageCaptureCore
import SwiftUI

// MARK: - Device Media Item (for grouping)

struct DevizeMediaItem: Identifiable {
  let cameraItems: [ICCameraItem]  // Can contain multiple related items (Live Photo, etc.)
  var thumbnail: Image?
  var isThumbnailLoading = false

  // Primary camera item (first one, typically the image for Live Photos)
  var cameraItem: ICCameraItem { cameraItems.first! }

  var id: String {
    // Create stable string ID from primary camera item properties for disk caching
    let components = [
      cameraItem.name ?? "",
      cameraItem.uti ?? "",
      // Include device name for uniqueness across different devices
      cameraItem.device?.name ?? "",
    ]
    return components.joined(separator: "|")
  }

  var name: String? { cameraItem.name }
  var uti: String? { cameraItem.uti }

  // Determine the media type based on the items
  var mediaType: MediaType {
    if cameraItems.count > 1
      && cameraItems.contains(where: { $0.uti == "com.apple.quicktime-movie" })
    {
      return .photo  // Live Photo (treated as photo with video component)
    } else if cameraItems.first?.uti == "com.apple.quicktime-movie"
      || cameraItems.first?.uti == "public.mpeg-4"
    {
      return .video
    } else {
      return .photo
    }
  }

  init(cameraItem: ICCameraItem) {
    self.cameraItems = [cameraItem]
  }

  init(cameraItems: [ICCameraItem]) {
    self.cameraItems = cameraItems
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
  @State private var selectedDeviceMediaItem: ConnectedDeviceMediaItem?
  @State private var deviceMediaItems: [ConnectedDeviceMediaItem] = []
  @State private var isLoadingDeviceContents = false
  @State private var deviceConnectionError: String?
  @State private var thumbnailOperationsCancelled = false

  @Environment(\.dismiss) private var dismiss

  // Thumbnail coordination
  private let thumbnailState = ThumbnailState()
  private let limiter = ConcurrencyLimiter(limit: 20)

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
          if let selectedItem = selectedDeviceMediaItem {
            importSelectedItem(selectedItem)
          }
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
          VStack(spacing: 4) {
            SectionGridView(
              items: deviceMediaItems,
              selectedItem: $selectedDeviceMediaItem,
              minCellWidth: 80
            ) { item in
              // Constrain MediaItemView to prevent overflow in grid cells
              ZStack {
                MediaItemView(
                  item: item,
                  onTap: {},
                  isSelected: selectedDeviceMediaItem?.id == item.id,
                )
              }
              .frame(width: 80, height: 80)  // Strict size constraint
              .clipped()  // Prevent any overflow
              .help(item.displayName)
            }
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
        await self.limiter.cancelAll()
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
          id: -1,
          type: .livePhoto,
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

  private func groupRelatedMedia(_ items: [String]) -> [MediaEntry] {
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
      let baseName = extractBaseName(from: photoName)
      if let group = groups[baseName] {
        if group.main.count > photoName.count {
          // longer name must be the edited name
          groups[photoName] = .init(main: photoName, edited: group.main, live: nil)
        } else {
          groups[group.main] = .init(main: group.main, edited: photoName, live: nil)
        }
      } else {
        groups[photoName] = .init(main: photoName, edited: nil, live: nil)
      }
    }

    // 2nd pass - find videos of live photos from 1st pass
    let videoNames = items.filter { name in
      let ext = (name as NSString).pathExtension
      return videoExtensions.contains { $0.caseInsensitiveCompare(ext) == .orderedSame }
    }
    for videoName in videoNames {
      let baseName = extractBaseName(from: videoName)
      if let group = groups[baseName] {
        groups[baseName] = .init(main: group.main, edited: group.edited, live: videoName)
      }
      if let group = groups[videoName] {
        groups[videoName] = .init(main: group.main, edited: group.edited, live: videoName)
      }
    }

    // 3rd pass - add rest of videos as separate videos
    for videoName in videoNames {
      let baseName = extractBaseName(from: videoName)
      if groups[baseName] == nil && groups[videoName] == nil {
        groups[videoName] = .init(main: videoName, edited: nil, live: nil)
      }
    }

    return Array(groups.values)
  }

  // Extract base name from filename (remove extension and edit markers)
  private func extractBaseName(from filename: String) -> String {
    var baseName = filename

    // Remove common extensions
    let extensions = [".jpg", ".jpeg", ".png", ".heic", ".heif", ".mov", ".mp4", ".m4v"]
    for ext in extensions {
      if baseName.lowercased().hasSuffix(ext) {
        baseName = String(baseName.dropLast(ext.count))
        break
      }
    }

    // Remove edit markers (e.g., "IMG_1234" from "IMG_1234 (Edited)")
    if let editMarkerRange = baseName.range(of: " \\(Edited\\)", options: .regularExpression) {
      baseName = String(baseName[..<editMarkerRange.lowerBound])
    }

    // Remove iOS edit markers (E suffix) - similar to MediaScanner.isEdited()
    if isEditedIOS(base: baseName) {
      baseName = removeEditSuffix(from: baseName)
    }

    return baseName
  }

  // Check if filename has iOS edit marker (similar to MediaScanner.isEdited)
  private func isEditedIOS(base: String) -> Bool {
    // Check for separators first
    let separators = ["_", "-"]
    for sep in separators {
      if let range = base.range(of: sep, options: .backwards) {
        let after = base[range.upperBound...]
        if after.hasPrefix("E") {
          return true
        }
      }
    }
    // Check for E before digits without separator
    if let firstDigitIndex = base.firstIndex(where: { $0.isNumber }) {
      let beforeDigits = base[..<firstDigitIndex]
      if beforeDigits.hasSuffix("E") {
        return true
      }
    }
    return false
  }

  // Remove edit suffix to get base name (similar to MediaScanner logic)
  private func removeEditSuffix(from base: String) -> String {
    // Check for separators first
    let separators = ["_", "-"]
    for sep in separators {
      if let range = base.range(of: sep, options: .backwards) {
        let after = base[range.upperBound...]
        if after.hasPrefix("E") {
          return String(base[..<range.lowerBound])
        }
      }
    }
    // Check for E before digits without separator (iOS style: IMG_E1234 -> IMG_1234)
    if let firstDigitIndex = base.firstIndex(where: { $0.isNumber }) {
      let beforeDigits = base[..<firstDigitIndex]
      if beforeDigits.hasSuffix("E") {
        // Remove the E and add separator before digits
        let prefix = String(beforeDigits.dropLast())
        let digits = String(base[firstDigitIndex...])
        return prefix + "_" + digits
      }
    }
    return base
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
              await self.limiter.cancelAll()
            }
          }
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

        print("DEBUG: Session opened successfully, accessing contents...")

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
        await self.checkDCIMContents(dcimFolder)
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

      self.isLoadingDeviceContents = false
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
      self.deviceMediaItems = allCameraItems.map { ConnectedDeviceMediaItem($0) }
      print("DEBUG: Total media items found: \(allCameraItems.count)")

      await self.requestThumbnails()

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

  private func requestThumbnails() async {
    await withTaskGroup(of: Void.self) { group in
      for mediaItem in deviceMediaItems {
        let id = String(describing: mediaItem.id)
        let requested = await thumbnailState.markRequestedIfNeeded(id: id)
        guard requested else { continue }

        group.addTask { [thumbnailState, limiter] in
          await limiter.acquire()
          let task = Task { [thumbnailState] in
            defer { Task { await limiter.release() } }
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
        await MainActor.run { storeThumbnail(mediaItem: mediaItem, thumbnail: thumbnail) }
      }
    } catch {
      print("requestThumbnail failed: \(error)")
    }
  }

  private func storeThumbnail(mediaItem: ConnectedDeviceMediaItem, thumbnail: NSImage) {
    ThumbnailCache.shared.storePreGeneratedThumbnail(thumbnail, mediaItem: mediaItem)
    print("DEBUG: Loaded thumbnail for \(mediaItem.displayName)")
  }

  private func importSelectedItem(_ item: ConnectedDeviceMediaItem) {
    print(
      "DEBUG: Importing selected item: \(item.displayName)"
    )

    // Import all camera items in this media item
    importCameraItem(item.originalItem)
    if let editedItem = item.editedItem {
      importCameraItem(editedItem)
    }
    if let liveItem = item.liveItem {
      importCameraItem(liveItem)
    }

    DispatchQueue.main.async {
      // Clear selection after import
      self.selectedDeviceMediaItem = nil
    }
  }

  private func importCameraItem(_ cameraItem: ICCameraItem) {
    print("DEBUG: Starting download for: \(cameraItem.name ?? "unnamed")")

    // ICCameraFile is the subclass that supports downloading
    if let cameraFile = cameraItem as? ICCameraFile {
      // Request download of the camera file with completion handler
      cameraFile.requestDownload(options: nil) { downloadID, error in
        if let error = error {
          print(
            "DEBUG: Download request failed for \(cameraItem.name ?? "unnamed"): \(error.localizedDescription)"
          )
        } else {
          print(
            "DEBUG: Download request successful for \(cameraItem.name ?? "unnamed"), ID: \(downloadID ?? "none")"
          )
        }
      }
    } else {
      print("DEBUG: Cannot download \(cameraItem.name ?? "unnamed") - not a file")
    }

    // The actual download completion will be handled by the device delegate
    // cameraDevice(_:didDownloadFile:file:destination:error:)
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

        let mediaItem = LocalFileSystemMediaItem(
          id: Int.random(in: 1...Int.max),
          type: mediaType,
          original: destinationUrl,
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

// MARK: - Thumbnail Coordination Actors
actor ThumbnailState {
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
class DeviceDelegate: NSObject, ICDeviceBrowserDelegate, ICDeviceDelegate {
  weak var thumbnailStateRef: AnyObject?

  let onDeviceFound: (ICDevice) -> Void
  let onDeviceRemoved: (ICDevice) -> Void
  let onDeviceDisconnected: (ICDevice) -> Void

  init(
    onDeviceFound: @escaping (ICDevice) -> Void,
    onDeviceRemoved: @escaping (ICDevice) -> Void,
    onDeviceDisconnected: @escaping (ICDevice) -> Void,
    thumbnailStateRef: AnyObject? = nil
  ) {
    self.onDeviceFound = onDeviceFound
    self.onDeviceRemoved = onDeviceRemoved
    self.onDeviceDisconnected = onDeviceDisconnected
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

  // ICCameraDeviceDelegate methods for downloads
  func cameraDevice(
    _ cameraDevice: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem,
    error: Error?
  ) {
    guard let receivedThumbnail = thumbnail else { return }
    let nsImage = NSImage(cgImage: receivedThumbnail, size: NSSize(width: 200, height: 200))

    Task { [weak self] in
      guard let state = self?.thumbnailStateRef as? ThumbnailState else { return }
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
    } else if fileURL != nil, let destination = destination {
      print(
        "DEBUG: Download completed: \(file?.name ?? "unknown file") -> \(destination.lastPathComponent)"
      )

      // Move the downloaded file to the final destination
      // The file is already downloaded to a temporary location by ImageCapture
      // We may want to move it to our media directory or process it further

      // Trigger media scan to pick up the new file
      Task {
        await MediaScanner.shared.scan(directories: DirectoryManager.shared.directories)
      }
    }
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didCompleteDeleteFilesWithError error: Error?) {
    // Handle delete completion
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
    self.hash(into: &hasher)
    return hasher.finalize()
  }
}
