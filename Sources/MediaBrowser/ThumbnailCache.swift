import AVFoundation
import Combine
import SwiftUI

class ThumbnailCache {
  static let shared = ThumbnailCache()
  private var cache = NSCache<NSString, NSImage>()
  private let cacheDir: String

  private init() {
    let cacheDirURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("MediaBrowser/thumbnails")
    cacheDir = cacheDirURL.path
    try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
  }

  func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
    let key = "\(url.absoluteString)_\(size.width)x\(size.height)" as NSString
    if let image = cache.object(forKey: key) {
      return image
    }
    if let image = loadFromDisk(key: key as String) {
      cache.setObject(image, forKey: key)
      return image
    }
    let image = await generateThumbnail(for: url, size: size)
    if let image = image {
      cache.setObject(image, forKey: key)
      saveToDisk(image: image, key: key as String)
    }
    return image
  }

  private func generateThumbnail(for url: URL, size: CGSize) async -> NSImage? {
    var cgImage: CGImage?
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let img = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
        ] as CFDictionary)
    {
      cgImage = img
    } else {
      // For videos, use AVAssetImageGenerator
      let asset = AVAsset(url: url)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.maximumSize = size
      generator.appliesPreferredTrackTransform = true
      do {
        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: min(0.5, CMTimeGetSeconds(duration) / 2), preferredTimescale: 30)
        cgImage = try? generator.copyCGImage(at: time, actualTime: nil)
      } catch {
        // ignore
      }
    }

    if var cgImage = cgImage {
      // Crop to square if not square
      let width = cgImage.width
      let height = cgImage.height
      let minDim = min(width, height)
      if width != height {
        let x = (width - minDim) / 2
        let y = (height - minDim) / 2
        let rect = CGRect(x: x, y: y, width: minDim, height: minDim)
        if let cropped = cgImage.cropping(to: rect) {
          cgImage = cropped
        }
      }
      return NSImage(cgImage: cgImage, size: size)
    }
    return nil
  }

  private func loadFromDisk(key: String) -> NSImage? {
    let filePath = cacheDir + "/" + key + ".png"
    return NSImage(contentsOfFile: filePath)
  }

  private func saveToDisk(image: NSImage, key: String) {
    let filePath = cacheDir + "/" + key + ".png"
    if let tiffData = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData) {
      let pngData = bitmap.representation(using: .png, properties: [:])
      try? pngData?.write(to: URL(fileURLWithPath: filePath))
    }
  }
}
