import SwiftUI

struct SettingsView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared
  @AppStorage("lastThumbnailCleanupCount") private var lastCleanupCount = 0

  var body: some View {
    VStack {
      Text("Directory Settings")
        .font(.largeTitle)
        .padding()

      HStack {
        Button("Add Directory") {
          directoryManager.addDirectory()
        }
        Button("Reset Database") {
          MediaScanner.shared.reset()
        }
        .foregroundColor(.red)
        Button("Cleanup Thumbnails (\(lastCleanupCount) last)") {
          let count = directoryManager.cleanupThumbnails()
          lastCleanupCount = count
        }
        Spacer()
      }
      .padding(.horizontal)

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
      .frame(minHeight: 200)
    }
    .frame(minWidth: 600, minHeight: 400)
    .padding()
  }
}
