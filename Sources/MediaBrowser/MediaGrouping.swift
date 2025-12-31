import Foundation
import ImageCaptureCore
import ImageIO
import UniformTypeIdentifiers

// MARK: - Media Grouping

/// Represents a media source with metadata for grouping
struct MediaSource: Hashable, Comparable {
  let year: Int
  let month: Int
  let day: Int
  let baseName: String
  let fullName: String
  let uti: String

  init(date: Date, name: String, uti: String) {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    self.year = components.year!
    self.month = components.month!
    self.day = components.day!
    self.fullName = name
    self.baseName = name.extractBaseName()
    self.uti = uti
  }

  init(cameraItem: ICCameraItem) {
    self.init(
      date: cameraItem.creationDate!,
      name: cameraItem.name!,
      uti: cameraItem.uti!
    )
  }

  init(url: URL) {
    let fileName = url.lastPathComponent
    let pathExtension = url.pathExtension
    let uti = UTType(filenameExtension: pathExtension)?.identifier ?? ""

    // Try to extract date from EXIF data first, then fall back to file metadata
    var fileDate: Date?
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    {

      // EXIF date
      if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
        let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
      {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fileDate = formatter.date(from: dateString)
      }
    }

    // Fall back to file system dates
    let finalDate =
      fileDate
      ?? {
        let resourceValues = try? url.resourceValues(forKeys: [
          .creationDateKey, .contentModificationDateKey,
        ])
        return resourceValues?.creationDate ?? resourceValues?.contentModificationDate ?? Date()
      }()

    self.init(date: finalDate, name: fileName, uti: uti)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(year)
    hasher.combine(month)
    hasher.combine(day)
    hasher.combine(baseName)
  }

  func isImage() -> Bool {
    return fullName.isImage()
  }

  func isVideo() -> Bool {
    return fullName.isVideo()
  }

  func isMedia() -> Bool {
    return fullName.isMedia()
  }

  func lookupKey() -> String {
    return "\(year)_\(month)_\(day)_\(baseName)_\(uti)"
  }

  static func == (lhs: MediaSource, rhs: MediaSource) -> Bool {
    lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
      && lhs.baseName == rhs.baseName
  }

  static func < (lhs: MediaSource, rhs: MediaSource) -> Bool {
    // Date first
    if lhs.year != rhs.year { return lhs.year < rhs.year }
    if lhs.month != rhs.month { return lhs.month < rhs.month }
    if lhs.day != rhs.day { return lhs.day < rhs.day }

    // Basename: length first, then alphabetical
    if lhs.fullName.count != rhs.fullName.count {
      return lhs.fullName.count < rhs.fullName.count  // Longer > shorter
    }
    return lhs.fullName < rhs.fullName  // Same length, alphabetical
  }
}

/// Represents a grouped media entry with main, edited, and live components
struct MediaGroupEntry: Comparable {
  let main: MediaSource
  let edited: MediaSource?
  let live: MediaSource?

  // Custom sorting: main → edited → live priority
  static func < (lhs: MediaGroupEntry, rhs: MediaGroupEntry) -> Bool {
    // 1. Compare main (highest priority)
    if lhs.main != rhs.main {
      return lhs.main < rhs.main
    }

    // 2. Compare edited (exists > nil)
    switch (lhs.edited, rhs.edited) {
    case (nil, nil):
      break  // Both nil, continue
    case (nil, _):
      return true  // lhs nil, rhs exists → lhs smaller
    case (_, nil):
      return false  // lhs exists, rhs nil → lhs bigger
    case (let lhsEdited?, let rhsEdited?):
      if lhsEdited != rhsEdited {
        return lhsEdited < rhsEdited
      }
    }

    // 3. Compare live (exists > nil)
    switch (lhs.live, rhs.live) {
    case (nil, nil):
      return false  // Equal
    case (nil, _):
      return true  // lhs nil, rhs exists → lhs smaller
    case (_, nil):
      return false  // lhs exists, rhs nil → lhs bigger
    case (let lhsLive?, let rhsLive?):
      return lhsLive < rhsLive
    }
  }
}

// MARK: - Grouping Functions

/// Groups related camera items (Live Photos, edited photos, etc.) into ConnectedDeviceMediaItem objects
func groupRelatedCameraItems(_ items: [ICCameraItem]) -> [ConnectedDeviceMediaItem] {
  let itemLookup: [String: ICCameraItem] = items.reduce(into: [String: ICCameraItem]()) {
    dict, item in
    dict[MediaSource(cameraItem: item).lookupKey()] = item  // overwrites duplicates, but there should be no duplicates with lookupKey()
  }

  let sources = items.map(MediaSource.init(cameraItem:))

  let mediaGroups = groupRelatedMedia(sources)
  return mediaGroups.compactMap { group in
    if let original = itemLookup[group.main.lookupKey()] {
      return ConnectedDeviceMediaItem(
        id: -1,  // Will be replaced with a unique sequence number
        original: original,
        edited: group.edited != nil ? itemLookup[group.edited!.lookupKey()] : nil,
        live: group.live != nil ? itemLookup[group.live!.lookupKey()] : nil
      )
    } else {
      return nil
    }
  }
}

/// Groups related URLs by creating MediaSource objects and grouping them
func groupRelatedURLs(_ urls: [URL]) -> [LocalFileSystemMediaItem] {
  let itemLookup: [String: URL] = urls.reduce(into: [String: URL]()) {
    dict, item in
    dict[MediaSource(url: item).lookupKey()] = item
  }

  let sources = urls.map(MediaSource.init(url:))

  let mediaGroups = groupRelatedMedia(sources)
  return mediaGroups.compactMap { group in
    if let original = itemLookup[group.main.lookupKey()] {
      return LocalFileSystemMediaItem(
        id: -1,
        original: original,
        edited: group.edited != nil ? itemLookup[group.edited!.lookupKey()] : nil,
        live: group.live != nil ? itemLookup[group.live!.lookupKey()] : nil
      )
    } else {
      return nil
    }
  }
}

/// Groups related media sources by base name and date, handling edited versions and Live Photos
func groupRelatedMedia(_ items: [MediaSource]) -> [MediaGroupEntry] {
  var groups: [MediaSource: MediaGroupEntry] = [:]

  // 1st pass - take list of photos while grouping edited photos
  let photoSources = items.filter { $0.isImage() }
  for photoSource in photoSources {
    if let group = groups[photoSource] {
      if group.main > photoSource {
        // longer name must be the edited name
        groups[photoSource] = .init(main: photoSource, edited: group.main, live: nil)
      } else {
        groups[photoSource] = .init(main: group.main, edited: photoSource, live: nil)
      }
    } else {
      groups[photoSource] = .init(main: photoSource, edited: nil, live: nil)
    }
  }

  // 2nd pass - find videos of live photos from 1st pass
  let videoSources = items.filter { $0.isVideo() }
  for videoSource in videoSources {
    if let group = groups[videoSource] {
      groups[videoSource] = .init(main: group.main, edited: group.edited, live: videoSource)
    }
  }

  // 3rd pass - add rest of videos as separate videos
  for videoSource in videoSources {
    if let group = groups[videoSource] {
      if group.live == videoSource {
        // it's other video's live video; skip
        continue
      }
      if group.main > videoSource {
        // longer name must be the edited version
        groups[videoSource] = .init(main: videoSource, edited: group.main, live: nil)
      } else {
        groups[videoSource] = .init(main: group.main, edited: videoSource, live: nil)
      }
    } else {
      groups[videoSource] = .init(main: videoSource, edited: nil, live: nil)
    }
  }

  // not necessarily needed to be sorted, but just making it deterministic and predictable
  return Array(groups.values).sorted { $0 < $1 }
}
