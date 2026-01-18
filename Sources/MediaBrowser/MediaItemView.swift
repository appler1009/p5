import SwiftUI

struct ConditionalTapGestureModifier: ViewModifier {
  let onTap: (() -> Void)?

  func body(content: Content) -> some View {
    if let onTap = onTap {
      content.onTapGesture(perform: onTap)
    } else {
      content
    }
  }
}

struct MediaItemView: View {
  let item: MediaItem
  let onTap: (() -> Void)?
  let isSelected: Bool
  let isDuplicate: Bool
  var externalThumbnail: Image? = nil  // For pre-loaded thumbnails (like in import view)
  var shouldReloadThumbnail: Bool = false  // Trigger to reload thumbnail
  @State private var thumbnail: NSImage?
  @State private var cornerRadius: CGFloat = 3

  private var syncStatusIndicator: some View {
    Group {
      if item.isDeleted {
        Image(systemName: "trash.fill")
          .foregroundColor(.red)
      } else {
        switch item.s3SyncStatus {
        case .synced:
          Image(systemName: "cloud.fill")
            .foregroundColor(.white)
        case .failed:
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red)
        case .notSynced:
          Image(systemName: "cloud")
            .foregroundColor(.white.opacity(0.7))
        case .notApplicable:
          EmptyView()  // No icon for items where sync is not applicable
        }
      }
    }
    .font(.caption)
    .shadow(radius: 1)
  }

  var body: some View {
    AnyView(
      ZStack {
        // Selection background
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)

        if let externalThumbnail = externalThumbnail {
          // Use pre-loaded thumbnail (for import view)
          externalThumbnail
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .clipped()
            .transition(.opacity)
        } else if let thumbnail = thumbnail {
          // Use loaded thumbnail (for main gallery)
          Image(nsImage: thumbnail)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .clipped()
            .transition(.opacity)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Text("...").font(.caption))
        }

        // Sync status indicator
        syncStatusIndicator
          .padding(4)
          .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: item.isDeleted ? .topTrailing : .bottomTrailing)
      }
      .aspectRatio(1, contentMode: .fit)  // Ensure square cells
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))  // Apply rounded corners to entire view
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(
            isSelected ? Color.accentColor : item.isDeleted ? Color.red : Color.clear,
            lineWidth: 4
          )
      )
      .help(item.displayName)
      .modifier(
        ConditionalTapGestureModifier(onTap: onTap)
      )
      .opacity(isDuplicate ? 0.3 : 1.0)
      .onAppear {
        loadThumbnail()
      }
      .onChange(of: shouldReloadThumbnail) { _, newValue in
        if newValue {
          loadThumbnail()
        }
      }
    )
  }

  private func loadThumbnail() {
    Task {
      // First check if thumbnail is already cached
      if let cachedImage = ThumbnailCache.shared.thumbnail(mediaItem: item) {
        thumbnail = cachedImage
        return
      }

      // Generate and cache thumbnail if not found
      if let displayURL = item.displayURL {
        let image = await ThumbnailCache.shared.generateAndCacheThumbnail(
          for: displayURL, mediaItem: item)
        thumbnail = image
      }
    }
  }
}
