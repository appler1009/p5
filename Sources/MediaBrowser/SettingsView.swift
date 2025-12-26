import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared
  @AppStorage("lastThumbnailCleanupCount") private var lastCleanupCount = 0

  var body: some View {
    ZStack {
      Color.clear
        .frame(width: 0, height: 0)
        .onAppear {
          NSApp.keyWindow?.title = "Settings"
        }
      Form {
        Section(header: Text("Directory Management")) {
          HStack {
            Button("Add Directory") {
              directoryManager.addDirectory()
            }
            Spacer()
          }
          List {
            ForEach(directoryManager.directories.indices, id: \.self) { index in
              HStack {
                Text(directoryManager.directories[index].path)
                Spacer()
                Button("Remove") {
                  directoryManager.removeDirectory(at: index)
                }
              }
            }
          }
          .frame(height: 120)  // Compact height for a few rows
        }

        Section(header: Text("Database Management")) {
          HStack {
            Button("Reset Database") {
              MediaScanner.shared.reset()
            }
            .foregroundColor(.red)
            Spacer()
          }
          HStack {
            Button("Cleanup Thumbnails (\(lastCleanupCount) last)") {
              let count = directoryManager.cleanupThumbnails()
              lastCleanupCount = count
            }
            Spacer()
          }
        }
      }
      .padding()
      .frame(minWidth: 600, minHeight: 300)
      .onKeyPress(.escape) {
        NSApp.keyWindow?.close()
        return .handled
      }
    }
  }
}
