import AppKit
import Foundation

@MainActor
class DirectoryManager: ObservableObject {
  @MainActor static let shared = DirectoryManager()
  @Published var directories: [URL] = []

  // Import directory configuration
  @Published var customImportDirectory: URL? {
    didSet {
      saveCustomImportDirectory()
    }
  }

  private let bookmarkKey = "selectedDirectories"
  private let importDirectoryKey = "customImportDirectory"
  private var accessedURLs: Set<URL> = []
  private var bookmarksFile: String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return home + "/Library/MediaBrowser/directories.json"
  }

  private init() {
    loadBookmarks()
    loadCustomImportDirectory()
  }

  func addDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      directories.append(url)
      if url.startAccessingSecurityScopedResource() {
        accessedURLs.insert(url)
      }
      saveBookmarks()
    }
  }

  func removeDirectory(at index: Int) {
    let url = directories[index]
    url.stopAccessingSecurityScopedResource()
    accessedURLs.remove(url)
    directories.remove(at: index)
    saveBookmarks()
  }

  private func saveBookmarks() {
    let dirs = directories.compactMap { url -> [String: String]? in
      do {
        let bookmarkData = try url.bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let bookmarkBase64 = bookmarkData.base64EncodedString()
        return ["path": url.path, "bookmark": bookmarkBase64]
      } catch {
        print("Error creating bookmark for \(url.path): \(error)")
        return nil
      }
    }
    do {
      try FileManager.default.createDirectory(
        atPath: (bookmarksFile as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
      let data = try JSONSerialization.data(withJSONObject: dirs, options: [])
      try data.write(to: URL(fileURLWithPath: bookmarksFile))
    } catch {
      print("Error saving bookmarks: \(error)")
    }
  }

  private func loadBookmarks() {
    if let data = try? Data(contentsOf: URL(fileURLWithPath: bookmarksFile)),
      let dirs = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
    {
      for dir in dirs {
        if let bookmarkBase64 = dir["bookmark"],
          let bookmarkData = Data(base64Encoded: bookmarkBase64)
        {
          var isStale = false
          if let url = try? URL(
            resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil,
            bookmarkDataIsStale: &isStale), !isStale
          {
            directories.append(url)
            if url.startAccessingSecurityScopedResource() {
              accessedURLs.insert(url)
            }
          }
        }
      }
    }
  }

  func cleanupThumbnails() -> Int {
    let count = ThumbnailCache.shared.cleanupDanglingThumbnails()
    UserDefaults.standard.set(count, forKey: "lastThumbnailCleanupCount")
    return count
  }

  // Import directory management
  func chooseExistingImportDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Select"
    panel.message = "Select a folder where imported photos will be stored"

    if panel.runModal() == .OK, let url = panel.url {
      customImportDirectory = url
      if url.startAccessingSecurityScopedResource() {
        accessedURLs.insert(url)
      }
    }
  }

  func clearCustomImportDirectory() {
    if let url = customImportDirectory {
      url.stopAccessingSecurityScopedResource()
      accessedURLs.remove(url)
    }
    customImportDirectory = nil
  }

  private func saveCustomImportDirectory() {
    if let url = customImportDirectory {
      do {
        let bookmarkData = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        let bookmarkBase64 = bookmarkData.base64EncodedString()
        UserDefaults.standard.set(bookmarkBase64, forKey: importDirectoryKey)
      } catch {
        print("Error saving custom import directory bookmark: \(error)")
      }
    } else {
      UserDefaults.standard.removeObject(forKey: importDirectoryKey)
    }
  }

  private func loadCustomImportDirectory() {
    if let bookmarkBase64 = UserDefaults.standard.string(forKey: importDirectoryKey),
      let bookmarkData = Data(base64Encoded: bookmarkBase64)
    {
      var isStale = false
      if let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), !isStale {
        customImportDirectory = url
        if url.startAccessingSecurityScopedResource() {
          accessedURLs.insert(url)
        }
      }
    }
  }

  var importDirectory: URL {
    // Use custom directory if set, otherwise use default
    if let customDir = customImportDirectory {
      return customDir
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let importDir = home.appendingPathComponent("Downloads/Imported")

    do {
      try FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)
    } catch {
      print("Failed to create import directory: \(error)")
    }

    return importDir
  }

  deinit {
    for url in accessedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }
}
