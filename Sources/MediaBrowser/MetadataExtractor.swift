import AVFoundation
import CoreLocation
import Foundation
import ImageIO
import tzf

struct MetadataExtractor {
  @MainActor private static let timezoneFinder: tzf.DefaultFinder? = try? tzf.DefaultFinder()

  private static let appleTagMappings: [String: String] = [
    "0": "MakerNoteVersion",
    "1": "AEMatrix",
    "2": "RunTime",
    "3": "AEStable",
    "4": "AETarget",
    "5": "AEAverage",
    "6": "AFStable",
    "7": "AFPerformance",
    "8": "AccelerationVector",
    "9": "HDRImageType",
    "10": "BurstUUID",
    "11": "ContentIdentifier",
    "12": "ImageCaptureType",
    "13": "RunTime",
    "14": "QualityHint",
    "15": "AETarget",
    "16": "AETarget",
    "17": "LuminanceNoiseAmplitude",
    "18": "PhotosAppFeatureFlags",
    "19": "ImageCaptureRequestID",
    "20": "Q",
    "21": "HDRHeadroom",
    "22": "FocusDistanceRange",
    "23": "OISMode",
    "24": "ImageUniqueID",
    "25": "ColorTemperature",
    "26": "CameraType",
    "27": "FocusPosition",
    "28": "HDRGain",
    "29": "AFMeasuredDepth",
    "30": "AFConfidence",
    "31": "ColorCorrectionMatrix",
    "32": "GreenGhostMitigationStatus",
    "33": "SemanticStyle",
    "34": "SemanticStyleRenderingVer",
    "35": "SceneFlags",
    "36": "SignalToNoiseRatioType",
    "39": "SignalToNoiseRatio",
  ]

  private static func sanitizeEXIFValue(_ value: Any) -> String {
    if let stringValue = value as? String {
      return stringValue.trimmingCharacters(in: .whitespaces)
    } else if let doubleValue = value as? Double {
      if doubleValue.isInfinite {
        return "-1.0"
      }
      return "\(doubleValue)"
    } else if let dataValue = value as? Data {
      return dataValue.base64EncodedString()
    } else if let arrayValue = value as? [Any] {
      return "\(arrayValue.map { sanitizeEXIFValue($0) })"
    } else if let dictValue = value as? [String: Any] {
      return "\(dictValue.mapValues { sanitizeEXIFValue($0) })"
    }
    return "\(value)"
  }

  @MainActor static func extractMetadata(for url: URL) async -> MediaMetadata {
    var metadata = MediaMetadata(
      creationDate: nil,
      modificationDate: nil,
      dimensions: nil,
      exifDate: nil,
      gps: nil,
      duration: nil,
      make: nil,
      model: nil,
      lens: nil,
      iso: nil,
      aperture: nil,
      shutterSpeed: nil,
      extraEXIF: [:]
    )

    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
      metadata.creationDate = attributes[.creationDate] as? Date
      metadata.modificationDate = attributes[.modificationDate] as? Date
    }

    if url.isImage() {
      if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
          var extraEXIF: [String: String] = [:]

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

            for (key, value) in gps {
              extraEXIF["gps_\(key)"] = "\(value)"
            }
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

            let knownEXIFKeys: Set<CFString> = [
              kCGImagePropertyExifDateTimeOriginal,
              kCGImagePropertyExifDateTimeDigitized,
              kCGImagePropertyExifOffsetTimeOriginal,
              kCGImagePropertyExifOffsetTimeDigitized,
              kCGImagePropertyExifISOSpeedRatings,
              kCGImagePropertyExifApertureValue,
              kCGImagePropertyExifShutterSpeedValue,
            ]

            for (key, value) in exif {
              if !knownEXIFKeys.contains(key) {
                extraEXIF["exif_\(key)"] = sanitizeEXIFValue(value)
              }
            }
          }

          if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            metadata.make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(
              in: .whitespaces)
            metadata.model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(
              in: .whitespaces)

            let knownTIFFKeys: Set<CFString> = [
              kCGImagePropertyTIFFMake,
              kCGImagePropertyTIFFModel,
            ]

            for (key, value) in tiff {
              if !knownTIFFKeys.contains(key) {
                extraEXIF["tiff_\(key)"] = sanitizeEXIFValue(value)
              }
            }
          }

          let imageIOKeysToSkip: Set<CFString> = [
            kCGImagePropertyPixelWidth,
            kCGImagePropertyPixelHeight,
            kCGImagePropertyOrientation,
            kCGImagePropertyColorModel,
            kCGImagePropertyDepth,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyExifDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyTIFFDictionary,
          ]

          for (key, value) in properties {
            if !imageIOKeysToSkip.contains(key) {
              if key as String == "{MakerApple}" {
                if let dataValue = value as? Data {
                  do {
                    var format = PropertyListSerialization.PropertyListFormat.binary
                    let plist = try PropertyListSerialization.propertyList(
                      from: dataValue,
                      options: [],
                      format: &format
                    )
                    if let appleDict = plist as? [String: Any] {
                      for (appleKey, appleValue) in appleDict {
                        let tagName = Self.appleTagMappings[appleKey] ?? appleKey
                        extraEXIF["apple_\(tagName)"] = sanitizeEXIFValue(appleValue)
                      }
                    }
                  } catch {
                    extraEXIF["{MakerApple}"] = "bplist_parse_error"
                  }
                } else {
                  extraEXIF["{MakerApple}"] = sanitizeEXIFValue(value)
                }
              } else {
                extraEXIF["image_\(key)"] = sanitizeEXIFValue(value)
              }
            }
          }

          metadata.extraEXIF = extraEXIF
        }
      }
    }

    if url.isVideo() {
      let asset = AVURLAsset(url: url)
      do {
        let duration = try await asset.load(.duration)
        metadata.duration = CMTimeGetSeconds(duration)

        let metadataItems = try await asset.load(.commonMetadata)

        var extraEXIF: [String: String] = [:]

        for item in metadataItems {
          guard let key = item.identifier,
            let stringValue = try? await item.load(.stringValue)
          else { continue }

          let keyString = key.rawValue

          if keyString.localizedCaseInsensitiveContains("creationdate") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            metadata.creationDate = formatter.date(from: stringValue)
            metadata.exifDate = formatter.date(from: stringValue)
            continue
          }

          if keyString.localizedCaseInsensitiveContains("gps")
            || keyString.localizedCaseInsensitiveContains("location")
          {
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
              metadata.gps = GPSLocation(
                latitude: latitude, longitude: longitude, altitude: altitude)
            }
            continue
          }

          if keyString.localizedCaseInsensitiveContains("make") {
            metadata.make = stringValue.trimmingCharacters(in: .whitespaces)
            continue
          }

          if keyString.localizedCaseInsensitiveContains("model") {
            metadata.model = stringValue.trimmingCharacters(in: .whitespaces)
            continue
          }

          if keyString.localizedCaseInsensitiveContains("iso") {
            if let isoValue = Int(stringValue) {
              metadata.iso = isoValue
            }
            continue
          }

          extraEXIF["video_\(keyString)"] = stringValue.trimmingCharacters(in: .whitespaces)
        }

        metadata.extraEXIF = extraEXIF
      } catch {
        print("Error loading video metadata: \(error)")
      }
    }

    return metadata
  }

  /// Extracts EXIF metadata properties from an image URL
  static func extractEXIFProperties(from url: URL) -> [CFString: Any]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
  }
}
