import AVFoundation
import Foundation
import GRDB
import ImageIO

struct ApplePhotosItem {
  let fileName: String
  let directory: String
  let originalFileName: String
  let fileURL: URL
  let fileSize: Int
  let metadata: MediaMetadata

  // Extended metadata
  let uniformTypeIdentifier: String?
  let timezoneName: String?
  let timezoneOffset: Int?
  let addedDate: Date?
  let longDescription: String?
  let focalLength: Double?
  let focalLength35mm: Int?
  let flashFired: Int?
  let exposureBias: Double?
  let meteringMode: Int?
  let whiteBalance: Int?
  let digitalZoomRatio: Double?
  let fps: Double?
  let bitrate: Double?
  let codec: String?
  let extendedTimezoneName: String?
  let extendedTimezoneOffset: Int?

  init(
    fileName: String,
    directory: String,
    originalFileName: String,
    fileURL: URL,
    fileSize: Int,
    metadata: MediaMetadata,
    uniformTypeIdentifier: String? = nil,
    timezoneName: String? = nil,
    timezoneOffset: Int? = nil,
    addedDate: Date? = nil,
    longDescription: String? = nil,
    focalLength: Double? = nil,
    focalLength35mm: Int? = nil,
    flashFired: Int? = nil,
    exposureBias: Double? = nil,
    meteringMode: Int? = nil,
    whiteBalance: Int? = nil,
    digitalZoomRatio: Double? = nil,
    fps: Double? = nil,
    bitrate: Double? = nil,
    codec: String? = nil,
    extendedTimezoneName: String? = nil,
    extendedTimezoneOffset: Int? = nil
  ) {
    self.fileName = fileName
    self.directory = directory
    self.originalFileName = originalFileName
    self.fileURL = fileURL
    self.fileSize = fileSize
    self.metadata = metadata
    self.uniformTypeIdentifier = uniformTypeIdentifier
    self.timezoneName = timezoneName
    self.timezoneOffset = timezoneOffset
    self.addedDate = addedDate
    self.longDescription = longDescription
    self.focalLength = focalLength
    self.focalLength35mm = focalLength35mm
    self.flashFired = flashFired
    self.exposureBias = exposureBias
    self.meteringMode = meteringMode
    self.whiteBalance = whiteBalance
    self.digitalZoomRatio = digitalZoomRatio
    self.fps = fps
    self.bitrate = bitrate
    self.codec = codec
    self.extendedTimezoneName = extendedTimezoneName
    self.extendedTimezoneOffset = extendedTimezoneOffset
  }
}

class ImportApplePhotos: ObservableObject {
  @Published var sortedMediaItems: [ApplePhotosMediaItem] = []
  @Published var selectedMediaItems: Set<MediaItem> = []

  private var scanCallbacks: ScanCallbacks?
  private var importCallbacks: ImportCallbacks?

  func previewPhotos(from photosURL: URL, with scanCallbacks: ScanCallbacks) async throws {
    self.sortedMediaItems = try await getMediaItems(from: photosURL, scanCallbacks: scanCallbacks)
  }

  internal func importItems(
    items: [ApplePhotosMediaItem],
    from photosURL: URL,
    to importedDirectory: URL,
    with importCallbacks: ImportCallbacks,
    progress: URLImportProgressCounter
  ) async throws {
    self.importCallbacks = importCallbacks

    try FileManager.default.createDirectory(
      at: importedDirectory, withIntermediateDirectories: true)

    let photos = try await getMediaItems(from: photosURL)
    for aPhoto in photos {
      progress.add(mediaItem: aPhoto)
    }

    for aPhoto in photos {
      try importOneItem(aPhoto, from: photosURL, to: importedDirectory, progress: progress)
    }

    importCallbacks.onComplete()
  }

  // Scan entire Apple Photos directory structure once
  private func scanApplePhotosDirectory(_ photosURL: URL) -> [URL: [String]] {
    var allFiles: [URL: [String]] = [:]

    // Recursively scan all directories under originals/
    let originalsURL = photosURL.appendingPathComponent("originals")

    // Recursive enumeration
    let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey]
    let enumerator = FileManager.default.enumerator(
      at: originalsURL,
      includingPropertiesForKeys: resourceKeys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )

    // Collect all files by full path
    while let fileURL = enumerator?.nextObject() as? URL {
      let path = fileURL.path.replacingOccurrences(
        of: photosURL.appendingPathComponent("originals/").path, with: "")
      let fileName = fileURL.lastPathComponent

      // Group files by their parent directory path
      let directoryPath = (path as NSString).deletingLastPathComponent
      if let directoryURL = URL(string: "file://\(directoryPath)") {
        if allFiles[directoryURL] == nil {
          allFiles[directoryURL] = []
        }
        allFiles[directoryURL]!.append(fileName)
      }
    }

    print("Scanned \(allFiles.values.flatMap { $0 }.count) files in Apple Photos library")
    return allFiles
  }

  private func getMediaItems(from photosURL: URL, scanCallbacks: ScanCallbacks? = nil)
    async throws -> [ApplePhotosMediaItem]
  {
    if sortedMediaItems.isEmpty {
      let rawItems = try fetchRawItems(from: photosURL)
      print("found \(rawItems.count) items from DB")

      // Find all related items in the directory.
      // 1) remove extension, 2) find any file that has the same prefix in the same directory with different suffix and extension
      // For example, these two files are related (a live photo)
      // file:///Users/appler/Downloads/ApplePhotos/originals/C/C02ABA48-1B5C-4ACF-AC42-6CF4B9313584.heic
      // file:///Users/appler/Downloads/ApplePhotos/originals/C/C02ABA48-1B5C-4ACF-AC42-6CF4B9313584_3.mov
      let allFiles = scanApplePhotosDirectory(photosURL)
      var relatedItems: [ApplePhotosItem] = []
      for rawItem in rawItems {
        let baseURL = rawItem.fileURL.deletingLastPathComponent()
        let basePrefix = rawItem.fileName.extractApplePhotosBaseName()

        // Get directory contents from our pre-scanned data
        let relativePath = baseURL.path.replacingOccurrences(
          of: photosURL.appendingPathComponent("originals/").path, with: "")
        guard let directoryPath = URL(string: "file://\(relativePath)"),
          let allFilesInDir = allFiles[directoryPath]
        else { continue }

        // Filter files that match base prefix (from pre-scanned data)
        let matchingFiles = allFilesInDir.filter { fileName in
          let filePrefix = fileName.extractApplePhotosBaseName()
          return filePrefix == basePrefix && rawItem.fileName != fileName
        }

        for matchingFile in matchingFiles {
          let fileURL = baseURL.appendingPathComponent(matchingFile)
          var fileSize = rawItem.fileSize
          var uti = rawItem.uniformTypeIdentifier
          let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey])
          if let sizeInBytes = values.fileSize {
            fileSize = sizeInBytes
          }
          if let uniformTypeIdentifier = values.typeIdentifier {
            uti = uniformTypeIdentifier
          }
          let relatedItem = ApplePhotosItem(
            fileName: matchingFile,
            directory: rawItem.directory,
            originalFileName: rawItem.originalFileName,
            fileURL: fileURL,
            fileSize: fileSize,
            metadata: rawItem.metadata,
            uniformTypeIdentifier: uti,
            timezoneName: rawItem.timezoneName,
            timezoneOffset: rawItem.timezoneOffset,
            addedDate: rawItem.addedDate,
            longDescription: rawItem.longDescription,
            focalLength: rawItem.focalLength,
            focalLength35mm: rawItem.focalLength35mm,
            flashFired: rawItem.flashFired,
            exposureBias: rawItem.exposureBias,
            meteringMode: rawItem.meteringMode,
            whiteBalance: rawItem.whiteBalance,
            digitalZoomRatio: rawItem.digitalZoomRatio,
            fps: rawItem.fps,
            bitrate: rawItem.bitrate,
            codec: rawItem.codec,
            extendedTimezoneName: rawItem.extendedTimezoneName,
            extendedTimezoneOffset: rawItem.extendedTimezoneOffset
          )
          relatedItems.append(relatedItem)
        }
      }

      let groupedItems = groupRelatedApplePhotoItems(rawItems + relatedItems, in: photosURL)
      print("found \(groupedItems.count) grouped items")

      for mediaItem in groupedItems {
        let editedUrl = mediaItem.editedUrl != nil ? mediaItem.editedUrl!.path : "no edited"
        let liveUrl = mediaItem.liveUrl != nil ? mediaItem.liveUrl!.path : "no live"
        print("\(mediaItem.originalUrl), \(editedUrl), \(liveUrl)")

        // Pre-generate and cache thumbnail
        if await ThumbnailCache.shared.generateAndCacheThumbnail(
          for: mediaItem.displayURL,
          mediaItem: mediaItem
        ) != nil {
          await MainActor.run { [mediaItem] in
            sortedMediaItems.insertSorted(mediaItem, by: \.thumbnailDate, order: .descending)
            // notify callback about new item in main thread to update UI asap
            if let onMediaFound = scanCallbacks?.onMediaFound {
              onMediaFound(mediaItem)
            }
          }
        }
      }
    }
    print("found \(sortedMediaItems.count) thumbnails")
    if let onComplete = self.scanCallbacks?.onComplete {
      onComplete()
    }
    return sortedMediaItems
  }

  private func fetchRawItems(from photosURL: URL) throws -> [ApplePhotosItem] {
    let sql = """
      SELECT
          ZASSET.ZFILENAME as filename,
          ZASSET.ZDIRECTORY as directory,
          ZASSET.ZUNIFORMTYPEIDENTIFIER as uniformTypeIdentifier,
          ZADDITIONALASSETATTRIBUTES.ZORIGINALFILENAME as originalFilename,
          ZADDITIONALASSETATTRIBUTES.ZORIGINALFILESIZE as fileSize,
          ZADDITIONALASSETATTRIBUTES.ZORIGINALWIDTH as originalWidth,
          ZADDITIONALASSETATTRIBUTES.ZORIGINALHEIGHT as originalHeight,
          ZADDITIONALASSETATTRIBUTES.ZORIGINALORIENTATION as originalOrientation,
          ZADDITIONALASSETATTRIBUTES.ZTIMEZONENAME as timezoneName,
          ZADDITIONALASSETATTRIBUTES.ZTIMEZONEOFFSET as timezoneOffset,
          ZASSET.ZDATECREATED as dateCreated,
          ZASSET.ZADDEDDATE as addedDate,
          ZASSET.ZMODIFICATIONDATE as modificationDate,
          ZASSET.ZLATITUDE as latitude,
          ZASSET.ZLONGITUDE as longitude,
          ZASSET.ZWIDTH as width,
          ZASSET.ZHEIGHT as height,
          ZASSET.ZORIENTATION as orientation,
          ZEXTENDEDATTRIBUTES.ZCAMERAMAKE as cameraMake,
          ZEXTENDEDATTRIBUTES.ZCAMERAMODEL as cameraModel,
          ZEXTENDEDATTRIBUTES.ZLENSMODEL as lensModel,
          ZEXTENDEDATTRIBUTES.ZISO as iso,
          ZEXTENDEDATTRIBUTES.ZAPERTURE as aperture,
          ZEXTENDEDATTRIBUTES.ZSHUTTERSPEED as shutterSpeed,
          ZEXTENDEDATTRIBUTES.ZFOCALLENGTH as focalLength,
          ZEXTENDEDATTRIBUTES.ZFOCALLENGTHIN35MM as focalLength35mm,
          ZEXTENDEDATTRIBUTES.ZFLASHFIRED as flashFired,
          ZEXTENDEDATTRIBUTES.ZEXPOSUREBIAS as exposureBias,
          ZEXTENDEDATTRIBUTES.ZMETERINGMODE as meteringMode,
          ZEXTENDEDATTRIBUTES.ZWHITEBALANCE as whiteBalance,
          ZEXTENDEDATTRIBUTES.ZDIGITALZOOMRATIO as digitalZoomRatio,
          ZEXTENDEDATTRIBUTES.ZFPS as fps,
          ZEXTENDEDATTRIBUTES.ZDURATION as duration,
          ZEXTENDEDATTRIBUTES.ZBITRATE as bitrate,
          ZEXTENDEDATTRIBUTES.ZCODEC as codec,
          ZEXTENDEDATTRIBUTES.ZDATECREATED as extendedDateCreated,
          ZEXTENDEDATTRIBUTES.ZTIMEZONENAME as extendedTimezoneName,
          ZEXTENDEDATTRIBUTES.ZTIMEZONEOFFSET as extendedTimezoneOffset,
          ZASSETDESCRIPTION.ZLONGDESCRIPTION as longDescription
      FROM ZASSET
      INNER JOIN ZADDITIONALASSETATTRIBUTES ON ZASSET.Z_PK = ZADDITIONALASSETATTRIBUTES.ZASSET
      LEFT JOIN ZEXTENDEDATTRIBUTES ON ZASSET.Z_PK = ZEXTENDEDATTRIBUTES.ZASSET
      LEFT JOIN ZASSETDESCRIPTION ON ZASSET.Z_PK = ZASSETDESCRIPTION.ZASSETATTRIBUTES
      """

    let dbURL = photosURL.appendingPathComponent("database/Photos.sqlite")
    let dbQueue = try DatabaseQueue(path: dbURL.path)
    return try dbQueue.read { db in
      let rows = try Row.fetchAll(db, sql: sql)

      var items: [ApplePhotosItem] = []
      for row in rows {
        let dbFileName = row[Column("filename")] as String
        let dbDirectory = row[Column("directory")] as String
        let originalFileURL =
          photosURL
          .appendingPathComponent("originals")
          .appendingPathComponent(dbDirectory)
          .appendingPathComponent(dbFileName)
        guard FileManager.default.fileExists(atPath: originalFileURL.path) else {
          continue  // Skip this database row
        }

        // Dates
        let creationDate = (row[Column("dateCreated")] as Double?).map {
          Date(timeIntervalSinceReferenceDate: $0)
        }
        let modificationDate = (row[Column("modificationDate")] as Double?).map {
          Date(timeIntervalSinceReferenceDate: $0)
        }
        let extendedDateCreated = (row[Column("extendedDateCreated")] as Double?).map {
          Date(timeIntervalSinceReferenceDate: $0)
        }

        // Dimensions - prefer original dimensions over asset dimensions
        let dimensions: CGSize?
        let originalWidth = row[Column("originalWidth")] as Int?
        let originalHeight = row[Column("originalHeight")] as Int?
        let width = row[Column("width")] as Int?
        let height = row[Column("height")] as Int?

        if let origWidth = originalWidth, let origHeight = originalHeight {
          dimensions = CGSize(width: CGFloat(origWidth), height: CGFloat(origHeight))
        } else if let w = width, let h = height {
          dimensions = CGSize(width: CGFloat(w), height: CGFloat(h))
        } else {
          dimensions = nil
        }

        // GPS - prefer extended attributes GPS over asset GPS
        let gps: GPSLocation?
        let extendedLatitude = row[Column("latitude")] as Double?
        let extendedLongitude = row[Column("longitude")] as Double?
        let assetLatitude = row[Column("latitude")] as Double?
        let assetLongitude = row[Column("longitude")] as Double?

        if let lat = extendedLatitude, let lon = extendedLongitude {
          gps = GPSLocation(latitude: lat, longitude: lon)
        } else if let lat = assetLatitude, let lon = assetLongitude {
          gps = GPSLocation(latitude: lat, longitude: lon)
        } else {
          gps = nil
        }

        // Camera metadata
        let make = row[Column("cameraMake")] as String?
        let model = row[Column("cameraModel")] as String?
        let lens = row[Column("lensModel")] as String?
        let iso = row[Column("iso")] as Int?
        let aperture = row[Column("aperture")] as Double?
        let shutterSpeedValue = row[Column("shutterSpeed")] as Double?
        let shutterSpeed = shutterSpeedValue.map { String(format: "1/%.0f", 1.0 / $0) }

        // Duration for videos
        let duration = row[Column("duration")] as Double?

        let metadata = MediaMetadata(
          creationDate: creationDate ?? extendedDateCreated,
          modificationDate: modificationDate,
          dimensions: dimensions,
          exifDate: extendedDateCreated,
          gps: gps,
          duration: duration,
          make: make,
          model: model,
          lens: lens,
          iso: iso,
          aperture: aperture,
          shutterSpeed: shutterSpeed
        )

        let item = ApplePhotosItem(
          fileName: dbFileName,
          directory: dbDirectory,
          originalFileName: (row[Column("originalFilename")] as String?) ?? "",
          fileURL: originalFileURL,
          fileSize: (row[Column("fileSize")] as Int?) ?? 0,
          metadata: metadata,
          uniformTypeIdentifier: row[Column("uniformTypeIdentifier")] as String?,
          timezoneName: row[Column("timezoneName")] as String?,
          timezoneOffset: row[Column("timezoneOffset")] as Int?,
          addedDate: (row[Column("addedDate")] as Double?).map {
            Date(timeIntervalSinceReferenceDate: $0)
          },
          longDescription: row[Column("longDescription")] as String?,
          focalLength: row[Column("focalLength")] as Double?,
          focalLength35mm: row[Column("focalLength35mm")] as Int?,
          flashFired: row[Column("flashFired")] as Int?,
          exposureBias: row[Column("exposureBias")] as Double?,
          meteringMode: row[Column("meteringMode")] as Int?,
          whiteBalance: row[Column("whiteBalance")] as Int?,
          digitalZoomRatio: row[Column("digitalZoomRatio")] as Double?,
          fps: row[Column("fps")] as Double?,
          bitrate: row[Column("bitrate")] as Double?,
          codec: row[Column("codec")] as String?,
          extendedTimezoneName: row[Column("extendedTimezoneName")] as String?,
          extendedTimezoneOffset: row[Column("extendedTimezoneOffset")] as Int?,
        )
        items.append(item)
      }
      return items
    }
  }

  private func importOneItem(
    _ item: ApplePhotosMediaItem,
    from photosURL: URL,
    to importedDirectory: URL,
    progress: URLImportProgressCounter
  ) throws {
    // Construct source URL
    var sourceURL = photosURL.appendingPathComponent("originals")
    if !item.directory.isEmpty {
      sourceURL = sourceURL.appendingPathComponent(item.directory)
    }
    sourceURL = sourceURL.appendingPathComponent(item.fileName)

    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      print("File not found: \(sourceURL.path)")
      if let importCallbacks = self.importCallbacks {
        importCallbacks.onMediaSkipped(item)
      }
      return
    }

    var urls = [item.originalUrl]
    if let edited = item.editedUrl { urls.append(edited) }
    if let live = item.liveUrl { urls.append(live) }
    for url in urls {

    }
    // Extract metadata from file
    let extractedMetadata = extractMetadata(from: sourceURL)

    // Use EXIF if available, else database
    let finalDate = item.metadata?.creationDate ?? extractedMetadata.exifDate

    // Determine destination filename
    let destinationFilename = item.originalFileName.isEmpty ? item.fileName : item.originalFileName

    // Create yyyy/mm/dd subdirectory if date is available
    let finalDirectory: URL
    if let date = finalDate {
      let calendar = Calendar.current
      let year = calendar.component(.year, from: date)
      let month = calendar.component(.month, from: date)
      let day = calendar.component(.day, from: date)
      let subDir = String(format: "%04d/%02d/%02d", year, month, day)
      finalDirectory = importedDirectory.appendingPathComponent(subDir)
      try FileManager.default.createDirectory(at: finalDirectory, withIntermediateDirectories: true)
    } else {
      finalDirectory = importedDirectory
    }

    let destinationURL = finalDirectory.appendingPathComponent(destinationFilename)

    // Copy file
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    if let fileDate = finalDate {
      var attributes = [FileAttributeKey: Any]()
      attributes[.creationDate] = fileDate
      attributes[.modificationDate] = fileDate

      do {
        try FileManager.default.setAttributes(attributes, ofItemAtPath: destinationURL.path)
      } catch {
        print("Failed to set file dates: \(error)")
      }
    }
    if let importCallbacks = self.importCallbacks {
      importCallbacks.onMediaImported(item)
    }

    // Here you could store the metadata in your app's database
    print("\(destinationFilename) with on \(finalDate?.description ?? "unknown")")
  }

  private func extractMetadata(from url: URL) -> MediaMetadata {
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
      shutterSpeed: nil
    )
  }
}
