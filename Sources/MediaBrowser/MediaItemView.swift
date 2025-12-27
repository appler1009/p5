import SwiftUI

struct MediaItemView: View {
  let item: MediaItem
  let onTap: () -> Void
  @State private var thumbnail: NSImage?

  private var syncStatusIndicator: some View {
    Group {
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
      }
    }
    .font(.caption)
    .shadow(radius: 1)
  }

  var body: some View {
    ZStack {
      if let thumbnail = thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
          .cornerRadius(8)
      } else {
        Rectangle()
          .fill(Color.gray.opacity(0.3))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .cornerRadius(8)
          .overlay(Text("...").font(.caption))
      }

    }
    .overlay(alignment: .topLeading) {
      if item.type == .video {
        Image(systemName: "play.fill")
          .foregroundColor(.white)
          .shadow(radius: 2)
          .padding(7)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      syncStatusIndicator
        .padding(4)
    }
    .aspectRatio(1, contentMode: .fit)  // Ensure square cells
    .help(item.metadata?.filename ?? item.url.lastPathComponent)
    .onTapGesture {
      onTap()
    }
    .onAppear {
      loadThumbnail()
    }
  }

  private func loadThumbnail() {
    Task {
      let image = await ThumbnailCache.shared.thumbnail(
        for: item.url, size: CGSize(width: 100, height: 100))
      thumbnail = image
    }
  }
}
