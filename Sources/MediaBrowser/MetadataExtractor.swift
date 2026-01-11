import AVFoundation
import CoreLocation
import Foundation
import ImageIO
import tzf

struct MetadataExtractor {
  private static let timezoneFinder: tzf.DefaultFinder? = try? tzf.DefaultFinder()

  static func extractMetadata(for url: URL) async -> MediaMetadata {
    var metadata = MediaMetadata(
      creationDate: nil,
      modificationDate: nil,
      dimensions: nil,
      exifDate: nil,
      gps: nil,
      duration: nil
    )

    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
      metadata.creationDate = attributes[.creationDate] as? Date
      metadata.modificationDate = attributes[.modificationDate] as? Date
    }

    if url.isImage() {
      if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
          if let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double
          {
            metadata.dimensions = CGSize(width: width, height: height)
          }

          var gpsLocation: GPSLocation?

          if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
            let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
          {
            let latitude = latRef == "N" ? lat : -lat
            let longitude = lonRef == "E" ? lon : -lon
            let altitude = gps[kCGImagePropertyGPSAltitude] as? Double
            gpsLocation = GPSLocation(latitude: latitude, longitude: longitude, altitude: altitude)
            metadata.gps = gpsLocation
          }

          if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
              let formatter = DateFormatter()
              formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

              var dateToUse: Date?

              if let offsetTime = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String ?? exif[
                kCGImagePropertyExifOffsetTimeDigitized] as? String
              {
                let tzFormatter = DateFormatter()
                tzFormatter.dateFormat = "yyyy:MM:dd HH:mm:ssZ"
                dateToUse = tzFormatter.date(from: dateString + offsetTime)
              } else if let gps = gpsLocation {
                if let finder = Self.timezoneFinder,
                  let tzString = try? finder.getTimezone(lng: gps.longitude, lat: gps.latitude),
                  let timezone = TimeZone(identifier: tzString)
                {
                  let tzFormatter = DateFormatter()
                  tzFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                  tzFormatter.timeZone = timezone
                  dateToUse = tzFormatter.date(from: dateString)
                }
              }

              if let date = dateToUse ?? formatter.date(from: dateString) {
                metadata.exifDate = date
              }
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

          if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            metadata.make = tiff[kCGImagePropertyTIFFMake] as? String
            metadata.model = tiff[kCGImagePropertyTIFFModel] as? String
          }
        }
      }
    }

    if url.isVideo() {
      let asset = AVAsset(url: url)

      metadata.duration = CMTimeGetSeconds(asset.duration)

      if let creationDate = asset.creationDate?.dateValue {
        metadata.creationDate = creationDate
        metadata.exifDate = creationDate
      }

      do {
        let metadataItems = try await asset.load(.commonMetadata)

        for item in metadataItems {
          guard let key = item.identifier,
                let stringValue = try? await item.load(.stringValue) else { continue }

          let keyString = key.rawValue

          if keyString.localizedCaseInsensitiveContains("creationdate") {
            if metadata.creationDate == nil {
              let formatter = DateFormatter()
              formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
              metadata.creationDate = formatter.date(from: stringValue)
              metadata.exifDate = metadata.creationDate
            }
            continue
          }

          if keyString.localizedCaseInsensitiveContains("gps") || keyString.localizedCaseInsensitiveContains("location") {
            var cleaned = stringValue
            if cleaned.hasSuffix("/") {
              cleaned.removeLast()
            }

            var latitude = 0.0
            var longitude = 0.0
            var altitude: Double? = nil

            var currentNumber = ""
            var sign = 1.0
            var values: [Double] = []

            for char in cleaned {
              if char == "+" {
                if !currentNumber.isEmpty, let val = Double(currentNumber) {
                  values.append(val * sign)
                }
                sign = 1.0
                currentNumber = ""
              } else if char == "-" {
                if !currentNumber.isEmpty, let val = Double(currentNumber) {
                  values.append(val * sign)
                }
                sign = -1.0
                currentNumber = ""
              } else if char.isNumber || char == "." {
                currentNumber.append(char)
              }
            }

            if !currentNumber.isEmpty, let val = Double(currentNumber) {
              values.append(val * sign)
            }

            if values.count >= 2 {
              latitude = values[0]
              longitude = values[1]
              if values.count >= 3 {
                altitude = values[2]
              }
              metadata.gps = GPSLocation(latitude: latitude, longitude: longitude, altitude: altitude)
            }
            continue
          }

          if keyString.localizedCaseInsensitiveContains("make") {
            metadata.make = stringValue
            continue
          }

          if keyString.localizedCaseInsensitiveContains("model") {
            metadata.model = stringValue
            continue
          }

          if keyString.localizedCaseInsensitiveContains("iso") {
            if let isoValue = Int(stringValue) {
              metadata.iso = isoValue
            }
            continue
          }
        }
      } catch {
        print("Error loading video metadata: \(error)")
      }
    }

    return metadata
  }
}
