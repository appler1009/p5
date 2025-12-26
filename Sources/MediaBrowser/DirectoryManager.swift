import Foundation
import AppKit

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
            // Create security-scoped bookmark
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: "\(bookmarkKey)_\(url.path)")
                directories.append(url)
                if url.startAccessingSecurityScopedResource() {
                    accessedURLs.insert(url)
                }
            } catch {
                print("Error creating bookmark: \(error)")
            }
        }
    }

    func removeDirectory(at index: Int) {
        let url = directories[index]
        url.stopAccessingSecurityScopedResource()
        accessedURLs.remove(url)
        UserDefaults.standard.removeObject(forKey: "\(bookmarkKey)_\(url.path)")
        directories.remove(at: index)
    }

    private func loadBookmarks() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(bookmarkKey + "_") }
        for key in keys {
            if let data = UserDefaults.standard.data(forKey: key) {
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    if !isStale {
                        directories.append(url)
                        if url.startAccessingSecurityScopedResource() {
                            accessedURLs.insert(url)
                        }
                    } else {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
            }
        }
    }

    deinit {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}