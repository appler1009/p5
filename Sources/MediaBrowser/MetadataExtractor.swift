import Foundation
import ImageIO
import AVFoundation
import CoreLocation // for GPS if needed, but not

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
                       let height = properties[kCGImagePropertyPixelHeight] as? Double {
                        metadata.dimensions = CGSize(width: width, height: height)
                    }

                    // EXIF
                    if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
                       let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                        metadata.exifDate = formatter.date(from: dateString)
                    }

                    // GPS
                    if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
                       let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
                       let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
                       let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
                       let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
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