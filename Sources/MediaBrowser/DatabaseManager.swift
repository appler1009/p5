import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()
    private var dbQueue: DatabaseQueue?

    private init() {
        do {
            let path = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first! + "/MediaBrowser"
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: "\(path)/media.db")
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
                t.column("altitude", .double)
                t.column("duration", .double)
            }
        }
    }

    func insertItem(_ item: MediaItem) {
        guard let metadata = item.metadata else { return }
        do {
            try dbQueue?.write { db in
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO media_items (url, type, filename, creation_date, modification_date, width, height, exif_date, latitude, longitude, altitude, duration)
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
                        metadata.gps?.altitude,
                        metadata.duration
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
                          let typeString = row["type"] as String? else { continue }
                    let itemType: MediaType
                    switch typeString {
                    case "photo": itemType = .photo
                    case "livePhoto": itemType = .livePhoto
                    case "video": itemType = .video
                    default: continue
                    }
                    let meta = MediaMetadata(
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
                                return GPSLocation(latitude: lat, longitude: lon, altitude: row["altitude"] as Double?)
                            }
                            return nil
                        }(),
                        duration: row["duration"] as Double?
                    )
                    let item = MediaItem(url: url, type: itemType, metadata: meta)
                    items.append(item)
                }
            }
        } catch {
            print("Query error: \(error)")
        }
        return items
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