import AVFoundation
import Foundation
import GRDB
import ImageIO

class ImportLocalFiles: @unchecked Sendable {
  private var mediaItems: [LocalFileSystemMediaItem] = []
  private var sourceDirectory: URL?

  func previewPhotos(sourceDirectory: URL, scanCallbacks: ScanCallbacks) async throws {
    let mediaItems = try await getMediaItems(sourceDirectory: sourceDirectory)
    print("found \(mediaItems.count) media items")

    for mediaItem in mediaItems {
      // Pre-generate and cache thumbnail
      if await ThumbnailCache.shared.generateAndCacheThumbnail(
        for: mediaItem.displayURL,
        mediaItem: mediaItem
      ) != nil {
        await MainActor.run { [mediaItem] in
          scanCallbacks.onMediaFound(mediaItem)  // notify callback about new item
        }
      }
    }
  }

  internal func importPhotos(
    items: [LocalFileSystemMediaItem],
    from sourceDirectory: URL,
    to importedDirectory: URL,
    callbacks: ImportCallbacks,
    progress: URLImportProgressCounter
  ) async throws {
    try FileManager.default.createDirectory(
      at: importedDirectory, withIntermediateDirectories: true)

    // put them all into the progress
    progress.setItems(items: items)

    // actually process one by one
    for oneItem in items {
      try importMedia(oneItem, to: importedDirectory)
    }
  }

  private func getMediaItems(sourceDirectory: URL)
    async throws -> [LocalFileSystemMediaItem]
  {
    if mediaItems.isEmpty {
      let fileManager = FileManager.default
      guard
        let enumerator = fileManager.enumerator(
          at: sourceDirectory,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
      else { return [] }

      var rawItems: [URL] = []
      while let fileURL = enumerator.nextObject() as? URL {
        if fileURL.isMedia() {
          rawItems.append(fileURL)
        }
      }
      print("found \(rawItems.count) items from \(sourceDirectory)")

      let groupedItems = await groupRelatedURLs(rawItems)
      print("found \(groupedItems.count) grouped items")
    }

    return mediaItems
  }

  private func importMedia(_ item: LocalFileSystemMediaItem, to importedDirectory: URL) throws {
    var urls: [URL] = [
      item.originalUrl
    ]
    if let editedURL = item.editedUrl {
      urls.append(editedURL)
    }
    if let liveURL = item.liveUrl {
      urls.append(liveURL)
    }

    // Create yyyy/mm/dd subdirectory if date is available
    let calendar = Calendar.current
    let year = calendar.component(.year, from: item.thumbnailDate)
    let month = calendar.component(.month, from: item.thumbnailDate)
    let day = calendar.component(.day, from: item.thumbnailDate)
    let subDir = String(format: "%04d/%02d/%02d", year, month, day)
    let finalDirectory = importedDirectory.appendingPathComponent(subDir)
    try FileManager.default.createDirectory(at: finalDirectory, withIntermediateDirectories: true)

    for url in urls {
      guard FileManager.default.fileExists(atPath: url.path) else {
        print("File not found: \(url.path)")
        continue
      }

      // Determine destination filename
      let destinationURL = finalDirectory.appendingPathComponent(url.lastPathComponent)

      // Copy file
      try FileManager.default.copyItem(at: url, to: destinationURL)
    }
  }

  private func extractMetadataz(from url: URL) -> MediaMetadata {
    var dateCreated: Date?
    var latitude: Double?
    var longitude: Double?

    if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
      if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
        // EXIF date
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
          let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        {
          let formatter = DateFormatter()
          formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
          dateCreated = formatter.date(from: dateString)
        }

        // GPS
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
          let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
          let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
          let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
          let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        {
          latitude = latRef == "N" ? lat : -lat
          longitude = lonRef == "E" ? lon : -lon
        }
      }
    }

    return MediaMetadata(
      creationDate: nil,
      modificationDate: nil,
      dimensions: nil,
      exifDate: dateCreated,
      gps: latitude.flatMap { latitude in
        longitude.map { longitude in
          GPSLocation(latitude: latitude, longitude: longitude)
        }
      },
      make: nil,
      model: nil,
      lens: nil,
      iso: nil,
      aperture: nil,
      shutterSpeed: nil,
      extraEXIF: [:]
    )
  }
}
