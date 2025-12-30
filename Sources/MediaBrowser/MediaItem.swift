import ImageCaptureCore
import SwiftUI

class MediaItem: Identifiable, Equatable, Hashable, ObservableObject {
  let id: Int
  var metadata: MediaMetadata?  // to be filled later
  @Published var s3SyncStatus: S3SyncStatus = .notSynced  // Track S3 upload status
  var displayName: String {
    fatalError("Subclasses must override displayName")
  }
  var displayURL: URL? {
    fatalError("Subclasses must override displayURL")
  }
  var thumbnailDate: Date {
    fatalError("Subclasses must override thumbnailDate")
  }
  var type: MediaType {
    fatalError("Subclasses must override type")
  }

  // private to prevent instantiation, always use subclass
  fileprivate init(id: Int) {
    self.id = id
  }

  static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
    return lhs.id == rhs.id
  }

  // Stable hash based on id + type
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(type)
  }
}

class LocalFileSystemMediaItem: MediaItem {
  private static var nextId = 1

  let originalUrl: URL
  let editedUrl: URL?
  let liveUrl: URL?

  override var displayName: String {
    return originalUrl.lastPathComponent
  }
  override var displayURL: URL {
    if let editedUrl = editedUrl {
      return editedUrl
    }
    return originalUrl
  }
  override var thumbnailDate: Date {
    if let metadata = self.metadata {
      if let creationDate = metadata.creationDate {
        return creationDate
      }
      if let exifDate = metadata.exifDate {
        return exifDate
      }
    }
    return Date()  // FIXME fallback to file's creation date
  }
  override var type: MediaType {
    if originalUrl.isVideo() {
      return .video
    } else if liveUrl != nil {
      return .livePhoto
    }
    return .photo
  }

  init(id: Int, original: URL, edited: URL? = nil, live: URL? = nil) {
    originalUrl = original
    editedUrl = edited
    liveUrl = live
    let actualId = id == -1 ? LocalFileSystemMediaItem.nextId : id
    if id == -1 {
      LocalFileSystemMediaItem.nextId += 1
    }
    super.init(id: actualId)
  }

  // ✅ Stable hash: URL path + type
  override func hash(into hasher: inout Hasher) {
    super.hash(into: &hasher)
    hasher.combine(originalUrl.path)
    hasher.combine(editedUrl?.path)
    hasher.combine(liveUrl?.path)
  }
}

class ConnectedDeviceMediaItem: MediaItem {
  let originalItem: ICCameraItem
  let editedItem: ICCameraItem?
  let liveItem: ICCameraItem?

  override var displayName: String {
    if let name = originalItem.name {
      return name
    }
    return "unknown"  // FIXME
  }
  override var displayURL: URL? {
    return nil
  }
  var displayItem: ICCameraItem {
    if let edited = editedItem {
      return edited
    }
    return originalItem
  }

  override var thumbnailDate: Date {
    if let creationDate = originalItem.creationDate {
      return creationDate
    }
    return Date()  // FIXME
  }
  override var type: MediaType {
    if originalItem.isVideo() {
      return .video
    } else if liveItem != nil {
      return .livePhoto
    }
    return .photo
  }

  private static var nextId = 1

  init(
    id: Int, original: ICCameraItem, edited: ICCameraItem? = nil,
    live: ICCameraItem? = nil
  ) {
    originalItem = original
    editedItem = edited
    liveItem = live
    let actualId = id == -1 ? ConnectedDeviceMediaItem.nextId : id
    if id == -1 {
      ConnectedDeviceMediaItem.nextId += 1
    }
    super.init(id: actualId)
    self.s3SyncStatus = .notApplicable  // Connected device items are not synced to S3
  }

  init(_ original: ICCameraItem, edited: ICCameraItem? = nil, live: ICCameraItem? = nil) {
    originalItem = original
    editedItem = edited
    liveItem = live

    super.init(id: ConnectedDeviceMediaItem.nextId)
    ConnectedDeviceMediaItem.nextId += 1
    self.s3SyncStatus = .notApplicable  // Connected device items are not synced to S3
  }

  // ✅ Stable hash: item.name + UTI + creationDate
  override func hash(into hasher: inout Hasher) {
    super.hash(into: &hasher)
    hasher.combine(originalItem.name)
    hasher.combine(originalItem.uti)
    hasher.combine(originalItem.creationDate)
    hasher.combine(editedItem?.name)
    hasher.combine(liveItem?.name)
  }
}

enum S3SyncStatus: String, Codable {
  case notSynced = "not_synced"
  case synced = "synced"
  case failed = "failed"
  case notApplicable = "not_applicable"
}

enum MediaType {
  case photo
  case livePhoto
  case video
}

struct MediaMetadata {
  var creationDate: Date?
  var modificationDate: Date?
  var dimensions: CGSize?
  var exifDate: Date?
  var gps: GPSLocation?
  var duration: TimeInterval?  // for videos
  var make: String?
  var model: String?
  var lens: String?
  var iso: Int?
  var aperture: Double?
  var shutterSpeed: String?
}

struct GPSLocation {
  let latitude: Double
  let longitude: Double
  var altitude: Double?
}
