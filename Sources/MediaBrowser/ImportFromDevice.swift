import ImageCaptureCore
import SwiftUI

class ImportFromDevice: ObservableObject {
  @Published var detectedDevices: [ICCameraDevice] = []
  @Published var deviceMediaItems: [ConnectedDeviceMediaItem] = []
  @Published var isLoadingDeviceContents = false
  @Published var isDownloading = false
  @Published var isScanning = false

  @Published var selectedDevice: ICCameraDevice?
  @Published var selectedDeviceMediaItems: Set<MediaItem> = []

  var deviceBrowser: ICDeviceBrowser?
  var deviceDelegate: DeviceDelegate?
  var thumbnailOperationsCancelled = false

  // Thumbnail coordination
  private let thumbnailState = CameraItemState()
  private let thumbnailLimiter = ConcurrencyLimiter(limit: 15)
  private let downloadState = CameraItemState()
  private let downloadLimiter = ConcurrencyLimiter(limit: 2)

  internal func scanForDevices() {
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
              "Selected device was removed, clearing selection and cancelling thumbnail operations"
            )
            self.selectedDevice = nil
            self.deviceMediaItems = []
            self.thumbnailOperationsCancelled = true
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
            print("Download failed: Device is busy or not ready.")
          } else {
            print("Download failed: \(error.localizedDescription)")
          }
        }
      },
      onDownloadSuccess: { file in
        DispatchQueue.main.async {
          print("Successfully imported \(file?.name ?? "file")")
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

  internal func selectDevice(_ device: ICCameraDevice) {
    selectedDevice = device
    deviceMediaItems = []
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

      // Group related camera items and create DeviceMediaItem objects
      self.deviceMediaItems = self.groupRelatedCameraItems(cameraItems)

      if self.deviceMediaItems.isEmpty {
        print("DEBUG: No media items found at root level")
      }

      DispatchQueue.main.async { [self] in
        isLoadingDeviceContents = false
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
              // if subItem.isMedia() != true { print("unknown UTI \(subItem.uti ?? "_unknown_") for \(subItem.name ?? "unnamed")") }
              return subItem.isMedia()
            }
            allCameraItems.append(contentsOf: mediaInSubfolder)
          }
        } else if item.isMedia() {
          allCameraItems.append(item)
        }
      }

      // Create DeviceMediaItem objects

      self.deviceMediaItems = self.groupRelatedCameraItems(allCameraItems)
      self.isLoadingDeviceContents = false

      await self.requestThumbnails()

      if allCameraItems.isEmpty {
        print("all camera items is empty")
      }

      await MainActor.run {
        self.isLoadingDeviceContents = false
      }
    } else {
      await MainActor.run {
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

  internal func requestDownloads() async {
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
          DispatchQueue.main.async {
            self.isDownloading = false
          }

          if let error = error {
            print(
              "DEBUG: Download request failed for \(cameraFileId): \(error.localizedDescription)")
          }

          if let fileName = cameraFile.name {
            let importDir = DirectoryManager.shared.importDirectory
            let downloadedPath = importDir.appendingPathComponent(fileName)
            do {
              let attributes = try FileManager.default.attributesOfItem(atPath: downloadedPath.path)
              if let downloadedSize = attributes[.size] as? NSNumber {
                if downloadedSize.uint64Value != cameraFile.fileSize {
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

  internal func stopScanning() {
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
      print(
        """
        No iPhones detected via USB.

        Try:
        • Unlock your iPhone
        • Tap "Trust This Computer" on iPhone
        • Use Apple USB-C cable
        • Check if iPhone appears in Image Capture app
        • Grant Full Disk Access in System Settings
        • Restart your iPhone
        """)
    }
  }

  // Group related camera items (Live Photos, edited photos, etc.)
  private func groupRelatedCameraItems(_ items: [ICCameraItem]) -> [ConnectedDeviceMediaItem] {
    let itemLookup: [String: ICCameraItem] = items.reduce(into: [String: ICCameraItem]()) {
      dict, item in
      dict[MediaSource(cameraItem: item).lookupKey()] = item  // overwrites duplicates, but there should be no duplicates with lookupKey()
    }

    let sources = items.map(MediaSource.init(cameraItem:))

    let mediaGroups = groupRelatedMedia(sources)
    return mediaGroups.compactMap { group in
      if let original = itemLookup[group.main.lookupKey()] {
        return ConnectedDeviceMediaItem(
          id: -1,  // Will be replaced with a unique sequence number
          original: original,
          edited: group.edited != nil ? itemLookup[group.edited!.lookupKey()] : nil,
          live: group.live != nil ? itemLookup[group.live!.lookupKey()] : nil
        )
      } else {
        return nil
      }
    }
  }

  struct MediaSource: Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int
    let baseName: String
    let fullName: String
    let uti: String

    init(date: Date, name: String, uti: String) {
      let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
      self.year = components.year!
      self.month = components.month!
      self.day = components.day!
      self.fullName = name
      self.baseName = name.extractBaseName()
      self.uti = uti
    }
    init(cameraItem: ICCameraItem) {
      self.init(
        date: cameraItem.creationDate!,
        name: cameraItem.name!,
        uti: cameraItem.uti!)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(year)
      hasher.combine(month)
      hasher.combine(day)
      hasher.combine(baseName)
    }

    func isImage() -> Bool {
      return fullName.isImage()
    }
    func isVideo() -> Bool {
      return fullName.isVideo()
    }
    func isMedia() -> Bool {
      return fullName.isMedia()
    }

    func lookupKey() -> String {
      return "\(year)_\(month)_\(day)_\(baseName)_\(uti)"
    }

    static func == (lhs: MediaSource, rhs: MediaSource) -> Bool {
      lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
        && lhs.baseName == rhs.baseName
    }

    static func < (lhs: MediaSource, rhs: MediaSource) -> Bool {
      // Date first
      if lhs.year != rhs.year { return lhs.year < rhs.year }
      if lhs.month != rhs.month { return lhs.month < rhs.month }
      if lhs.day != rhs.day { return lhs.day < rhs.day }

      // Basename: length first, then alphabetical
      if lhs.fullName.count != rhs.fullName.count {
        return lhs.fullName.count < rhs.fullName.count  // Longer > shorter
      }
      return lhs.fullName < rhs.fullName  // Same length, alphabetical
    }
  }
  struct MediaGroupEntry: Comparable {
    let main: MediaSource
    let edited: MediaSource?
    let live: MediaSource?

    // Custom sorting: main → edited → live priority
    static func < (lhs: MediaGroupEntry, rhs: MediaGroupEntry) -> Bool {
      // 1. Compare main (highest priority)
      if lhs.main != rhs.main {
        return lhs.main < rhs.main
      }

      // 2. Compare edited (exists > nil)
      switch (lhs.edited, rhs.edited) {
      case (nil, nil):
        break  // Both nil, continue
      case (nil, _):
        return true  // lhs nil, rhs exists → lhs smaller
      case (_, nil):
        return false  // lhs exists, rhs nil → lhs bigger
      case (let lhsEdited?, let rhsEdited?):
        if lhsEdited != rhsEdited {
          return lhsEdited < rhsEdited
        }
      }

      // 3. Compare live (exists > nil)
      switch (lhs.live, rhs.live) {
      case (nil, nil):
        return false  // Equal
      case (nil, _):
        return true  // lhs nil, rhs exists → lhs smaller
      case (_, nil):
        return false  // lhs exists, rhs nil → lhs bigger
      case (let lhsLive?, let rhsLive?):
        return lhsLive < rhsLive
      }
    }
  }

  func groupRelatedMedia(_ items: [MediaSource]) -> [MediaGroupEntry] {
    var groups: [MediaSource: MediaGroupEntry] = [:]

    // 1st pass - take list of photos while grouping edited photos
    let photoSources = items.filter { $0.isImage() }
    for photoSource in photoSources {
      if let group = groups[photoSource] {
        if group.main > photoSource {
          // longer name must be the edited name
          groups[photoSource] = .init(main: photoSource, edited: group.main, live: nil)
        } else {
          groups[photoSource] = .init(main: group.main, edited: photoSource, live: nil)
        }
      } else {
        groups[photoSource] = .init(main: photoSource, edited: nil, live: nil)
      }
    }

    // 2nd pass - find videos of live photos from 1st pass
    let videoSources = items.filter { $0.isVideo() }
    for videoSource in videoSources {
      if let group = groups[videoSource] {
        groups[videoSource] = .init(main: group.main, edited: group.edited, live: videoSource)
      }
    }

    // 3rd pass - add rest of videos as separate videos
    for videoSource in videoSources {
      if let group = groups[videoSource] {
        if group.live == videoSource {
          // it's other video's live video; skip
          continue
        }
        if group.main > videoSource {
          // longer name must be the edited version
          groups[videoSource] = .init(main: videoSource, edited: group.main, live: nil)
        } else {
          groups[videoSource] = .init(main: group.main, edited: videoSource, live: nil)
        }
      } else {
        groups[videoSource] = .init(main: videoSource, edited: nil, live: nil)
      }
    }

    // not necessarily needed to be sorted, but just making it deterministic and predictable
    return Array(groups.values).sorted { $0 < $1 }
  }

  func cancelAllThumbnails() async {
    await thumbnailState.cancelAll()
    await thumbnailLimiter.cancelAll()
  }

  func cancelAllDownloads() async {
    await downloadState.cancelAll()
    await downloadLimiter.cancelAll()
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
    print("ICDevice name changed: \(device.name!)")
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeSharingState device: ICDevice) {
    print("ICDevice sharing state changed: \(device.name!)")
  }

  // ICDeviceDelegate methods
  func deviceDidBecomeReady(_ device: ICDevice) {
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    print(
      "ICDevice session opened: \(device.name!), error: \(error?.localizedDescription ?? "none")")
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    print(
      "ICDevice session closed: \(device.name!), error: \(error?.localizedDescription ?? "none")")
  }

  func didRemove(_ device: ICDevice) {
    print("ICDevice removed: \(device.name!)")
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
      print("Download failed for \(file?.name ?? "unknown file"): \(error.localizedDescription)")
      // Call the error handler
      onDownloadError(error, file)
    } else if let fileURL = fileURL {
      print("Download completed: \(file?.name ?? "unknown file") -> \(fileURL.lastPathComponent)")

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
    print("Camera device removed \(items.count) items")
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
    // Handle items being renamed on the camera device
    print("Camera device renamed \(items.count) items")
  }

  func cameraDeviceDidChangeCapability(_ cameraDevice: ICCameraDevice) {
    // Handle capability changes
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didReceivePTPEvent eventData: Data) {
    // Handle PTP events from the camera device
    print("Camera device received PTP event")
  }

  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    // Handle when device is ready with complete content catalog
  }

  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
    // Handle access restriction removal
  }

  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
    // Handle access restriction enable
    print("Camera device access restriction enabled")
  }
}
