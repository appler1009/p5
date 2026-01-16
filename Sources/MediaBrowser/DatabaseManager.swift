import Foundation
import GRDB

@MainActor
class DatabaseManager: ObservableObject {
  static let shared = DatabaseManager()
  static let databaseFileExtension = "photos"
  private var dbQueue: DatabaseQueue?
  private var currentDbPath: String?

  var databasePath: String? {
    currentDbPath
  }

  private init() {
    let defaultPath =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path
      + "/MediaBrowser/media.\(Self.databaseFileExtension)"
    let dbPath = UserDefaults.standard.string(forKey: "databasePath") ?? defaultPath
    openDatabase(at: dbPath)
  }

  func switchToDatabase(at path: String) {
    UserDefaults.standard.set(path, forKey: "databasePath")
    openDatabase(at: path)
  }

  private func openDatabase(at path: String) {
    do {
      dbQueue = nil  // Close previous if any
      currentDbPath = path

      let directory = (path as NSString).deletingLastPathComponent
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

      print("Opening database at: \(path)")

      // If DB exists and local_media_items table lacks s3_sync_status column, add it
      if FileManager.default.fileExists(atPath: path) {
        let tempQueue = try DatabaseQueue(path: path)
        try tempQueue.write { db in
          if try db.tableExists("local_media_items") {
            let columns = try db.columns(in: "local_media_items").map { $0.name }
            if !columns.contains("s3_sync_status") {
              try db.alter(table: "local_media_items") { t in
                t.add(column: "s3_sync_status", .text).defaults(to: S3SyncStatus.notSynced.rawValue)
              }
            }
            if !columns.contains("geocode") {
              try db.alter(table: "local_media_items") { t in
                t.add(column: "geocode", .text)
              }
            }
          }
        }
      }

      dbQueue = try DatabaseQueue(path: path)
      try createTable()
    } catch {
      print("Database open error: \(error)")
    }
  }

  func saveDirectories(_ directoryStates: [(URL, Bool)]) {
    do {
      try dbQueue?.write { db in
        try db.execute(sql: "DELETE FROM directories")
        for (url, _) in directoryStates {
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

  func loadDirectories() -> [(URL, Bool)] {
    var directoryStates: [(URL, Bool)] = []
    do {
      try dbQueue?.read { db in
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM directories")
        for row in rows {
          if let path = row["path"] as String? {
            let url = URL(fileURLWithPath: path)
            var isStale = true
            if let bookmarkBase64 = row["bookmark"] as String?,
              let bookmarkData = Data(base64Encoded: bookmarkBase64)
            {
              if let resolvedUrl = try? URL(
                resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil,
                bookmarkDataIsStale: &isStale), !isStale
              {
                directoryStates.append((resolvedUrl, false))
                continue
              }
            }
            // If no bookmark or stale, show path with stale
            directoryStates.append((url, true))
          }
        }
      }
    } catch {
      print("Load directories error: \(error)")
    }
    return directoryStates
  }

  func clearAll() {
    print("DELETE FROM local_media_items")
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

  func updateEditedUrl(for itemId: Int, editedUrl: URL) {
    do {
      try dbQueue?.write { db in
        try db.execute(
          sql: "UPDATE local_media_items SET edited_url = ? WHERE id = ?",
          arguments: [editedUrl.absoluteString, itemId]
        )
      }
    } catch {
      print("Update edited URL error: \(error)")
    }
  }

  func updateGeocode(for itemId: Int, geocode: String) {
    do {
      try dbQueue?.write { db in
        try db.execute(
          sql: "UPDATE local_media_items SET geocode = ? WHERE id = ?",
          arguments: [geocode, itemId]
        )
      }
    } catch {
      print("Update geocode error: \(error)")
    }
  }

  func getItemsNeedingGeocode(limit: Int = 50) -> [LocalFileSystemMediaItem] {
    var items: [LocalFileSystemMediaItem] = []
    do {
      try dbQueue?.read { db in
        let rows = try Row.fetchAll(
          db,
          sql:
            "SELECT * FROM local_media_items WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND (geocode IS NULL OR geocode = '') LIMIT ?",
          arguments: [limit])

        for row in rows {
          guard let itemId = row["id"] as Int?,
            let originalUrlString = row["original_url"] as String?,
            let originalUrl = URL(string: originalUrlString)
          else { continue }

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
            shutterSpeed: nil,
            geocode: row["geocode"] as String?,
            extraEXIF: [:]
          )

          // Load additional metadata from EXIF JSON
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
            meta.shutterSpeed = exifDict["shutterSpeed"] as? String
          }

          let item = LocalFileSystemMediaItem(
            id: itemId,
            original: originalUrl,
            edited: row["edited_url"] as String? != nil
              ? URL(string: row["edited_url"] as! String) : nil,
            live: row["live_video_url"] as String? != nil
              ? URL(string: row["live_video_url"] as! String) : nil
          )
          item.metadata = meta
          items.append(item)
        }
      }
    } catch {
      print("Error fetching items needing geocode: \(error)")
    }
    return items
  }

  private func createTable() throws {
    try dbQueue?.write { db in
      try db.create(table: "local_media_items", ifNotExists: true) { t in
        t.column("id", .integer).primaryKey(autoincrement: true)
        t.column("original_url", .text).unique()
        t.column("edited_url", .text)
        t.column("live_video_url", .text)
        t.column("display_name", .text)

        t.column("creation_date", .datetime)
        t.column("modification_date", .datetime)
        t.column("exif_date", .datetime)
        t.column("width", .double)
        t.column("height", .double)
        t.column("latitude", .double)
        t.column("longitude", .double)
        t.column("exif", .text)
        t.column("geocode", .text)
        t.column("s3_sync_status", .text).defaults(to: S3SyncStatus.notApplicable.rawValue)
        t.column("directory_id", .integer)
      }
      try db.create(table: "directories", ifNotExists: true) { t in
        t.column("id", .integer).primaryKey(autoincrement: true)
        t.column("path", .text).unique()
        t.column("bookmark", .text)
      }
      try db.create(table: "settings", ifNotExists: true) { t in
        t.column("key", .text).primaryKey()
        t.column("value", .text)
      }
    }
  }

  func insertItem(_ item: LocalFileSystemMediaItem) {
    guard let metadata = item.metadata else { return }

    var filteredEXIF: [String: Any] = [:]

    if let altitude = metadata.gps?.altitude, altitude.isFinite {
      filteredEXIF["altitude"] = altitude
    }
    if let duration = metadata.duration, duration.isFinite {
      filteredEXIF["duration"] = duration
    }
    if let make = metadata.make { filteredEXIF["make"] = make }
    if let model = metadata.model { filteredEXIF["model"] = model }
    if let lens = metadata.lens { filteredEXIF["lens"] = lens }
    if let iso = metadata.iso { filteredEXIF["iso"] = iso }
    if let aperture = metadata.aperture, aperture.isFinite {
      filteredEXIF["aperture"] = aperture
    }
    if let shutterSpeed = metadata.shutterSpeed { filteredEXIF["shutter_speed"] = shutterSpeed }

    for (key, value) in metadata.extraEXIF {
      filteredEXIF[key] = value
    }

    let exifData = try? JSONSerialization.data(withJSONObject: filteredEXIF, options: [])
    let exifString = exifData.flatMap { String(data: $0, encoding: .utf8) }

    do {
      try dbQueue?.write { db in
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO local_media_items (
              original_url,
              edited_url,
              live_video_url,
              display_name,

              creation_date,
              modification_date,
              exif_date,
              width,

              height,
              latitude,
              longitude,
              exif,

              geocode,
              s3_sync_status
            )
            VALUES (
              ?, ?, ?, ?,
              ?, ?, ?, ?,
              ?, ?, ?, ?,
              ?, ?
            )
            """,
          arguments: [
            item.originalUrl.absoluteString,
            item.editedUrl?.absoluteString,
            item.liveUrl?.absoluteString,
            item.originalUrl.lastPathComponent,

            metadata.creationDate,
            metadata.modificationDate,
            metadata.exifDate,
            metadata.dimensions?.width,

            metadata.dimensions?.height,
            metadata.gps?.latitude,
            metadata.gps?.longitude,
            exifString,

            metadata.geocode,
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
            let originalUrl = URL(string: originalUrlString)
          else { continue }
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
            shutterSpeed: nil,
            geocode: row["geocode"] as String?,
            extraEXIF: [:]
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

            let knownKeys = Set([
              "altitude", "duration", "make", "model", "lens", "iso", "aperture", "shutter_speed",
            ])
            for (key, value) in exifDict {
              if !knownKeys.contains(key) {
                meta.extraEXIF[key] = value as? String ?? "\(value)"
              }
            }
          }

          let syncStatusString = row["s3_sync_status"] as String?
          let syncStatus = syncStatusString.flatMap { S3SyncStatus(rawValue: $0) } ?? .notSynced

          let editedUrlString = row["edited_url"] as? String
          let editedUrl = editedUrlString.flatMap { URL(string: $0) }
          let liveUrlString = row["live_video_url"] as? String
          let liveUrl = liveUrlString.flatMap { URL(string: $0) }

          let item = LocalFileSystemMediaItem(
            id: itemId, original: originalUrl, edited: editedUrl, live: liveUrl)
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

  func hasDuplicate(baseName: String, date: Date) -> Bool {
    guard let dbQueue = dbQueue else { return false }
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return false
    }
    let startOfDay = Calendar.current.date(
      from: DateComponents(year: year, month: month, day: day))!
    let endOfDay = Calendar.current.date(
      from: DateComponents(year: year, month: month, day: day + 1))!
    let count = try? dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT
            COUNT(*)
          FROM
            local_media_items
          WHERE
            (
              (
                creation_date >= ?
                AND creation_date < ?
              )
              OR (
                exif_date >= ?
                AND exif_date < ?
              )
            )
            AND display_name LIKE ?
          """,
        arguments: [startOfDay, endOfDay, startOfDay, endOfDay, "\(baseName).%"]) ?? 0
    }
    return (count ?? 0) > 0
  }

  // MARK: - Settings Management

  func getSetting(_ key: String) -> String? {
    do {
      return try dbQueue?.read { db in
        try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
      }
    } catch {
      print("Error getting setting \(key): \(error)")
      return nil
    }
  }

  func setSetting(_ key: String, value: String) {
    do {
      try dbQueue?.write { db in
        try db.execute(
          sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
          arguments: [key, value])
      }
    } catch {
      print("Error setting \(key): \(error)")
    }
  }

  func getAllSettings() -> [String: String] {
    var settings: [String: String] = [:]
    do {
      try dbQueue?.read { db in
        let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
        for row in rows {
          if let key = row["key"] as String?, let value = row["value"] as String? {
            settings[key] = value
          }
        }
      }
    } catch {
      print("Error getting all settings: \(error)")
    }
    return settings
  }
}
