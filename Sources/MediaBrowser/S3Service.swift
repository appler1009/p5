import AWSClientRuntime
import AWSS3
import AWSSDKIdentity
import Combine
import Foundation

class S3Service: ObservableObject {
  static let shared = S3Service()

  @Published var uploadProgress: [String: Double] = [:]
  @Published var isUploading = false
  @Published var autoSyncEnabled: Bool = UserDefaults.standard.bool(forKey: "autoSyncEnabled") {
    didSet {
      UserDefaults.standard.set(autoSyncEnabled, forKey: "autoSyncEnabled")
    }
  }
  @Published var config = S3Config() {
    didSet {
      saveConfig()
      setupS3Client()
      updateAutoSync()
    }
  }

  private var s3Client: S3Client?
  private let configKey = "s3Config"
  private var pendingTasks = Set<Task<Void, Never>>()
  private let uploadQueue = DispatchQueue(label: "com.mediabrowser.s3upload")

  private let supportedImageExtensions = [
    "jpg", "jpeg", "png", "heic", "tiff", "tif", "raw", "cr2", "nef", "arw", "dng",
  ]
  private let supportedVideoExtensions = ["mov", "mp4"]

  /// Check if a file exists with case-insensitive extension matching
  private func fileExistsWithCaseInsensitiveExtension(
    baseName: String, extensions: [String], directoryURL: URL
  ) -> URL? {
    for ext in extensions {
      // Check both lowercase and uppercase versions
      for caseVariant in [ext.lowercased(), ext.uppercased()] {
        let fileURL = directoryURL.appendingPathComponent("\(baseName).\(caseVariant)")
        if FileManager.default.fileExists(atPath: fileURL.path) {
          return fileURL
        }
      }
    }
    return nil
  }

  private init() {
    loadConfig()
    setupS3Client()
  }

  private func loadConfig() {
    if let data = UserDefaults.standard.data(forKey: configKey),
      let decodedConfig = try? JSONDecoder().decode(S3Config.self, from: data)
    {
      config = decodedConfig
    }
  }

  private func saveConfig() {
    if let data = try? JSONEncoder().encode(config) {
      UserDefaults.standard.set(data, forKey: configKey)
    }
  }

  private func setupS3Client() {
    guard config.isValid else {
      s3Client = nil
      return
    }

    do {
      // Create static credentials from app settings
      let identity = AWSCredentialIdentity(
        accessKey: config.accessKeyId,
        secret: config.secretAccessKey
      )

      let resolver = StaticAWSCredentialIdentityResolver(identity)

      let configuration = try S3Client.S3ClientConfiguration(
        awsCredentialIdentityResolver: resolver,
        region: config.region
      )

      s3Client = S3Client(config: configuration)
    } catch {
      print("Failed to setup S3 client: \(error)")
      s3Client = nil
    }
  }

  func updateConfig(_ newConfig: S3Config) {
    config = newConfig
    setupS3Client()
  }

  func shouldUploadItem(_ item: MediaItem) async -> Bool {
    guard config.isValid else { return false }
    guard let s3Client = s3Client else { return false }

    let s3Key = createS3Key(for: item)

    do {
      // Check if object exists in S3
      let headInput = HeadObjectInput(bucket: config.bucketName, key: s3Key)
      let headOutput = try await s3Client.headObject(input: headInput)

      // If object exists, compare timestamps
      if let s3LastModified = headOutput.lastModified,
        let localFileDate = item.metadata?.creationDate ?? item.metadata?.exifDate
      {

        // Only upload if local file is newer than S3 object
        return localFileDate > s3LastModified
      }

      // If we can't determine timestamps, assume we should upload
      return true

    } catch {
      // Check if this is a "not found" error (object doesn't exist in S3)
      let errorString = String(describing: error)
      if errorString.contains("NotFound") || errorString.contains("NoSuchKey")
        || errorString.contains("404")
      {
        // Object doesn't exist - we should upload
        return true
      }
      // Other errors - log and assume we should upload
      print("Error checking S3 object existence for \(s3Key): \(error)")
      return true
    }
  }

  func uploadMediaItem(_ item: MediaItem) async throws {
    guard config.isValid else {
      throw S3Error.notConfigured
    }
    guard s3Client != nil else {
      throw S3Error.clientNotInitialized
    }

    let progressFileName = item.displayName ?? item.url.lastPathComponent
    await MainActor.run {
      NotificationCenter.default.post(
        name: NSNotification.Name("UploadProgressUpdated"), object: nil,
        userInfo: [
          "fileName": progressFileName
        ])
    }

    // 1) Find all related files including itself
    let allFiles = findRelatedFiles(for: item) + [item.url]
    print(
      "⏭️ [FILES] Will upload \(allFiles.count) files: \(allFiles.map { $0.lastPathComponent }.joined(separator: ", "))"
    )

    // 2) Make a list of files and loop through them
    for fileURL in allFiles {
      // Determine the media type for this file
      let mediaType: MediaType
      if fileURL == item.url {
        // This is the main item, use its existing type
        mediaType = item.type
      } else {
        // This is a related file, determine type from extension
        if supportedImageExtensions.contains(fileURL.pathExtension.lowercased()) {
          mediaType = .photo
        } else if supportedVideoExtensions.contains(fileURL.pathExtension.lowercased()) {
          mediaType = .video
        } else {
          mediaType = .photo  // fallback
        }
      }

      // Create a MediaItem for this file
      let currentItem = MediaItem(
        id: item.id,
        url: fileURL,
        type: mediaType,
        metadata: item.metadata,
        displayName: item.displayName
      )

      // 3) Check for each file if already exists in S3
      let needsUpload = await shouldUploadItem(currentItem)

      // 4) If it is, skip to next file
      if !needsUpload {
        print("⏭️ [SKIP] \(fileURL.lastPathComponent) already exists in S3")
        continue  // Skip to next file
      }

      // 5) If it does not exist in S3, upload file
      do {
        try await uploadSingleFile(fileURL, item: currentItem)
        print("✅ [SUCCESS] \(fileURL.lastPathComponent) uploaded")
      } catch {
        let filename = fileURL.lastPathComponent
        print("❌ [FAILED] \(filename) - Error: \(error.localizedDescription)")
        // Continue with next file even if one fails
        continue
      }
    }
  }

  private func uploadSingleFile(_ fileURL: URL, item: MediaItem) async throws {
    let s3Key = createS3Key(for: item)

    do {
      let fileData = try Data(contentsOf: fileURL)

      let input = PutObjectInput(
        body: .data(fileData),
        bucket: config.bucketName,
        contentType: contentType(for: fileURL),
        key: s3Key,
        storageClass: .intelligentTiering
      )

      _ = try await s3Client!.putObject(input: input)
    } catch {
      throw error
    }
  }

  private func findRelatedFiles(for item: MediaItem) -> [URL] {
    var relatedFiles: [URL] = []
    let fileName = item.url.deletingPathExtension().lastPathComponent
    let fileExtension = item.url.pathExtension
    let directoryURL = item.url.deletingLastPathComponent()

    // For live photos: find the paired video file with same base name
    if item.type == .livePhoto {
      if let videoURL = fileExistsWithCaseInsensitiveExtension(
        baseName: fileName, extensions: supportedVideoExtensions, directoryURL: directoryURL)
      {
        relatedFiles.append(videoURL)
      }
    }

    // Handle edited file relationships bidirectionally
    if let range = fileName.range(of: #"(\d+)"#, options: .regularExpression) {
      let prefix = String(fileName[..<range.lowerBound])  // e.g., "IMG" or "IMG_"
      let digits = String(fileName[range])  // e.g., "1234"

      // Check if this appears to be an edited file (has 'E' before digits in prefix)
      if prefix.hasSuffix("E") {
        // This is likely an edited file - find the original
        let originalPrefix = String(prefix.dropLast())  // Remove the 'E'
        let originalBaseName = "\(originalPrefix)\(digits)"

        // Check for original file with same extension
        if !fileExtension.isEmpty {
          if let originalURL = fileExistsWithCaseInsensitiveExtension(
            baseName: originalBaseName, extensions: [fileExtension], directoryURL: directoryURL)
          {
            relatedFiles.append(originalURL)
          }
        }

        // Check for original file with any common image extension
        let commonExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp"]
        let extensionsToCheck = commonExtensions.filter { $0 != fileExtension.lowercased() }  // Skip if same as current
        if let originalURL = fileExistsWithCaseInsensitiveExtension(
          baseName: originalBaseName, extensions: extensionsToCheck, directoryURL: directoryURL)
        {
          relatedFiles.append(originalURL)
        }
      } else {
        // This appears to be an original file - find edited versions
        let editedBaseName = "\(prefix)E\(digits)"

        // Check for edited file with same extension first
        if !fileExtension.isEmpty {
          if let editedURL = fileExistsWithCaseInsensitiveExtension(
            baseName: editedBaseName, extensions: [fileExtension], directoryURL: directoryURL)
          {
            relatedFiles.append(editedURL)
          }
        }

        // Check for edited file without extension
        let editedURLNoExt = directoryURL.appendingPathComponent(editedBaseName)
        if FileManager.default.fileExists(atPath: editedURLNoExt.path) {
          relatedFiles.append(editedURLNoExt)
        }

        // Check for edited file with any common image extension
        let commonExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp"]
        let extensionsToCheck = commonExtensions.filter { $0 != fileExtension.lowercased() }  // Skip if same as original
        if let editedURL = fileExistsWithCaseInsensitiveExtension(
          baseName: editedBaseName, extensions: extensionsToCheck, directoryURL: directoryURL)
        {
          relatedFiles.append(editedURL)
        }
      }
    }

    return relatedFiles
  }

  func createS3Key(for item: MediaItem) -> String {
    var components = [config.basePath]

    if let date = item.metadata?.creationDate ?? item.metadata?.exifDate {
      let calendar = Calendar.current
      let year = calendar.component(.year, from: date)
      let month = String(format: "%02d", calendar.component(.month, from: date))
      let day = String(format: "%02d", calendar.component(.day, from: date))

      components.append("\(year)")
      components.append(month)
      components.append(day)
    }

    components.append(item.url.lastPathComponent)

    return components.filter { !$0.isEmpty }.joined(separator: "/")
  }

  func stopAutoSync() {
    autoSyncEnabled = false
    // Cancel all pending upload tasks
    for task in pendingTasks {
      task.cancel()
    }
    pendingTasks.removeAll()
    print("Auto S3 sync stopped")
  }

  func uploadNextItem() async {
    // Simple mutex using boolean flag - check if already running
    guard !isUploading else {
      return
    }

    isUploading = true
    defer { isUploading = false }

    // Process items in a loop until none remain or auto-sync is disabled
    while autoSyncEnabled {
      // Find the first item that hasn't been synced yet
      guard
        var itemToUpload = DatabaseManager.shared.getAllItems().first(where: {
          $0.s3SyncStatus != .synced
        })
      else {
        print("💾 [PROGRESS] Update nil as progress")
        await MainActor.run {
          NotificationCenter.default.post(
            name: NSNotification.Name("UploadProgressUpdated"), object: nil,
            userInfo: [
              "fileName": NSNull()
            ])
        }

        // Schedule next run in 1 minute if auto-sync is still enabled
        if autoSyncEnabled {
          let task = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60 seconds
            if !Task.isCancelled && autoSyncEnabled {
              await self.uploadNextItem()
            }
          }
          pendingTasks.insert(task)
        }
        return
      }

      do {
        try await uploadMediaItem(itemToUpload)

        // Update the item's sync status in database
        itemToUpload.s3SyncStatus = .synced
        DatabaseManager.shared.updateS3SyncStatus(for: itemToUpload)

        // Update UI to show cloud icon immediately after successful upload
        let itemId = itemToUpload.id
        let statusRaw = itemToUpload.s3SyncStatus.rawValue
        await MainActor.run {
          NotificationCenter.default.post(
            name: NSNotification.Name("S3SyncStatusUpdated"), object: nil,
            userInfo: [
              "itemId": itemId, "status": statusRaw,
            ])
        }

        // Continue to next item in the loop (no need to schedule new task)

      } catch {
        let filename = itemToUpload.url.lastPathComponent
        print("❌ [FAILED] \(filename) - Error: \(error.localizedDescription)")

        // Update the item's sync status to failed
        itemToUpload.s3SyncStatus = .failed
        DatabaseManager.shared.updateS3SyncStatus(for: itemToUpload)

        print("💾 [STATUS] Marked \(filename) as failed - will retry later")

        // On failure, break the loop and schedule retry in 1 minute
        if autoSyncEnabled {
          let task = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60 seconds
            if !Task.isCancelled && autoSyncEnabled {
              await self.uploadNextItem()
            }
          }
          pendingTasks.insert(task)
        }
        return
      }
    }
  }

  private func updateAutoSync() {
    // Auto-stop if configuration becomes invalid
    if !config.isValid {
      if autoSyncEnabled {
        stopAutoSync()
      }
    }
    // Note: We don't auto-start here - user must explicitly enable via toggle
  }

  private func contentType(for url: URL) -> String {
    let pathExtension = url.pathExtension.lowercased()

    switch pathExtension {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "heic":
      return "image/heic"
    case "mov":
      return "video/quicktime"
    case "mp4":
      return "video/mp4"
    default:
      return "application/octet-stream"
    }
  }
  enum S3Error: Error {
    case notConfigured
    case clientNotInitialized
    case uploadFailed(String)
  }
}
