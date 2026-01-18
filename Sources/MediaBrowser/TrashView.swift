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
      HStack {
        Text("Trash")
          .font(.title)
          .fontWeight(.bold)
        Spacer()
        if !selectedItems.isEmpty {
          HStack(spacing: 12) {
            Button(
              selectedItems.count == 1
                ? "Restore 1 selected item"
                : "Restore \(selectedItems.count) selected items"
            ) {
              Task {
                await restoreSelectedItems()
              }
            }
            .disabled(isLoading)

            Button(
              selectedItems.count == 1
                ? "Delete 1 selected item from Library"
                : "Delete \(selectedItems.count) selected items from Library"
            ) {
              Task {
                await deleteSelectedItemsFromLibrary()
              }
            }
            .disabled(isLoading)
            .foregroundColor(.red)
          }
        } else if !trashedItems.isEmpty {
          HStack(spacing: 12) {
            Button("Restore All") {
              Task {
                await restoreAllItems()
              }
            }
            .disabled(isLoading)

            Button("Delete All from Library") {
              Task {
                await deleteAllItemsFromLibrary()
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
            title: nil,
            items: trashedItems,
            selectedItems: Set(
              selectedItems.compactMap { itemId in
                trashedItems.first { $0.id == itemId }
              }),
            onSelectionChange: { newSelectedItems in
              selectedItems = Set(newSelectedItems.map { $0.id })
            },
            onItemDoubleTap: { _ in
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
      Task {
        await mediaScanner.loadFromDB()
      }
    }
  }

  private func restoreAllItems() async {
    isLoading = true
    for itemId in trashedItems.map(\.id) {
      databaseManager.restoreFromTrash(itemId: itemId)
    }
    selectedItems.removeAll()
    await MainActor.run {
      loadTrashedItems()
      isLoading = false
      Task {
        await mediaScanner.loadFromDB()
      }
    }
  }

  private func deleteSelectedItemsFromLibrary() async {
    isLoading = true
    let fileManager = FileManager.default

    for itemId in selectedItems {
      if let item = trashedItems.first(where: { $0.id == itemId }) {
        await trashItem(item: item, fileManager: fileManager)
      }
    }

    selectedItems.removeAll()
    await MainActor.run {
      loadTrashedItems()
      isLoading = false
    }
  }

  private func deleteAllItemsFromLibrary() async {
    isLoading = true
    let fileManager = FileManager.default

    for item in trashedItems {
      await trashItem(item: item, fileManager: fileManager)
    }

    selectedItems.removeAll()
    await MainActor.run {
      loadTrashedItems()
      isLoading = false
    }
  }

  private func trashItem(item: LocalFileSystemMediaItem, fileManager: FileManager) async {
    if s3Service.config.isValid && item.s3SyncStatus == .synced {
      do {
        try await s3Service.deleteFromS3(item)
      } catch {
        print("Failed to delete from S3: \(error)")
      }
    }

    let urlsToTrash = [item.originalUrl, item.editedUrl, item.liveUrl].compactMap { $0 }
    for url in urlsToTrash {
      if fileManager.fileExists(atPath: url.path) {
        do {
          try fileManager.trashItem(at: url, resultingItemURL: nil)
        } catch {
          print("Failed to trash \(url.path): \(error)")
        }
      }
    }

    databaseManager.permanentlyDeleteFromTrash(itemId: item.id)
  }
}
