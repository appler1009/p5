import AVFoundation
import Foundation
import GRDB
import ImageIO

struct PhotoMetadata {
  let filename: String
  let directory: String?
  let originalFilename: String?
  let dateCreated: Double?
  let latitude: Double?
  let longitude: Double?
  let width: Int?
  let height: Int?
  let fileSize: Int64?
}

struct ExtractedMetadata {
  let dateCreated: Date?
  let latitude: Double?
  let longitude: Double?
}

class ImportApplePhotos {
  private let dbQueue: DatabaseQueue
  private let mastersURL: URL

  init(libraryURL: URL) throws {
    let dbURL = libraryURL.appendingPathComponent("database/Photos.sqlite")
    self.dbQueue = try DatabaseQueue(path: dbURL.path)
    self.mastersURL = libraryURL.appendingPathComponent("Masters")
  }

  func importPhotos(to importedDirectory: URL) throws {
    try FileManager.default.createDirectory(
      at: importedDirectory, withIntermediateDirectories: true)

    let photos = try fetchPhotoMetadata()

    for photo in photos {
      try importPhoto(photo, to: importedDirectory)
    }
  }

  private func fetchPhotoMetadata() throws -> [PhotoMetadata] {
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
            ZASSET.ZORIGINALFILESIZE as fileSize
        FROM ZASSET
        INNER JOIN ZADDITIONALASSETATTRIBUTES ON ZASSET.Z_PK = ZADDITIONALASSETATTRIBUTES.ZASSET
        """

      let rows = try Row.fetchAll(db, sql: sql)

      return rows.map { row in
        PhotoMetadata(
          filename: row["filename"],
          directory: row["directory"],
          originalFilename: row["originalFilename"],
          dateCreated: row["dateCreated"],
          latitude: row["latitude"],
          longitude: row["longitude"],
          width: row["width"],
          height: row["height"],
          fileSize: row["fileSize"]
        )
      }
    }
  }

  private func importPhoto(_ photo: PhotoMetadata, to importedDirectory: URL) throws {
    // Construct source URL
    var sourceURL = mastersURL
    if let directory = photo.directory {
      sourceURL = sourceURL.appendingPathComponent(directory)
    }
    sourceURL = sourceURL.appendingPathComponent(photo.filename)

    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      print("File not found: \(sourceURL.path)")
      return
    }

    // Extract metadata from file
    let extractedMetadata = extractMetadata(from: sourceURL)

    // Use EXIF if available, else database
    let finalDate =
      extractedMetadata.dateCreated
      ?? photo.dateCreated.map { Date(timeIntervalSinceReferenceDate: $0) }
    let finalLatitude = extractedMetadata.latitude ?? photo.latitude
    let finalLongitude = extractedMetadata.longitude ?? photo.longitude

    // Determine destination filename
    let destinationFilename = photo.originalFilename ?? photo.filename
    let destinationURL = importedDirectory.appendingPathComponent(destinationFilename)

    // Copy file
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

    // Here you could store the metadata in your app's database
    print("Imported \(destinationFilename) with date: \(finalDate?.description ?? "unknown")")
  }

  private func extractMetadata(from url: URL) -> ExtractedMetadata {
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

    return ExtractedMetadata(dateCreated: dateCreated, latitude: latitude, longitude: longitude)
  }
}
