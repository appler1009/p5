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
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Suppress MapKit debug output
    UserDefaults.standard.set(false, forKey: "MKDefaultLogLevel")

    // GeocodingService is started in ContentView

    // Open last database
    if let lastPath = UserDefaults.standard.string(forKey: "lastOpenedDatabasePath") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        if let action = WindowManager.openWindow {
          action(lastPath)
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

      // Add items after standard View options
      CommandGroup(after: .sidebar) {
        Button(action: {
          UserDefaults.standard.set("Grid", forKey: "viewMode")
        }) {
          Label("Grid View", systemImage: "square.grid.2x2")
        }
        .keyboardShortcut("1", modifiers: .command)

        Button(action: {
          UserDefaults.standard.set("Map", forKey: "viewMode")
        }) {
          Label("Map View", systemImage: "map")
        }
        .keyboardShortcut("2", modifiers: .command)

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
