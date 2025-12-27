import SwiftUI

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

  func applicationWillTerminate(_ notification: Notification) {
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
      // Add items after the standard View options
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
      }
    }
    WindowGroup(id: "settings") {
      SettingsView()
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 600, height: 300)
  }
}
