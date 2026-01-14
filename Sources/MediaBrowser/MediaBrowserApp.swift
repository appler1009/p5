import SwiftUI

extension Notification.Name {
  static let rotateClockwise = Notification.Name("rotateClockwise")
  static let rotateCounterClockwise = Notification.Name("rotateCounterClockwise")
  static let openSettings = Notification.Name("openSettings")
  static let openImport = Notification.Name("openImport")
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Suppress MapKit debug output
    UserDefaults.standard.set(false, forKey: "MKDefaultLogLevel")

    // Start auto-sync if enabled
    if S3Service.shared.autoSyncEnabled && S3Service.shared.config.isValid {
      Task {
        await S3Service.shared.uploadNextItem()
      }
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    // Disable window tabbing for all windows
    NSApp.windows.forEach { $0.tabbingMode = .disallowed }

    // Restore full screen state
    let wasFullScreen = UserDefaults.standard.bool(forKey: "wasFullScreen")
    if wasFullScreen, let window = NSApp.windows.first {
      window.toggleFullScreen(nil)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Save full screen state
    if let window = NSApp.windows.first {
      UserDefaults.standard.set(window.styleMask.contains(.fullScreen), forKey: "wasFullScreen")
    }
    // App cleanup - no auto-sync to clean up
  }

}

@main
struct MediaBrowserApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .commands {
      // Disable New Window menu
      CommandGroup(replacing: .newItem) {}

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
        .keyboardShortcut("O", modifiers: .command)

        Divider()
      }

      // Add Settings to app menu after About
      CommandGroup(after: .appInfo) {
        Button(action: {
          NotificationCenter.default.post(name: .openSettings, object: nil)
        }) {
          Label("Settings...", systemImage: "gear")
        }
        .keyboardShortcut(",", modifiers: .command)
      }

      // Photos menu for photo operations
      CommandMenu("Photos") {
        Button(action: {
          NotificationCenter.default.post(name: .rotateClockwise, object: nil)
        }) {
          Label("Rotate Clockwise", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("R", modifiers: .command)

        Button(action: {
          NotificationCenter.default.post(name: .rotateCounterClockwise, object: nil)
        }) {
          Label("Rotate Counter Clockwise", systemImage: "arrow.counterclockwise")
        }
        .keyboardShortcut("R", modifiers: [.command, .shift])
      }
    }
    Window("Settings", id: "settings") {
      SettingsView()
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 600, height: 300)

    Window("Import", id: "import") {
      ImportView()
    }
    .defaultSize(width: 900, height: 700)
  }
}
