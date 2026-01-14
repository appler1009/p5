import Foundation
import SwiftUI

extension Notification.Name {
  static let newMediaItemImported = Notification.Name("newMediaItemImported")
}

@MainActor
class MediaScanner: ObservableObject {
  @MainActor static let shared = MediaScanner()

  @Published var items: [LocalFileSystemMediaItem] = []
  @Published var isScanning = false
  @Published var scanProgress: (current: Int, total: Int)? = nil

  private init() {
    Task { await loadFromDB() }
  }

  func loadFromDB() async {
    items = DatabaseManager.shared.getAllItems()
  }

  func reset() async {
    items.removeAll()
    DatabaseManager.shared.clearAll()
  }

  func scan(directories: [URL]) async {
    var dirs = directories
    dirs.append(DirectoryManager.shared.importDirectory)

    await MainActor.run {
      isScanning = true
    }
    items.removeAll()
    DatabaseManager.shared.clearAll()

    // First pass: calculate total items
    var total = 0
    for directory in dirs {
      total += await countItems(in: directory)
    }
    let finalTotal = total
    await MainActor.run {
      scanProgress = (0, finalTotal)
    }

    // Second pass: scan
    for directory in dirs {
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

  func countItems(in directory: URL) async -> Int {
    let fileManager = FileManager.default
    guard
      let enumerator = fileManager.enumerator(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
      )
    else { return 0 }

    var baseToURLs = [String: [URL]]()
    while let fileURL = enumerator.nextObject() as? URL {
      if fileURL.isMedia() {
        let base = fileURL.deletingPathExtension().lastPathComponent
        baseToURLs[base, default: []].append(fileURL)
      }
    }

    var count = 0
    for (base, urls) in baseToURLs {
      let imageURL = urls.first { $0.isImage() }
      let preferredURL = imageURL ?? urls.first
      if preferredURL != nil,
        isEdited(base: base) || getEditedBase(base: base).flatMap({ baseToURLs[$0] }) == nil
      {
        count += 1
      }
    }
    return count
  }

  func scanDirectory(_ directory: URL) async {
    let fileManager = FileManager.default
    guard
      let enumerator = fileManager.enumerator(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
      )
    else { return }

    var allFileURLs: [URL] = []
    while let fileURL = enumerator.nextObject() as? URL {
      if fileURL.isMedia() {
        allFileURLs.append(fileURL)
      }
    }

    let mediaItems = await groupRelatedURLs(allFileURLs)
    for mediaItem in mediaItems {
      // extract metadata
      let metadata = await MetadataExtractor.extractMetadata(for: mediaItem.originalUrl)
      mediaItem.metadata = metadata

      // Pre-generate and cache thumbnail
      let _ = await ThumbnailCache.shared.generateAndCacheThumbnail(
        for: mediaItem.displayURL, mediaItem: mediaItem)
      await MainActor.run { [mediaItem] in
        items.append(mediaItem)  // run in main thread to update the UI in real time
      }
      if let progress = scanProgress, progress.current + 1 <= progress.total {
        await MainActor.run {
          scanProgress = (progress.current + 1, progress.total)
        }
      }
    }
  }

  func isEdited(base: String) -> Bool {
    // Check for "_Edited" suffix (new rotation naming)
    if base.hasSuffix("_Edited") {
      let prefix = base.dropLast(7)  // remove "_Edited"
      if prefix.last?.isNumber == true {
        return true
      }
    }

    // Check for separators with E first (original naming)
    let separators = ["_", "-"]
    for sep in separators {
      if let range = base.range(of: sep, options: .backwards) {
        let after = base[range.upperBound...]
        if after.hasPrefix("E") && after.count > 1
          && after[after.index(after.startIndex, offsetBy: 1)].isNumber
        {
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
    // For new "_Edited" naming scheme, just append "_Edited" if not already present
    if !base.hasSuffix("_Edited") {
      return "\(base)_Edited"
    }

    // For backward compatibility with original "E" naming scheme
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
    // Handle new "_Edited" suffix naming scheme
    if base.hasSuffix("_Edited") {
      return String(base.dropLast(7))  // Remove "_Edited" (7 characters)
    }

    // Handle original "E" naming scheme for backward compatibility
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
}
