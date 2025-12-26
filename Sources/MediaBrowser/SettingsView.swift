import SwiftUI

struct SettingsView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared

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
