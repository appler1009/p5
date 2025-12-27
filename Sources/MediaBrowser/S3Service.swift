import AWSClientRuntime
import AWSS3
import AWSSDKIdentity
import Combine
import Foundation

class S3Service: ObservableObject {
  static let shared = S3Service()

  @Published var uploadProgress: [String: Double] = [:]
  @Published var isUploading = false
  @Published var currentUploadItem: String?
  @Published var autoSyncEnabled = false
  @Published var config = S3Config() {
    didSet {
      saveConfig()
      setupS3Client()
      updateAutoSync()
    }
  }

  private var s3Client: S3Client?
  private var autoSyncTimer: Timer?
  private let configKey = "s3Config"
  private let uploadQueue = DispatchQueue(label: "com.mediabrowser.s3upload")

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

      let resolver = try StaticAWSCredentialIdentityResolver(identity)

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

  private func shouldUploadItem(_ item: MediaItem) async -> Bool {
    guard config.enabled && config.isValid else { return false }
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
    guard config.enabled && config.isValid else {
      throw S3Error.notConfigured
    }
    guard let s3Client = s3Client else {
      throw S3Error.clientNotInitialized
    }

    let s3Key = createS3Key(for: item)
    let fileURL = item.url

    print("Upload attempt 1 for \(item.url.lastPathComponent)")
    print("S3 Operation: PutObject")
    print("Bucket: \(config.bucketName)")
    print("Key: \(s3Key)")
    print("Region: \(config.region)")
    print("Storage Class: INTELLIGENT_TIERING")
    print("Content Type: \(contentType(for: fileURL))")
    print("File Size: \((try? Data(contentsOf: fileURL).count) ?? 0) bytes")

    do {
      let fileData = try Data(contentsOf: fileURL)

      let input = PutObjectInput(
        body: .data(fileData),
        bucket: config.bucketName,
        contentType: contentType(for: fileURL),
        key: s3Key,
        storageClass: .intelligentTiering
      )

      _ = try await s3Client.putObject(input: input)

      print("Successfully uploaded \(item.url.lastPathComponent) to S3")

    } catch {
      throw error
    }
  }

  func syncAllItems(_ items: [MediaItem]) async {
    guard config.enabled && config.isValid else {
      print("S3 sync not configured or disabled")
      return
    }

    await MainActor.run {
      isUploading = true
      uploadProgress.removeAll()
    }

    let totalItems = items.count
    var completedCount = 0

    for (index, item) in items.enumerated() {
      let progressKey = item.id.uuidString
      await MainActor.run {
        currentUploadItem = item.url.lastPathComponent
        uploadProgress[progressKey] = 0.0
      }

      do {
        // Check if this item needs to be uploaded
        let needsUpload = await shouldUploadItem(item)

        if !needsUpload {
          await MainActor.run {
            uploadProgress[progressKey] = 1.0  // Mark as completed (already exists)
          }
          print("Skipped \(item.url.lastPathComponent) - already up to date in S3")
          completedCount += 1
          continue
        }

        // Update overall progress
        let overallProgress = Double(index) / Double(totalItems)
        await MainActor.run {
          uploadProgress["overall"] = overallProgress
        }

        try await uploadMediaItem(item)

        // Update database with successful sync status
        var updatedItem = item
        updatedItem.s3SyncStatus = .synced
        DatabaseManager.shared.updateS3SyncStatus(for: updatedItem)

        await MainActor.run {
          uploadProgress[progressKey] = 1.0
        }

        completedCount += 1
        print("Synced \(completedCount)/\(totalItems): \(item.url.lastPathComponent)")

      } catch {
        // Update database with failed sync status
        var updatedItem = item
        updatedItem.s3SyncStatus = .failed
        DatabaseManager.shared.updateS3SyncStatus(for: updatedItem)

        print("Failed to sync \(item.url.lastPathComponent): \(error)")
        await MainActor.run {
          uploadProgress[progressKey] = -1.0  // Indicate failure
        }
      }
    }

    await MainActor.run {
      isUploading = false
      currentUploadItem = nil
      uploadProgress["overall"] = 1.0
    }

    print("S3 sync completed: \(completedCount)/\(totalItems) items synced")
  }

  func startAutoSync() {
    stopAutoSync()  // Stop any existing timer

    autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
      Task {
        await self?.performAutoSync()
      }
    }

    autoSyncEnabled = true
    print("Auto S3 sync started - checking every 60 seconds")
  }

  func stopAutoSync() {
    autoSyncTimer?.invalidate()
    autoSyncTimer = nil
    autoSyncEnabled = false
    print("Auto S3 sync stopped")
  }

  private func updateAutoSync() {
    // Auto-stop if configuration becomes invalid
    if !config.enabled || !config.isValid {
      if autoSyncEnabled {
        stopAutoSync()
      }
    }
    // Note: We don't auto-start here - user must explicitly enable via toggle
  }

  private func performAutoSync() async {
    // Check if sync is enabled and configured
    guard config.enabled && config.isValid else {
      return  // Silently skip if not configured
    }

    // Get items that need syncing
    let itemsToSync = DatabaseManager.shared.getAllItems().filter { $0.s3SyncStatus != .synced }

    guard !itemsToSync.isEmpty else {
      return  // Nothing to sync
    }

    print("Auto-sync: Found \(itemsToSync.count) items to sync")

    // Perform the sync
    await syncAllItems(itemsToSync)
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

  func checkSyncStatus() async -> [String: S3SyncStatus] {
    // Placeholder - would check which files exist in S3
    return [:]
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
}

enum S3Error: Error {
  case notConfigured
  case clientNotInitialized
  case uploadFailed(String)
}
