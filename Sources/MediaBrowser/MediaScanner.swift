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
  var displayName: String?  // for edited versions, show original name
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
  @Published var isScanning = false
  @Published var scanProgress: (current: Int, total: Int)? = nil

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
    await MainActor.run {
      isScanning = true
    }
    items.removeAll()
    DatabaseManager.shared.clearAll()

    // First pass: calculate total items
    var total = 0
    for directory in directories {
      total += await countItems(in: directory)
    }
    let finalTotal = total
    await MainActor.run {
      scanProgress = (0, finalTotal)
    }

    // Second pass: scan
    for directory in directories {
      await scanDirectory(directory)
    }

    // Save to DB
    for item in items {
      DatabaseManager.shared.insertItem(item)
    }
    // Cleanup dangling thumbnails
    let deleted = ThumbnailCache.shared.cleanupDanglingThumbnails()
    print("Cleaned up \(deleted) dangling thumbnails")

    await MainActor.run {
      isScanning = false
      scanProgress = nil
    }
  }

  private func countItems(in directory: URL) async -> Int {
    let fileManager = FileManager.default
    guard
      let enumerator = fileManager.enumerator(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
      )
    else { return 0 }

    var baseToURLs = [String: [URL]]()
    while let fileURL = enumerator.nextObject() as? URL {
      if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
        let base = fileURL.deletingPathExtension().lastPathComponent
        baseToURLs[base, default: []].append(fileURL)
      }
    }

    var count = 0
    for (base, urls) in baseToURLs {
      let imageURL = urls.first { supportedImageExtensions.contains($0.pathExtension.lowercased()) }
      let preferredURL = imageURL ?? urls.first
      if preferredURL != nil,
        isEdited(base: base) || getEditedBase(base: base).flatMap({ baseToURLs[$0] }) == nil
      {
        count += 1
      }
    }
    return count
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
          var item = MediaItem(url: url, type: type, displayName: nil)
          if isEdited(base: base) {
            item.displayName = getOriginalBase(base: base) + "." + url.pathExtension.uppercased()
          }
          await extractMetadata(for: &item)
          // Generate thumbnail
          let _ = await ThumbnailCache.shared.thumbnail(
            for: url, size: CGSize(width: 100, height: 100))
          items.append(item)
          if let progress = scanProgress, progress.current + 1 <= progress.total {
            await MainActor.run {
              scanProgress = (progress.current + 1, progress.total)
            }
          }
        }
      }
    }
  }

  private func isEdited(base: String) -> Bool {
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

  private func getEditedBase(base: String) -> String? {
    // Check for separators first
    let separators = ["_", "-"]
    for sep in separators {
      if let range = base.range(of: sep, options: .backwards) {
        let prefix = base[..<range.lowerBound]
        let number = base[range.upperBound...]
        return "\(prefix)\(sep)E\(number)"
      }
    }
    // Insert E before digits
    if let firstDigitIndex = base.firstIndex(where: { $0.isNumber }) {
      let letters = base[..<firstDigitIndex]
      let digits = base[firstDigitIndex...]
      return "\(letters)E\(digits)"
    }
    return nil
  }

  private func getOriginalBase(base: String) -> String {
    // Check for separators first
    let separators = ["_", "-"]
    for sep in separators {
      if let range = base.range(of: sep, options: .backwards) {
        let after = base[range.upperBound...]
        if after.hasPrefix("E") {
          let number = after.dropFirst()
          let prefix = base[..<range.lowerBound]
          return "\(prefix)\(sep)\(number)"
        }
      }
    }
    // Remove E before digits
    if let firstDigitIndex = base.firstIndex(where: { $0.isNumber }) {
      let beforeDigits = base[..<firstDigitIndex]
      if beforeDigits.hasSuffix("E") {
        let letters = beforeDigits.dropLast()
        let digits = base[firstDigitIndex...]
        return "\(letters)\(digits)"
      }
    }
    return base
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
