import SwiftUI

struct TrashView: View {
  let databaseManager: DatabaseManager
  let s3Service: S3Service
  let mediaScanner: MediaScanner
  let gridCellSize: Double

  @State private var trashedItems: [LocalFileSystemMediaItem] = []
  @State private var selectedItems: Set<Int> = []
  @State private var isLoading = false

  var body: some View {
    VStack {
      // Header
      HStack {
        Text("Trash")
          .font(.title)
          .fontWeight(.bold)
        Spacer()
        if !selectedItems.isEmpty {
          HStack(spacing: 12) {
            Button("Restore") {
              Task {
                await restoreSelectedItems()
              }
            }
            .disabled(isLoading)

            Button("Delete Permanently") {
              Task {
                await permanentlyDeleteSelectedItems()
              }
            }
            .disabled(isLoading)
            .foregroundColor(.red)
          }
        }
      }
      .padding()

      if trashedItems.isEmpty {
        VStack {
          Image(systemName: "trash")
            .font(.largeTitle)
            .foregroundColor(.secondary)
          Text("Trash is empty")
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          SectionGridView(
            title: nil,  // No title for trash view
            items: trashedItems,
            selectedItems: Set(
              selectedItems.compactMap { itemId in
                trashedItems.first { $0.id == itemId }
              }),
            onSelectionChange: { newSelectedItems in
              selectedItems = Set(newSelectedItems.map { $0.id })
            },
            onItemDoubleTap: { _ in
              // No double-tap action for trash items
            },
            cellWidth: gridCellSize,
            disableDuplicates: false,
            onDuplicateCountChange: nil,
            selectionState: nil,
            onItemAppearanceChange: nil
          )
        }
      }
    }
    .onAppear {
      loadTrashedItems()
    }
  }

  private func loadTrashedItems() {
    trashedItems = databaseManager.getTrashedItems()
  }

  private func restoreSelectedItems() async {
    isLoading = true
    for itemId in selectedItems {
      databaseManager.restoreFromTrash(itemId: itemId)
    }
    selectedItems.removeAll()
    await MainActor.run {
      loadTrashedItems()
      isLoading = false
      // Notify MediaScanner to reload
      Task {
        await mediaScanner.loadFromDB()
      }
    }
  }

  private func permanentlyDeleteSelectedItems() async {
    isLoading = true

    for itemId in selectedItems {
      if let item = trashedItems.first(where: { $0.id == itemId }) {
        // Delete from S3 if synced
        if s3Service.config.isValid && item.s3SyncStatus == .synced {
          do {
            try await s3Service.deleteFromS3(item)
          } catch {
            print("Failed to delete from S3: \(error)")
          }
        }
      }
      databaseManager.permanentlyDeleteFromTrash(itemId: itemId)

      // Run cleanup for any old trash items
      databaseManager.cleanupOldTrashItems()
    }

    selectedItems.removeAll()
    await MainActor.run {
      loadTrashedItems()
      isLoading = false
    }
  }
}
