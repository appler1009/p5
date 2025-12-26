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

      // If DB exists and media_items table lacks blurhash column, recreate DB
      if FileManager.default.fileExists(atPath: dbPath) {
        let tempQueue = try DatabaseQueue(path: dbPath)
        var needsRecreate = false
        try tempQueue.read { db in
          if try db.tableExists("media_items") {
            let columns = try db.columns(in: "media_items").map { $0.name }
            if !columns.contains("blurhash") {
              needsRecreate = true
            }
          }
        }
        if needsRecreate {
          try FileManager.default.removeItem(atPath: dbPath)
        }
      }

      dbQueue = try DatabaseQueue(path: dbPath)
      try createTable()
    } catch {
      print("Database init error: \(error)")
    }
  }

  private func createTable() throws {
    try dbQueue?.write { db in
      try db.create(table: "media_items", ifNotExists: true) { t in
        t.column("id", .integer).primaryKey(autoincrement: true)
        t.column("url", .text).unique()
        t.column("type", .text)
        t.column("filename", .text)
        t.column("creation_date", .datetime)
        t.column("modification_date", .datetime)
        t.column("width", .double)
        t.column("height", .double)
        t.column("exif_date", .datetime)
        t.column("latitude", .double)
        t.column("longitude", .double)
        t.column("blurhash", .text)
        t.column("exif", .text)
      }
      try db.create(table: "directories", ifNotExists: true) { t in
        t.column("id", .integer).primaryKey(autoincrement: true)
        t.column("path", .text)
        t.column("bookmark", .text)
      }
    }
  }

  func insertItem(_ item: MediaItem) {
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
            INSERT OR REPLACE INTO media_items (url, type, filename, creation_date, modification_date, width, height, exif_date, latitude, longitude, blurhash, exif)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            item.url.absoluteString,
            String(describing: item.type),
            metadata.filename,
            metadata.creationDate,
            metadata.modificationDate,
            metadata.dimensions?.width,
            metadata.dimensions?.height,
            metadata.exifDate,
            metadata.gps?.latitude,
            metadata.gps?.longitude,
            item.blurhash,
            exifString,
          ]
        )
      }
    } catch {
      print("Insert error: \(error)")
    }
  }

  func getAllItems() -> [MediaItem] {
    var items: [MediaItem] = []
    do {
      try dbQueue?.read { db in
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM media_items")
        for row in rows {
          guard let urlString = row["url"] as String?,
            let url = URL(string: urlString),
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
            filePath: url.path,
            filename: row["filename"] as String? ?? "",
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

          let item = MediaItem(
            url: url, type: itemType, metadata: meta, displayName: nil,
            blurhash: row["blurhash"] as String?)
          items.append(item)
        }
      }
    } catch {
      print("Query error: \(error)")
    }
    return items
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

  func updateBlurhash(for url: URL, hash: String) {
    do {
      try dbQueue?.write { db in
        try db.execute(
          sql: "UPDATE media_items SET blurhash = ? WHERE url = ?",
          arguments: [hash, url.absoluteString]
        )
      }
    } catch {
      print("Update blurhash error: \(error)")
    }
  }

  func clearAll() {
    do {
      try dbQueue?.write { db in
        try db.execute(sql: "DELETE FROM media_items")
      }
    } catch {
      print("Clear error: \(error)")
    }
  }
}
