import AVFoundation
import Foundation
import GRDB
import ImageIO

struct ApplePhotosMediaItem {
  let fileName: String
  let directory: String
  let originalFileName: String
  let fileSize: Int
  let metadata: MediaMetadata

  init(
    fileName: String, directory: String, originalFileName: String, fileSize: Int,
    metadata: MediaMetadata
  ) {
    self.fileName = fileName
    self.directory = directory
    self.originalFileName = originalFileName
    self.fileSize = fileSize
    self.metadata = metadata
  }
}

class ImportApplePhotos {
  private let dbQueue: DatabaseQueue
  private let photosURL: URL

  init(libraryURL: URL) throws {
    self.photosURL = libraryURL

    let dbURL = libraryURL.appendingPathComponent("database/Photos.sqlite")
    self.dbQueue = try DatabaseQueue(path: dbURL.path)
  }

  func importPhotos(to importedDirectory: URL) throws {
    try FileManager.default.createDirectory(
      at: importedDirectory, withIntermediateDirectories: true)

    let photos = try fetchPhotoMetadata()

    for metadata in photos {
      try importPhoto(metadata, to: importedDirectory)
    }
  }

  private func fetchPhotoMetadata() throws -> [ApplePhotosMediaItem] {
    let sql = """
      SELECT
          ZASSET.ZFILENAME as filename,
          ZASSET.ZDIRECTORY as directory,
          ZADDITIONALASSETATTRIBUTES.ZORIGINALFILENAME as originalFilename,
          ZASSET.ZDATECREATED as dateCreated,
          ZASSET.ZLATITUDE as latitude,
          ZASSET.ZLONGITUDE as longitude,
          ZASSET.ZWIDTH as width,
          ZASSET.ZHEIGHT as height,
          ZADDITIONALASSETATTRIBUTES.ZORIGINALFILESIZE as fileSize,
          ZASSET.ZORIENTATION as orientation
      FROM ZASSET
      INNER JOIN ZADDITIONALASSETATTRIBUTES ON ZASSET.Z_PK = ZADDITIONALASSETATTRIBUTES.ZASSET
      """

    return try dbQueue.read { db in
      let rows = try Row.fetchAll(db, sql: sql)

      var items: [ApplePhotosMediaItem] = []
      for row in rows {
        let creationDate = (row[Column("dateCreated")] as Double?).map {
          Date(timeIntervalSinceReferenceDate: $0)
        }

        let dimensions: CGSize?
        if let width = row[Column("width")] as Int?, let height = row[Column("height")] as Int? {
          dimensions = CGSize(width: CGFloat(width), height: CGFloat(height))
        } else {
          dimensions = nil
        }

        let gps: GPSLocation?
        if let latitude = row[Column("latitude")] as Double?,
          let longitude = row[Column("longitude")] as Double?
        {
          gps = GPSLocation(latitude: latitude, longitude: longitude)
        } else {
          gps = nil
        }

        let metadata = MediaMetadata(
          creationDate: creationDate,
          modificationDate: nil,
          dimensions: dimensions,
          exifDate: nil,
          gps: gps,
          make: nil,
          model: nil,
          lens: nil,
          iso: nil,
          aperture: nil,
          shutterSpeed: nil
        )

        let item = ApplePhotosMediaItem(
          fileName: row[Column("filename")] as String,
          directory: row[Column("directory")] as String,
          originalFileName: row[Column("originalFilename")] as String,
          fileSize: row[Column("fileSize")] as Int,
          metadata: metadata
        )
        items.append(item)
      }
      return items
    }
  }

  private func importPhoto(_ item: ApplePhotosMediaItem, to importedDirectory: URL) throws {
    // Construct source URL
    var sourceURL = self.photosURL.appendingPathComponent("originals")
    if !item.directory.isEmpty {
      sourceURL = sourceURL.appendingPathComponent(item.directory)
    }
    sourceURL = sourceURL.appendingPathComponent(item.fileName)

    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      print("File not found: \(sourceURL.path)")
      return
    }

    // Extract metadata from file
    let extractedMetadata = extractMetadata(from: sourceURL)

    // Use EXIF if available, else database
    let finalDate = item.metadata.creationDate ?? extractedMetadata.exifDate

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

    // Here you could store the metadata in your app's database
    print(
      "Imported \(destinationFilename) with date: \(finalDate?.description ?? "unknown")"
    )
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
