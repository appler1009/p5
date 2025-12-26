import AppKit
import Foundation

class DirectoryManager: ObservableObject {
  static let shared = DirectoryManager()
  @Published var directories: [URL] = []

  private let bookmarkKey = "selectedDirectories"
  private var accessedURLs: Set<URL> = []

  private init() {
    loadBookmarks()
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
      DatabaseManager.shared.saveDirectories(directories)
    }
  }

  func removeDirectory(at index: Int) {
    let url = directories[index]
    url.stopAccessingSecurityScopedResource()
    accessedURLs.remove(url)
    directories.remove(at: index)
    DatabaseManager.shared.saveDirectories(directories)
  }

  private func loadBookmarks() {
    directories = DatabaseManager.shared.loadDirectories()
    for url in directories {
      if url.startAccessingSecurityScopedResource() {
        accessedURLs.insert(url)
      }
    }
  }

  deinit {
    for url in accessedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }
}
