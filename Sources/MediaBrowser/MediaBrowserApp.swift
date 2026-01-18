import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
  static let rotateClockwise = Notification.Name("rotateClockwise")
  static let rotateCounterClockwise = Notification.Name("rotateCounterClockwise")
  static let openSettings = Notification.Name("openSettings")
  static let openImport = Notification.Name("openImport")
  static let databaseSwitched = Notification.Name("databaseSwitched")
  static let openNewDatabase = Notification.Name("openNewDatabase")
  static let openDatabase = Notification.Name("openDatabase")
}

extension UserDefaults {
  private static let recentDatabasesKey = "recentDatabases"
  private static let maxRecentDatabases = 5

  static func addRecentDatabase(_ path: String) {
    var recent = recentDatabases()
    // Remove if already exists (to move to front)
    recent.removeAll { $0 == path }
    // Add to front
    recent.insert(path, at: 0)
    // Keep only the last 5
    if recent.count > maxRecentDatabases {
      recent = Array(recent.prefix(maxRecentDatabases))
    }
    UserDefaults.standard.set(recent, forKey: recentDatabasesKey)
  }

  static func recentDatabases() -> [String] {
    return UserDefaults.standard.stringArray(forKey: recentDatabasesKey) ?? []
  }

  static func saveWindowState(for databasePath: String, frame: NSRect, isFullscreen: Bool) {
    let frameString = NSStringFromRect(frame)
    UserDefaults.standard.set(frameString, forKey: databasePath + "_windowFrame")
    UserDefaults.standard.set(isFullscreen, forKey: databasePath + "_windowFullscreen")
  }

  static func windowState(for databasePath: String) -> (frame: NSRect?, isFullscreen: Bool) {
    let frameString = UserDefaults.standard.string(forKey: databasePath + "_windowFrame")
    let frame = frameString.map { NSRectFromString($0) }
    let isFullscreen = UserDefaults.standard.bool(forKey: databasePath + "_windowFullscreen")
    return (frame: frame, isFullscreen: isFullscreen)
  }

  private static let openDatabaseWindowsKey = "openDatabaseWindows"

  @MainActor static func addOpenDatabaseWindow(_ path: String) {
    var openPaths = UserDefaults.openDatabaseWindows()
    if !openPaths.contains(path) {
      openPaths.append(path)
      UserDefaults.standard.set(openPaths, forKey: openDatabaseWindowsKey)

    }
  }

  @MainActor static func removeOpenDatabaseWindow(_ path: String) {
    var openPaths = UserDefaults.openDatabaseWindows()
    if let index = openPaths.firstIndex(of: path) {
      openPaths.remove(at: index)
      UserDefaults.standard.set(openPaths, forKey: openDatabaseWindowsKey)

    }
  }

  static func openDatabaseWindows() -> [String] {
    return UserDefaults.standard.stringArray(forKey: openDatabaseWindowsKey) ?? []
  }
}

@preconcurrency class AppDelegate: NSObject, NSApplicationDelegate {
  private nonisolated(unsafe) static var _isTerminating = false
  static var isTerminating: Bool {
    get { _isTerminating }
    set { _isTerminating = newValue }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Suppress MapKit debug output
    UserDefaults.standard.set(false, forKey: "MKDefaultLogLevel")

    // GeocodingService is started in ContentView

    // Open previously open database windows
    let openPaths = UserDefaults.openDatabaseWindows()

    if !openPaths.isEmpty {
      // Stagger window openings to avoid full screen conflicts
      for (index, path) in openPaths.enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + Double(index) * 0.2) {
          if let action = WindowManager.openWindow {
            action(path)
          }
        }
      }
    } else {
      // Fallback to last opened database if no open windows were saved
      if let lastPath = UserDefaults.standard.string(forKey: "lastOpenedDatabasePath") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          if let action = WindowManager.openWindow {
            action(lastPath)
          }
        }
      }
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    // Disable window tabbing for all windows
    NSApp.windows.forEach { $0.tabbingMode = .disallowed }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  func applicationWillTerminate(_ notification: Notification) {
    AppDelegate.isTerminating = true
    // App cleanup - no auto-sync to clean up
  }

}

class WindowManager {
  @MainActor static var openWindow: ((String) -> Void)?
}

@main
struct MediaBrowserApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @ObservedObject private var lightboxStateManager = LightboxStateManager.shared
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    let _ =
      WindowManager.openWindow = { value in
        openWindow(id: "database", value: value)
      }

    WindowGroup(id: "launcher") {
      EmptyView()
    }
    .defaultLaunchBehavior(.suppressed)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New...") {
          let savePanel = NSSavePanel()
          savePanel.canCreateDirectories = true
          savePanel.showsTagField = false
          savePanel.nameFieldStringValue = "database.\(DatabaseManager.databaseFileExtension)"
          if #available(macOS 12.0, *) {
            savePanel.allowedContentTypes = [
              UTType(filenameExtension: DatabaseManager.databaseFileExtension)!
            ]
          } else {
            savePanel.allowedFileTypes = [DatabaseManager.databaseFileExtension]
          }
          savePanel.title = "New Database"
          if savePanel.runModal() == .OK, let url = savePanel.url {
            WindowManager.openWindow?(url.path)
          }
        }
        .keyboardShortcut("n", modifiers: .command)

        Button("Open...") {
          let openPanel = NSOpenPanel()
          openPanel.canChooseFiles = true
          openPanel.canChooseDirectories = false
          openPanel.allowsMultipleSelection = false
          if #available(macOS 12.0, *) {
            openPanel.allowedContentTypes = [
              UTType(filenameExtension: DatabaseManager.databaseFileExtension)!
            ]
          } else {
            openPanel.allowedFileTypes = [DatabaseManager.databaseFileExtension]
          }
          openPanel.title = "Open Database"
          if openPanel.runModal() == .OK, let url = openPanel.url {
            WindowManager.openWindow?(url.path)
          }
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()
      }

      CommandGroup(after: .newItem) {
        Menu("Open Recent") {
          if UserDefaults.recentDatabases().isEmpty {
            Text("No Recent Databases").foregroundColor(.secondary)
          } else {
            ForEach(UserDefaults.recentDatabases(), id: \.self) { path in
              Button(action: {
                WindowManager.openWindow?(path)
              }) {
                Text((path as NSString).lastPathComponent)
              }
            }
            Divider()
            Button("Clear Menu") {
              UserDefaults.standard.removeObject(forKey: "recentDatabases")
            }
          }
        }
      }

      // Add items after standard View menu options
      // View menu for switching between views
      CommandGroup(after: .sidebar) {
        Button(action: {
          NotificationCenter.default.post(name: Notification.Name("switchToGridView"), object: nil)
        }) {
          Label("Grid View", systemImage: "square.grid.2x2")
        }
        .keyboardShortcut("1", modifiers: .command)

        Button(action: {
          NotificationCenter.default.post(name: Notification.Name("switchToMapView"), object: nil)
        }) {
          Label("Map View", systemImage: "map")
        }
        .keyboardShortcut("2", modifiers: .command)

        Divider()

        Button(action: {
          NotificationCenter.default.post(name: Notification.Name("switchToTrashView"), object: nil)
        }) {
          Label("Trash View", systemImage: "trash")
        }
        .keyboardShortcut("3", modifiers: .command)

        Divider()

        Button(action: {
          NotificationCenter.default.post(name: .openImport, object: nil)
        }) {
          Label("Import...", systemImage: "iphone.and.arrow.forward")
        }
        .keyboardShortcut(KeyEquivalent("m"), modifiers: .command)

        Button(action: {
          NotificationCenter.default.post(name: .openSettings, object: nil)
        }) {
          Label("Settings...", systemImage: "gear")
        }
        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)

        Divider()
      }

      // Photos menu for photo operations
      CommandMenu("Photos") {
        Button(action: {
          // Post notification to open media details sidebar
          NotificationCenter.default.post(name: Notification.Name("openMediaDetails"), object: nil)
        }) {
          Label("Details...", systemImage: "info.circle")
        }
        .keyboardShortcut("I", modifiers: .command)
        .disabled(!LightboxStateManager.shared.isLightboxOpen)

        Divider()

        Button(action: {
          NotificationCenter.default.post(name: .rotateClockwise, object: nil)
        }) {
          Label("Rotate Clockwise", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("R", modifiers: .command)
        .disabled(!LightboxStateManager.shared.isLightboxOpen)

        Button(action: {
          NotificationCenter.default.post(name: .rotateCounterClockwise, object: nil)
        }) {
          Label("Rotate Counter Clockwise", systemImage: "arrow.counterclockwise")
        }
        .keyboardShortcut("R", modifiers: [.command, .shift])
        .disabled(!LightboxStateManager.shared.isLightboxOpen)
      }
    }

    WindowGroup(id: "database", for: String.self) { $databasePath in
      // Map Binding<String?> expected by ContentView from Binding<String?>? produced by WindowGroup
      ContentView(databasePath: $databasePath.wrappedValue)
    }
  }
}
