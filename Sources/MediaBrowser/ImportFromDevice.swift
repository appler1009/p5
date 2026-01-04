@preconcurrency import ImageCaptureCore
import SwiftUI

class ImportFromDevice: ObservableObject {
  @Published var detectedDevices: [ICCameraDevice] = []
  @Published var mediaItems: [ConnectedDeviceMediaItem] = []
  @Published var isLoadingDeviceContents = false
  @Published var isDownloading = false
  @Published var isScanning = false

  @Published var selectedDevice: ICDevice?
  @Published var selectedMediaItems: Set<MediaItem> = []

  var deviceBrowser: ICDeviceBrowser?
  var deviceDelegate: DeviceDelegate?
  var thumbnailOperationsCancelled = false

  // Thumbnail coordination
  private let thumbnailState = CameraItemState()
  private let thumbnailLimiter = ConcurrencyLimiter(limit: 15)
  private let downloadState = CameraItemState()
  private let downloadLimiter = ConcurrencyLimiter(limit: 2)

  // callbacks
  private var importCallbacks: ImportCallbacks?

  internal func scanForDevices(with importCallbacks: ImportCallbacks) {
    // update callbacks
    self.importCallbacks = importCallbacks

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
            self.mediaItems = []
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
            self.mediaItems = []
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
      onDeviceUnlocked: { device in
        //        self.selectDevice(device)
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
      onCameraItemsAvailable: { items in
        Task {
          await self.processItems(items)
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
    isLoadingDeviceContents = true
    thumbnailOperationsCancelled = false

    // Set the device delegate
    device.delegate = deviceDelegate

    // Request to open session with the device
    device.requestOpenSession { error in
      if let error = error {
        Task {
          self.isLoadingDeviceContents = false
          if let onError = self.importCallbacks?.onError {
            onError(error)
          }
        }
        print("Failed to open session with device: \(error)")
        return
      }

      Task {
        print("checking device contents")
        await self.checkDeviceContents(device)
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
        print("checking DCIM contents")
        await self.checkDCIMContents(dcimFolder)
        return
      }

      // Fallback: filter for any media items at root level
      let cameraItems = contents.filter { item in
        return item.isMedia()
      }

      // Group related camera items and create DeviceMediaItem objects
      let items = groupRelatedCameraItems(cameraItems)
      await self.processItems(items)

    } else {
      print("DEBUG: device.contents is nil, retrying...")
      // Retry after a short delay in case contents aren't ready yet
      Task {
        if isLoadingDeviceContents {
          await checkDeviceContents(device)
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
        }
      }

      let items = groupRelatedCameraItems(allCameraItems)
      await self.processItems(items)

    } else {
      await MainActor.run { [weak self] in
        self?.isLoadingDeviceContents = false
      }
    }
  }

  private func processItems(_ allItems: [ConnectedDeviceMediaItem]) async {
    print("processItems \(allItems.count)")
    Task {
      self.isLoadingDeviceContents = false
    }

    await self.requestThumbnails(for: allItems)

    if allItems.isEmpty {
      print("all camera items is empty")
    }

    await MainActor.run { [weak self] in
      self?.isLoadingDeviceContents = false
    }
  }

  private func requestThumbnails(for mediaItems: [ConnectedDeviceMediaItem]) async {
    await withTaskGroup(of: Void.self) { group in
      for mediaItem in mediaItems {
        // Check if thumbnail already exists in local cache
        if ThumbnailCache.shared.thumbnailExists(mediaItem: mediaItem) {
          if let onMediaFound = self.importCallbacks?.onMediaFound {
            onMediaFound(mediaItem)
          }
          continue
        }

        let id = String(describing: mediaItem.id)
        let requested = await thumbnailState.markRequestedIfNeeded(id: id)
        guard requested else { continue }

        group.addTask { [thumbnailState, thumbnailLimiter] in
          await thumbnailLimiter.acquire()
          let task = Task { [thumbnailState, weak self] in
            defer { Task { await thumbnailLimiter.release() } }
            if Task.isCancelled { return }
            guard let self = self else { return }
            await self.checkForThumbnail(for: mediaItem)
            await thumbnailState.clearRunningTask(for: id)
          }
          await thumbnailState.setRunningTask(task, for: id)
          await task.value
        }
      }

      if let onComplete = self.importCallbacks?.onComplete {
        onComplete()
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
          if let onMediaFound = self.importCallbacks?.onMediaFound {
            onMediaFound(mediaItem)
          }
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
    selectedMediaItems.forEach { mediaItem in
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
          let task = Task { [downloadState, weak self] in
            if Task.isCancelled { return }
            guard let self = self else { return }
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
        cameraFile.requestDownload(options: options) { [weak self] downloadID, error in
          DispatchQueue.main.async { [weak self] in
            self?.isDownloading = false
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
  let onDeviceUnlocked: (ICDevice) -> Void
  let onDownloadError: (Error, ICCameraFile?) -> Void
  let onDownloadSuccess: (ICCameraFile?) -> Void
  let onCameraItemsAvailable: ([ConnectedDeviceMediaItem]) -> Void

  var cameraItems: [ICCameraItem] = []

  init(
    onDeviceFound: @escaping (ICDevice) -> Void,
    onDeviceRemoved: @escaping (ICDevice) -> Void,
    onDeviceDisconnected: @escaping (ICDevice) -> Void,
    onDeviceUnlocked: @escaping (ICDevice) -> Void,
    onDownloadError: @escaping (Error, ICCameraFile?) -> Void,
    onDownloadSuccess: @escaping (ICCameraFile?) -> Void,
    onCameraItemsAvailable: @escaping ([ConnectedDeviceMediaItem]) -> Void,
    thumbnailStateRef: AnyObject? = nil
  ) {
    self.onDeviceFound = onDeviceFound
    self.onDeviceRemoved = onDeviceRemoved
    self.onDeviceDisconnected = onDeviceDisconnected
    self.onDeviceUnlocked = onDeviceUnlocked
    self.onDownloadError = onDownloadError
    self.onDownloadSuccess = onDownloadSuccess
    self.onCameraItemsAvailable = onCameraItemsAvailable
    self.thumbnailStateRef = thumbnailStateRef
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    print("DeviceBrowser: ICDevice became ready: \(device.name!)")
    onDeviceFound(device)
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    print("DeviceBrowser: ICDevice became ready: \(device.name!)")
    onDeviceRemoved(device)
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
    print("DeviceBrowser: ICDevice name changed: \(device.name!)")
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeSharingState device: ICDevice) {
    print("DeviceBrowser: ICDevice sharing state changed: \(device.name!)")
  }

  // ICDeviceDelegate methods
  func deviceDidBecomeReady(_ device: ICDevice) {
    print("DeviceBrowser: ICDevice became ready: \(device.name!)")
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    print(
      "DeviceBrowser: ICDevice session opened: \(device.name!), error: \(error?.localizedDescription ?? "none")"
    )
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    print(
      "DeviceBrowser: ICDevice session closed: \(device.name!), error: \(error?.localizedDescription ?? "none")"
    )
  }

  func didRemove(_ device: ICDevice) {
    print("DeviceBrowser: ICDevice removed: \(device.name!)")
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
    print(
      "CameraDevice: Camera device received metadata for item \(item.name ?? "unknown") with error \(error?.localizedDescription ?? "none")"
    )
  }

  func cameraDevice(
    _ cameraDevice: ICCameraDevice, didDownloadFile fileURL: URL?, file: ICCameraFile?,
    destination: URL?, error: Error?
  ) {
    if let error = error {
      print(
        "CameraDevice: Download failed for \(file?.name ?? "unknown file"): \(error.localizedDescription)"
      )
      // Call the error handler
      onDownloadError(error, file)
    } else if let fileURL = fileURL {
      print(
        "CameraDevice: Download completed: \(file?.name ?? "unknown file") -> \(fileURL.lastPathComponent)"
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
    print(
      "CameraDevice: Camera device deleted files with error \(error?.localizedDescription ?? "unknown error")"
    )
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didAdd items: [ICCameraItem]) {
    // Handle items being added to the camera device
    print("CameraDevice: Camera device added \(items.count) items")
    self.cameraItems = items
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didRemove items: [ICCameraItem]) {
    // Handle items being removed from the camera device
    print("CameraDevice: Camera device removed \(items.count) items")
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
    // Handle items being renamed on the camera device
    print("CameraDevice: Camera device renamed \(items.count) items")
  }

  func cameraDeviceDidChangeCapability(_ cameraDevice: ICCameraDevice) {
    // Handle capability changes
    print("CameraDevice: Camera device changed capability")
  }

  func cameraDevice(_ cameraDevice: ICCameraDevice, didReceivePTPEvent eventData: Data) {
    // Handle PTP events from the camera device
    print("CameraDevice: Camera device received PTP event")
  }

  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    // Handle when device is ready with complete content catalog
    print("CameraDevice: Camera device became ready")
    print("found \(self.cameraItems.count) camera items")
    let deviceMediaItems = groupRelatedCameraItems(self.cameraItems)
    print("found \(deviceMediaItems.count) media items")
    self.onCameraItemsAvailable(deviceMediaItems)
  }

  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
    // Handle access restriction removal
    print("CameraDevice: Camera device access restriction removed")
    self.onDeviceUnlocked(device)
  }

  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
    // Handle access restriction enable
    print("CameraDevice: Camera device access restriction enabled")
  }
}
