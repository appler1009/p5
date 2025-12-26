import Foundation

enum MediaType {
  case photo
  case livePhoto
  case video
}

struct MediaItem: Identifiable {
  let id = UUID()
  let url: URL
  let type: MediaType
  var metadata: MediaMetadata?  // to be filled later
}

struct MediaMetadata {
  var filePath: String
  var filename: String
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

class MediaScanner: ObservableObject {
  static let shared = MediaScanner()

  @Published var items: [MediaItem] = []

  private let supportedImageExtensions = [
    "jpg", "jpeg", "png", "heic", "tiff", "tif", "raw", "cr2", "nef", "arw", "dng",
  ]
  private let supportedVideoExtensions = ["mov", "mp4"]

  private init() {
    loadFromDB()
  }

  func loadFromDB() {
    items = DatabaseManager.shared.getAllItems()
  }

  func reset() {
    items.removeAll()
    DatabaseManager.shared.clearAll()
  }

  func scan(directories: [URL]) async {
    items.removeAll()
    DatabaseManager.shared.clearAll()
    for directory in directories {
      await scanDirectory(directory)
    }
    // Save to DB
    for item in items {
      DatabaseManager.shared.insertItem(item)
    }
  }

  private func scanDirectory(_ directory: URL) async {
    let fileManager = FileManager.default
    guard
      let enumerator = fileManager.enumerator(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
      )
    else { return }

    var allURLs: [URL] = []
    while let fileURL = enumerator.nextObject() as? URL {
      if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
        allURLs.append(fileURL)
      }
    }

    var baseToURLs = [String: [URL]]()
    for url in allURLs {
      let base = url.deletingPathExtension().lastPathComponent
      baseToURLs[base, default: []].append(url)
    }

    for (base, urls) in baseToURLs {
      // Prefer image over video for the same base
      let imageURL = urls.first { supportedImageExtensions.contains($0.pathExtension.lowercased()) }
      let preferredURL = imageURL ?? urls.first
      if let url = preferredURL,
        isEdited(base: base) || getEditedBase(base: base).flatMap({ baseToURLs[$0] }) == nil
      {
        if let type = mediaType(for: url) {
          var item = MediaItem(url: url, type: type)
          await extractMetadata(for: &item)
          items.append(item)
        }
      }
    }
  }

  private func isEdited(base: String) -> Bool {
    let separators = ["_", "-"]
    for sep in separators {
      if let range = base.range(of: sep, options: .backwards) {
        let after = base[range.upperBound...]
        return after.hasPrefix("E")
      }
    }
    return false
  }

  private func getEditedBase(base: String) -> String? {
    let separators = ["_", "-"]
    for sep in separators {
      if let range = base.range(of: sep, options: .backwards) {
        let prefix = base[..<range.lowerBound]
        let number = base[range.upperBound...]
        return "\(prefix)\(sep)E\(number)"
      }
    }
    return nil
  }

  private var supportedExtensions: [String] {
    supportedImageExtensions + supportedVideoExtensions
  }

  private func mediaType(for url: URL) -> MediaType? {
    let pathExtension = url.pathExtension.lowercased()
    if supportedImageExtensions.contains(pathExtension) {
      // Check if it's a Live Photo: look for paired .mov
      let movURL = url.deletingPathExtension().appendingPathExtension("mov")
      if supportedVideoExtensions.contains(movURL.pathExtension.lowercased())
        && FileManager.default.fileExists(atPath: movURL.path)
      {
        return .livePhoto
      } else {
        return .photo
      }
    } else if supportedVideoExtensions.contains(pathExtension) {
      return .video
    }
    return nil
  }
}
