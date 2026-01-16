import Foundation

extension MediaItem {
  /// Determines if this media item matches the given search query
  /// Searches across filename, file extension, camera make, and camera model
  func matchesSearchQuery(_ query: String) -> Bool {
    // Search in filename
    if displayName.localizedCaseInsensitiveContains(query) {
      return true
    }

    // Search in file extension (without dot)
    let fileExtension = (displayName as NSString).pathExtension.lowercased()
    if fileExtension.localizedCaseInsensitiveContains(query) {
      return true
    }

    // Search in camera make
    if let make = metadata?.make,
      make.localizedCaseInsensitiveContains(query)
    {
      return true
    }

    // Search in camera model
    if let model = metadata?.model,
      model.localizedCaseInsensitiveContains(query)
    {
      return true
    }

    return false
  }
}
