import AVFoundation
import Foundation
import GRDB
import ImageIO

struct ExtractedMetadata {
  let dateCreated: Date?
  let latitude: Double?
  let longitude: Double?
  let orientation: Int?
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

  private func fetchPhotoMetadata() throws -> [MediaMetadata] {
    try dbQueue.read { db in
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

      let rows = try Row.fetchAll(db, sql: sql)

      return rows.map { row in
        MediaMetadata(
          creationDate: row["dateCreated"].map { Date(timeIntervalSinceReferenceDate: $0) },
          modificationDate: nil,
          dimensions: row["width"].flatMap { width in
            row["height"].map { height in
              CGSize(width: CGFloat(width), height: CGFloat(height))
            }
          },
          exifDate: nil,
          gps: row["latitude"].flatMap { latitude in
            row["longitude"].map { longitude in
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
  }

  private func importPhoto(_ metadata: MediaMetadata, to importedDirectory: URL) throws {
    // Construct source URL
    var sourceURL = self.photosURL.appendingPathComponent("originals")
    if let directory = metadata.directory {
      sourceURL = sourceURL.appendingPathComponent(directory)
    }
    sourceURL = sourceURL.appendingPathComponent(metadata.filename)

    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      print("File not found: \(sourceURL.path)")
      return
    }

    // Extract metadata from file
    let extractedMetadata = extractMetadata(from: sourceURL)

    // Use EXIF if available, else database
    let finalDate = extractedMetadata.dateCreated ?? metadata.creationDate
    let finalOrientation = extractedMetadata.orientation ?? metadata.orientation

    // Determine destination filename
    let destinationFilename = metadata.originalFilename ?? metadata.filename

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
      "Imported \(destinationFilename) with date: \(finalDate?.description ?? "unknown"), orientation: \(finalOrientation?.description ?? "unknown")"
    )
  }

  private func extractMetadata(from url: URL) -> ExtractedMetadata {
    var dateCreated: Date?
    var latitude: Double?
    var longitude: Double?
    var orientation: Int?

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

        // Orientation
        orientation = properties[kCGImagePropertyOrientation] as? Int
      }
    }

    return ExtractedMetadata(dateCreated: dateCreated, latitude: latitude, longitude: longitude, orientation: orientation)
  }
}