import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Suppress MapKit debug output
    UserDefaults.standard.set(false, forKey: "MKDefaultLogLevel")
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Clean up auto-sync timer
    S3Service.shared.stopAutoSync()
  }
}

@main
struct MediaBrowserApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    WindowGroup(id: "settings") {
      SettingsView()
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 600, height: 300)
  }
}
