import Foundation
import GRDB

class DatabaseManager {
  static let shared = DatabaseManager()
  private var dbQueue: DatabaseQueue?

  private init() {
    do {
      let path =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path
        + "/MediaBrowser"
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
      let dbPath = "\(path)/media.db"

      // If DB exists and local_media_items table lacks s3_sync_status column, add it
      if FileManager.default.fileExists(atPath: dbPath) {
        let tempQueue = try DatabaseQueue(path: dbPath)
        try tempQueue.write { db in
          if try db.tableExists("local_media_items") {
            let columns = try db.columns(in: "local_media_items").map { $0.name }
            if !columns.contains("s3_sync_status") {
              try db.alter(table: "local_media_items") { t in
                t.add(column: "s3_sync_status", .text).defaults(to: S3SyncStatus.notSynced.rawValue)
              }
            }
          }
        }
      }

      dbQueue = try DatabaseQueue(path: dbPath)
      try createTable()
    } catch {
      print("Database init error: \(error)")
    }
  }

  func saveDirectories(_ directories: [URL]) {
    do {
      try dbQueue?.write { db in
        try db.execute(sql: "DELETE FROM directories")
        for url in directories {
          let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
          let bookmarkBase64 = bookmarkData.base64EncodedString()
          try db.execute(
            sql: "INSERT INTO directories (path, bookmark) VALUES (?, ?)",
            arguments: [url.path, bookmarkBase64])
        }
      }
    } catch {
      print("Save directories error: \(error)")
    }
  }

  func loadDirectories() -> [URL] {
    var directories: [URL] = []
    do {
      try dbQueue?.read { db in
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM directories")
        for row in rows {
          if let bookmarkBase64 = row["bookmark"] as String?,
            let bookmarkData = Data(base64Encoded: bookmarkBase64)
          {
            var isStale = false
            if let url = try? URL(
              resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil,
              bookmarkDataIsStale: &isStale), !isStale
            {
              directories.append(url)
            }
          }
        }
      }
    } catch {
      print("Load directories error: \(error)")
    }
    return directories
  }

  func clearAll() {
    do {
      try dbQueue?.write { db in
        try db.execute(sql: "DELETE FROM local_media_items")
      }
    } catch {
      print("Clear error: \(error)")
    }
  }

  func updateS3SyncStatus(for item: MediaItem) {
    do {
      try dbQueue?.write { db in
        try db.execute(
          sql: "UPDATE local_media_items SET s3_sync_status = ? WHERE id = ?",
          arguments: [item.s3SyncStatus.rawValue, item.id]
        )
      }
    } catch {
      print("Update S3 sync status error: \(error)")
    }
  }

  private func createTable() throws {
    try dbQueue?.write { db in
      try db.create(table: "local_media_items", ifNotExists: true) { t in
        t.column("id", .integer).primaryKey(autoincrement: true)
        t.column("original_url", .text).unique()
        t.column("edited_url", .text)
        t.column("live_video_url", .text)
        t.column("type", .text)
        t.column("creation_date", .datetime)
        t.column("modification_date", .datetime)
        t.column("exif_date", .datetime)
        t.column("width", .double)
        t.column("height", .double)
        t.column("latitude", .double)
        t.column("longitude", .double)
        t.column("exif", .text)
        t.column("s3_sync_status", .text).defaults(to: S3SyncStatus.notApplicable.rawValue)
        t.column("directory_id", .integer)
      }
      try db.create(table: "directories", ifNotExists: true) { t in
        t.column("id", .integer).primaryKey(autoincrement: true)
        t.column("path", .text)
        t.column("bookmark", .text)
      }
    }
  }

  func insertItem(_ item: LocalFileSystemMediaItem) {
    guard let metadata = item.metadata else { return }
    let exifDict: [String: Any] = [
      "altitude": metadata.gps?.altitude as Any,
      "duration": metadata.duration as Any,
      "make": metadata.make as Any,
      "model": metadata.model as Any,
      "lens": metadata.lens as Any,
      "iso": metadata.iso as Any,
      "aperture": metadata.aperture as Any,
      "shutter_speed": metadata.shutterSpeed as Any,
    ].compactMapValues { $0 }
    let exifData = try? JSONSerialization.data(withJSONObject: exifDict, options: [])
    let exifString = exifData.flatMap { String(data: $0, encoding: .utf8) }

    do {
      try dbQueue?.write { db in
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO local_media_items (
              original_url,
              edited_url,
              live_video_url,
              type,

              creation_date,
              modification_date,
              exif_date,
              width,

              height,
              latitude,
              longitude,
              exif,

              s3_sync_status
            )
            VALUES (
              ?, ?, ?, ?,
              ?, ?, ?, ?,
              ?, ?, ?, ?,
              ?
            )
            """,
          arguments: [
            item.originalUrl.absoluteString,
            item.editedUrl?.absoluteString,
            item.liveUrl?.absoluteString,
            String(describing: item.type),

            metadata.creationDate,
            metadata.modificationDate,
            metadata.exifDate,
            metadata.dimensions?.width,

            metadata.dimensions?.height,
            metadata.gps?.latitude,
            metadata.gps?.longitude,
            exifString,

            item.s3SyncStatus.rawValue,
          ]
        )
      }
    } catch {
      print("Insert error: \(error)")
    }
  }

  func getAllItems() -> [LocalFileSystemMediaItem] {
    var items: [LocalFileSystemMediaItem] = []
    do {
      try dbQueue?.read { db in
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM local_media_items")
        for row in rows {
          guard let itemId = row["id"] as Int?,
            let originalUrlString = row["original_url"] as String?,
            let originalUrl = URL(string: originalUrlString),
            let typeString = row["type"] as String?
          else { continue }
          let itemType: MediaType
          switch typeString {
          case "photo": itemType = .photo
          case "livePhoto": itemType = .livePhoto
          case "video": itemType = .video
          default: continue
          }
          var meta = MediaMetadata(
            creationDate: row["creation_date"] as Date?,
            modificationDate: row["modification_date"] as Date?,
            dimensions: {
              if let w = row["width"] as Double?, let h = row["height"] as Double? {
                return CGSize(width: w, height: h)
              }
              return nil
            }(),
            exifDate: row["exif_date"] as Date?,
            gps: {
              if let lat = row["latitude"] as Double?, let lon = row["longitude"] as Double? {
                return GPSLocation(latitude: lat, longitude: lon, altitude: nil)
              }
              return nil
            }(),
            duration: nil,
            make: nil,
            model: nil,
            lens: nil,
            iso: nil,
            aperture: nil,
            shutterSpeed: nil
          )

          if let exifString = row["exif"] as String?, let exifData = exifString.data(using: .utf8),
            let exifDict = try? JSONSerialization.jsonObject(with: exifData) as? [String: Any]
          {
            meta.gps?.altitude = exifDict["altitude"] as? Double
            meta.duration = exifDict["duration"] as? Double
            meta.make = exifDict["make"] as? String
            meta.model = exifDict["model"] as? String
            meta.lens = exifDict["lens"] as? String
            meta.iso = exifDict["iso"] as? Int
            meta.aperture = exifDict["aperture"] as? Double
            meta.shutterSpeed = exifDict["shutter_speed"] as? String
          }

          let syncStatusString = row["s3_sync_status"] as String?
          let syncStatus = syncStatusString.flatMap { S3SyncStatus(rawValue: $0) } ?? .notSynced

          let item = LocalFileSystemMediaItem(id: itemId, type: itemType, original: originalUrl)
          item.metadata = meta
          item.s3SyncStatus = syncStatus
          items.append(item)
        }
      }
    } catch {
      print("Query error: \(error)")
    }
    return items
  }
}
