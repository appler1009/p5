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
    }

    return metadata
  }

  static func extractImageMetadataSync(for url: URL) -> (date: Date?, gps: GPSLocation?) {
    var gpsLocation: GPSLocation?
    var exifDate: Date?

    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    {
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
      }

      if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
        let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
      {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

        if let offsetTime = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String ?? exif[
          kCGImagePropertyExifOffsetTimeDigitized] as? String
        {
          let tzFormatter = DateFormatter()
          tzFormatter.dateFormat = "yyyy:MM:dd HH:mm:ssZ"
          exifDate = tzFormatter.date(from: dateString + offsetTime)
        } else if let gps = gpsLocation {
          if let finder = Self.timezoneFinder,
            let tzString = try? finder.getTimezone(lng: gps.longitude, lat: gps.latitude),
            let timezone = TimeZone(identifier: tzString)
          {
            let tzFormatter = DateFormatter()
            tzFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            tzFormatter.timeZone = timezone
            exifDate = tzFormatter.date(from: dateString)
          }
        }

        if exifDate == nil {
          exifDate = formatter.date(from: dateString)
        }
      }
    }

    return (exifDate, gpsLocation)
  }
}
