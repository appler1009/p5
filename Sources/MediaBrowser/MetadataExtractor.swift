import AVFoundation
import CoreLocation  // for GPS if needed, but not
import Foundation
import ImageIO

extension MediaScanner {
  func extractMetadata(for item: inout MediaItem) async {
    let url = item.url
    var metadata = MediaMetadata(
      filePath: url.path,
      filename: url.lastPathComponent,
      creationDate: nil,
      modificationDate: nil,
      dimensions: nil,
      exifDate: nil,
      gps: nil,
      duration: nil
    )

    // File attributes
    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
      metadata.creationDate = attributes[.creationDate] as? Date
      metadata.modificationDate = attributes[.modificationDate] as? Date
    }

    switch item.type {
    case .photo, .livePhoto:
      if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
          // Dimensions
          if let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double
          {
            metadata.dimensions = CGSize(width: width, height: height)
          }

          // EXIF
          if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
              let formatter = DateFormatter()
              formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
              metadata.exifDate = formatter.date(from: dateString)
            }
            metadata.iso = exif[kCGImagePropertyExifISOSpeedRatings] as? Int
            if let apertureValue = exif[kCGImagePropertyExifApertureValue] as? Double {
              metadata.aperture = pow(2, apertureValue / 2)
            }
            if let shutterValue = exif[kCGImagePropertyExifShutterSpeedValue] as? Double {
              let shutter = 1 / pow(2, shutterValue)
              metadata.shutterSpeed = String(format: "1/%.0f", 1 / shutter)
            }
          }

          // TIFF for Make, Model, Lens
          if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            metadata.make = tiff[kCGImagePropertyTIFFMake] as? String
            metadata.model = tiff[kCGImagePropertyTIFFModel] as? String
            // Lens not standard in TIFF
          }

          // GPS
          if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
            let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
          {
            let latitude = latRef == "N" ? lat : -lat
            let longitude = lonRef == "E" ? lon : -lon
            let altitude = gps[kCGImagePropertyGPSAltitude] as? Double
            metadata.gps = GPSLocation(latitude: latitude, longitude: longitude, altitude: altitude)
          }
        }
      }
    case .video:
      let asset = AVAsset(url: url)
      do {
        let duration = try await asset.load(.duration)
        metadata.duration = CMTimeGetSeconds(duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        if let track = tracks.first {
          metadata.dimensions = try await track.load(.naturalSize)
        }
      } catch {
        print("Error loading video metadata: \(error)")
      }
    // For EXIF in videos, might need more work, but skip for now
    }

    item.metadata = metadata
  }
}
