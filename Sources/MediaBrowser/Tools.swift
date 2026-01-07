import ImageCaptureCore

// MARK: - extract base name
extension String {
  // Extract base name from filename (remove extension and edit markers)
  func extractBaseName(forApplePhotos: Bool = false) -> String {
    if forApplePhotos {
      return extractApplePhotosBaseName()
    }

    var baseName = self

    // Remove edit markers first (before extensions)
    // Remove edit markers (e.g., "IMG_1234" from "IMG_1234 (Edited)")
    if let editMarkerRange = baseName.range(of: " \\(Edited\\)", options: .regularExpression) {
      baseName = String(baseName[..<editMarkerRange.lowerBound])
    }

    // Remove iOS edit markers (E in the middle)
    if let firstDigitIndex = baseName.firstIndex(where: { $0.isNumber }) {
      let beforeDigits = baseName[..<firstDigitIndex]
      if beforeDigits.hasSuffix("E") {
        // Remove the E without adding separator
        let prefix = String(beforeDigits.dropLast())
        let digits = String(baseName[firstDigitIndex...])
        baseName = prefix + digits
      }
    }

    // Then remove common extensions (remove all extensions)
    return (baseName as NSString).deletingPathExtension
  }

  func extractApplePhotosBaseName() -> String {
    let fileName = self

    // Remove file extension
    let nameWithoutExt = (fileName as NSString).deletingPathExtension

    // Find and remove suffix
    let cameraSequencePattern = try? NSRegularExpression(pattern: "_[0-9]{1,2}$")
    let range = cameraSequencePattern?.rangeOfFirstMatch(
      in: nameWithoutExt,
      options: [],
      range: NSRange(location: 0, length: nameWithoutExt.count)
    )
    if let range = range {
      // Remove the matching part
      let prefixLength = range.location
      return String(nameWithoutExt.prefix(prefixLength))
    }

    return nameWithoutExt
  }
}

extension URL {
  // Extract base name from the last path component
  func extractBaseName() -> String {
    return self.lastPathComponent.extractBaseName()
  }
}

private struct MediaExtensions {
  static let image: Set<String> = [
    // Standard image formats
    "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "heic", "heif", "webp", "svg", "icns", "psd",
    "ico",

    // Raw image formats from various camera manufacturers
    "cr2", "crw", "nef", "nrw", "arw", "srf", "rw2", "rwl", "raf", "orf", "ori", "pef", "dng",
    "rwl", "3fr", "fff", "iiq", "mos", "dcr", "kdc", "x3f", "erf", "mef", "dng", "mrw", "orf",
    "rw2", "srw", "dng",
  ]

  static let video: Set<String> = [
    // Standard video formats
    "mp4", "avi", "mov", "m4v", "mpg", "mpeg", "3gp", "3g2", "dv", "flc", "m2ts", "mts", "m4v",
    "mkv", "webm", "wmv", "asf", "rm", "divx", "xvid", "ogv", "vob",
  ]
}

extension URL {
  func isImage() -> Bool {
    return MediaExtensions.image.contains(pathExtension.lowercased())
  }

  func isVideo() -> Bool {
    return MediaExtensions.video.contains(pathExtension.lowercased())
  }

  func isMedia() -> Bool {
    return isImage() || isVideo()
  }
}

extension String {
  func isImage() -> Bool {
    guard let ext = self.components(separatedBy: ".").last?.lowercased() else { return false }
    return MediaExtensions.image.contains(ext)
  }

  func isVideo() -> Bool {
    guard let ext = self.components(separatedBy: ".").last?.lowercased() else { return false }
    return MediaExtensions.video.contains(ext)
  }

  func isMedia() -> Bool {
    return isImage() || isVideo()
  }
}

// MARK: - Camera Item Hash
extension ICCameraItem {
  public static func == (lhs: ICCameraItem, rhs: ICCameraItem) -> Bool {
    // Compare stable properties
    lhs.name == rhs.name && lhs.uti == rhs.uti && lhs.creationDate == rhs.creationDate
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(name)
    hasher.combine(uti)
    hasher.combine(creationDate)
    return hasher.finalize()
  }

}

extension ICCameraItem {
  private static let imageUTIs: Set<String> = [
    // Standard image formats
    "public.image",
    "public.jpeg",
    "public.png",
    "public.tiff",
    "public.gif",
    "public.bmp",
    "public.heic",
    "public.heif",
    "public.webp",
    "public.svg-image",
    "com.apple.icns",
    "com.adobe.photoshop-image",
    "com.microsoft.bmp",
    "com.microsoft.ico",

    // Raw image formats from various camera manufacturers
    "com.canon.cr2",
    "com.canon.crw",
    "com.nikon.nef",
    "com.nikon.nrw",
    "com.sony.arw",
    "com.sony.srf",
    "com.panasonic.rw2",
    "com.panasonic.rwl",
    "com.fuji.raw",
    "com.fuji.raf",
    "com.olympus.orf",
    "com.olympus.ori",
    "com.pentax.raw",
    "com.pentax.pef",
    "com.leica.raw",
    "com.leica.rwl",
    "com.hasselblad.3fr",
    "com.hasselblad.fff",
    "com.phaseone.iiq",
    "com.leaf.mos",
    "com.kodak.dcr",
    "com.kodak.kdc",
    "com.sigma.raw",
    "com.sigma.x3f",
    "com.epson.raw",
    "com.epson.erf",
    "com.mamiya.raw",
    "com.mamiya.mef",
    "com.ricoh.raw",
    "com.ricoh.dng",
    "com.konica.raw",
    "com.konica.mrw",
    "com.minolta.raw",
    "com.minolta.mrw",
    "com.casiodata.raw",
    "com.agfa.raw",
    "com.samsung.raw",
    "com.samsung.srw",
    "com.nokia.raw",
    "com.nokia.nrw",
  ]

  private static let videoUTIs: Set<String> = [
    // Standard video formats
    "public.video",
    "public.movie",
    "public.mpeg-4",
    "public.avi",
    "com.apple.quicktime-movie",
    "public.mp4",
    "public.mpeg",
    "public.3gpp",
    "public.3gpp2",
    "public.dv",
    "public.flc",
    "public.m2ts",
    "public.mts",
    "public.m4v",
    "public.mkv",
    "org.webmproject.webm",
    "com.microsoft.wmv",
    "com.microsoft.asf",
    "com.real.realmedia",
    "com.divx.divx",
    "com.xvid.xvid",
    "public.ogv",
    "public.vob",

    // Additional formats from devices
    "com.apple.itunes.m4v",
    "com.google.webm",
    "com.microsoft.mpeg",
    "com.sony.mpeg",
    "com.panasonic.mpeg",
    "com.canon.mpeg",
    "com.nikon.mpeg",
    "com.olympus.mpeg",
  ]

  func isImage() -> Bool {
    return uti.map { Self.imageUTIs.contains($0) } ?? false
  }

  func isVideo() -> Bool {
    return uti.map { Self.videoUTIs.contains($0) } ?? false
  }

  func isMedia() -> Bool {
    return isImage() || isVideo()
  }
}

enum ArraySortOrder {
  case ascending
  case descending
}

extension Array {
  mutating func insertSorted<T: Comparable>(
    _ newElement: Element,
    by keyPath: KeyPath<Element, T>,
    order: ArraySortOrder = .ascending
  ) {
    var left = 0
    var right = self.count

    while left < right {
      let mid = (left + right) / 2
      let midValue = self[mid][keyPath: keyPath]
      let newValue = newElement[keyPath: keyPath]

      // Direction-aware comparison
      let comparison: Bool
      switch order {
      case .ascending:
        comparison = midValue >= newValue
      case .descending:
        comparison = midValue <= newValue
      }

      if comparison {
        right = mid
      } else {
        left = mid + 1
      }
    }

    self.insert(newElement, at: left)
  }
}
