import AVFoundation
import AVFoundation
import Combine
import CryptoKit
import SwiftUI

extension Notification.Name {
  static let thumbnailDidBecomeAvailable = Notification.Name("ThumbnailDidBecomeAvailable")
}

@MainActor
class ThumbnailCache {
  @MainActor static let shared = ThumbnailCache()
  private var cache = NSCache<NSString, NSImage>()
  private let cacheDir: String
  static let thumbnailSize = CGSize(width: 200, height: 200)
  static let thumbnailExtension = "jpg"

  private init() {
    let cacheDirURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("MediaBrowser/thumbnails")
    cacheDir = cacheDirURL.path
    try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
  }

  func thumbnail(mediaItem: MediaItem) -> NSImage? {
    return self.thumbnail(date: mediaItem.thumbnailDate, basename: mediaItem.displayName)
  }

  func thumbnail(date: Date, basename: String) -> NSImage? {
    let filename = filenameForThumbnail(date: date, basename: basename)
    let key = filename as NSString  // Use filename as cache key

    if let image = cache.object(forKey: key) {
      return image
    }
    if let image = loadFromDisk(key: filename) {
      cache.setObject(image, forKey: key)
      return image
    }
    return nil  // No thumbnail available in cache
  }

  func thumbnailExists(mediaItem: MediaItem) -> Bool {
    return self.thumbnailExists(date: mediaItem.thumbnailDate, basename: mediaItem.displayName)
  }

  func thumbnailExists(date: Date, basename: String) -> Bool {
    let filename = filenameForThumbnail(date: date, basename: basename)
    let key = filename as NSString

    // Check in-memory cache first
    if cache.object(forKey: key) != nil {
      return true
    }

    // Check disk existence without loading the image
    let filePath = cacheDir + "/" + filename
    return FileManager.default.fileExists(atPath: filePath)
  }

  func generateAndCacheThumbnail(for url: URL, mediaItem: MediaItem) async -> NSImage? {
    return await generateAndCacheThumbnail(
      for: url,
      date: mediaItem.thumbnailDate,
      basename: mediaItem.displayName,
      mediaItemId: mediaItem.id
    )
  }

  func generateAndCacheThumbnail(for url: URL, date: Date, basename: String, mediaItemId: Int = -1)
    async -> NSImage?
  {
    guard let image = await generateThumbnail(for: url) else { return nil }

    // Cache the generated thumbnail
    let filename = filenameForThumbnail(date: date, basename: basename)
    let key = filename as NSString

    cache.setObject(image, forKey: key)
    saveToDisk(image: image, key: filename)

    // Notify observers that thumbnail became available
    NotificationCenter.default.post(
      name: .thumbnailDidBecomeAvailable,
      object: nil,
      userInfo: [
        "date": date,
        "basename": basename,
        "mediaItemId": mediaItemId,
      ]
    )

    return image
  }

  // Generate filename for pre-generated thumbnails (used by ImportView)
  func filenameForThumbnail(date: Date, basename: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd"
    let dateString = dateFormatter.string(from: date)
    let combined = "\(dateString)_\(basename)"

    let md5Hash =
      combined.data(using: .utf8).map { data in
        Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
      } ?? "fallback"
    return "\(md5Hash).\(Self.thumbnailExtension)"
  }

  // Store a pre-generated thumbnail in cache (used by ImportView for device thumbnails)
  func storePreGeneratedThumbnail(_ nsImage: NSImage, mediaItem: MediaItem) {
    let date = mediaItem.thumbnailDate
    let basename = mediaItem.displayName
    let filename = filenameForThumbnail(date: date, basename: basename)
    let key = filename as NSString

    cache.setObject(nsImage, forKey: key)
    saveToDisk(image: nsImage, key: filename)

    // Notify observers that thumbnail became available
    NotificationCenter.default.post(
      name: .thumbnailDidBecomeAvailable,
      object: nil,
      userInfo: [
        "date": date,
        "basename": basename,
        "mediaItemId": mediaItem.id,
      ]
    )
  }

  private func generateThumbnail(for url: URL) async -> NSImage? {
    var cgImage: CGImage?
    if url.isVideo() {
      // For videos, use AVAssetImageGenerator
      let asset = AVURLAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.maximumSize = ThumbnailCache.thumbnailSize
      generator.appliesPreferredTrackTransform = true
      do {
        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: min(0.5, CMTimeGetSeconds(duration) / 2), preferredTimescale: 30)
        cgImage = try await withCheckedThrowingContinuation { continuation in
          generator.generateCGImageAsynchronously(for: time) { cg, actualTime, error in
            if let error = error {
              continuation.resume(throwing: error)
            } else if let cg = cg {
              continuation.resume(returning: cg)
            } else {
              continuation.resume(throwing: NSError(domain: "Thumbnail", code: 0, userInfo: nil))
            }
          }
        }
      } catch {
        // ignore
      }
    } else {
      if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let img = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(
              ThumbnailCache.thumbnailSize.width, ThumbnailCache.thumbnailSize.height),
          ] as CFDictionary)
      {
        cgImage = img
      }
    }

    if var cgImage = cgImage {
      // Crop to square if not square (with safety checks)
      let width = cgImage.width
      let height = cgImage.height
      let minDim = min(width, height)
      if width != height && width > 0 && height > 0 {
        let x = (width - minDim) / 2
        let y = (height - minDim) / 2
        let rect = CGRect(x: x, y: y, width: minDim, height: minDim)
        if let cropped = cgImage.cropping(to: rect) {
          cgImage = cropped
        }
      }
      return NSImage(cgImage: cgImage, size: ThumbnailCache.thumbnailSize)
    }
    return nil
  }

  func cleanupDanglingThumbnails() -> Int {
    let fileManager = FileManager.default
    var deletedCount = 0
    guard let files = try? fileManager.contentsOfDirectory(atPath: cacheDir) else { return 0 }
    for file in files where file.hasSuffix(".\(Self.thumbnailExtension)") {
      let key = String(file.dropLast(Self.thumbnailExtension.count + 1))  // remove .extension
      if let lastUnderscore = key.lastIndex(of: "_") {
        let urlString = String(key[..<lastUnderscore])
        if let url = URL(string: urlString), !fileManager.fileExists(atPath: url.path) {
          do {
            try fileManager.removeItem(atPath: cacheDir + "/" + file)
            deletedCount += 1
          } catch {
            // ignore
          }
        }
      }
    }
    return deletedCount
  }

  private func loadFromDisk(key: String) -> NSImage? {
    let filePath = cacheDir + "/" + key
    return NSImage(contentsOfFile: filePath)
  }

  private func saveToDisk(image: NSImage, key: String) {
    let filePath = cacheDir + "/" + key
    if let tiffData = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData) {
      let jpgData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
      try? jpgData?.write(to: URL(fileURLWithPath: filePath))
    }
  }
}
