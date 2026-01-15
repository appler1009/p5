import AppKit
import SwiftUI

struct ImportDirectorySection: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Import Directory with Icon
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Image(systemName: "square.and.arrow.down")
            .foregroundColor(.green)
            .frame(width: 24)
          VStack(alignment: .leading, spacing: 2) {
            Text("Import Directory")
              .font(.body)
              .fontWeight(.medium)
            Text("Photos imported from camera will be stored in:")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(
              directoryManager.customImportDirectory == nil
                ? directoryManager.importDirectory.path
                : directoryManager.customImportDirectory!.path
            )
            .font(.caption)
            .foregroundColor(.accentColor)
            .monospaced()
          }
          Spacer()
        }
        .padding(.bottom, 8)

        // Import Directory Controls
        HStack(spacing: 8) {
          Button(
            directoryManager.customImportDirectory == nil
              ? "Choose Import Directory" : "Change Directory"
          ) {
            directoryManager.chooseExistingImportDirectory()
          }
          .buttonStyle(.bordered)

          Button("Use Default") {
            directoryManager.clearCustomImportDirectory()
          }
          .buttonStyle(.bordered)
          .disabled(directoryManager.customImportDirectory == nil)

          Button("Open in Finder") {
            let urlToOpen =
              directoryManager.customImportDirectory ?? directoryManager.importDirectory
            NSWorkspace.shared.open(urlToOpen)
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(.vertical)
  }
}
