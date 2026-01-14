import AppKit
import Foundation

@MainActor
class DirectoryManager: ObservableObject {
  @MainActor static let shared = DirectoryManager()
  @Published var directoryStates: [(URL, Bool)] = []

  var directories: [URL] { directoryStates.map { $0.0 } }

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
    loadDirectories()
    loadCustomImportDirectory()
  }

  func addDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      if !directoryStates.contains(where: { $0.0 == url }) {
        directoryStates.append((url, false))
        if url.startAccessingSecurityScopedResource() {
          accessedURLs.insert(url)
        }
        saveDirectories()
      }
    }
  }

  func removeDirectory(at index: Int) {
    let (url, _) = directoryStates[index]
    url.stopAccessingSecurityScopedResource()
    accessedURLs.remove(url)
    directoryStates.remove(at: index)
    saveDirectories()
  }

  func renewDirectory(at index: Int) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      // Check if already exists elsewhere
      if let existingIndex = directoryStates.firstIndex(where: { $0.0 == url }),
        existingIndex != index
      {
        // Already exists, don't duplicate
        return
      }
      // Stop old
      let (oldUrl, _) = directoryStates[index]
      oldUrl.stopAccessingSecurityScopedResource()
      accessedURLs.remove(oldUrl)
      // Set new
      directoryStates[index] = (url, false)
      if url.startAccessingSecurityScopedResource() {
        accessedURLs.insert(url)
      }
      saveDirectories()
    }
  }

  private func saveDirectories() {
    // Remove duplicates by URL
    var uniqueStates: [(URL, Bool)] = []
    for state in directoryStates {
      if !uniqueStates.contains(where: { $0.0 == state.0 }) {
        uniqueStates.append(state)
      }
    }
    directoryStates = uniqueStates
    DatabaseManager.shared.saveDirectories(directoryStates)
  }

  private func loadDirectories() {
    directoryStates = DatabaseManager.shared.loadDirectories()
    // Start accessing security scoped resources for non-stale
    for (url, isStale) in directoryStates {
      if !isStale && url.startAccessingSecurityScopedResource() {
        accessedURLs.insert(url)
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
