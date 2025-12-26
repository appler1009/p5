import SwiftUI

struct MediaItemView: View {
  let item: MediaItem
  let onTap: () -> Void
  @ObservedObject private var mediaScanner = MediaScanner.shared
  @State private var thumbnail: NSImage?
  @State private var blurImage: NSImage?

  private var currentBlurhash: String? {
    item.blurhash ?? mediaScanner.blurhashes[item.url]
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
      } else if let blurImage = blurImage {
        Image(nsImage: blurImage)
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
          .overlay(Text("Loading...").font(.caption))
      }

    }
    .overlay(alignment: .topLeading) {
      if item.type == .video {
        Image(systemName: "play.fill")
          .foregroundColor(.white)
          .shadow(radius: 2)
          .padding(7)
      } else if item.type == .livePhoto {
        Image(systemName: "livephoto")
          .foregroundColor(.white)
          .shadow(radius: 2)
          .padding(4)
      }
    }
    .aspectRatio(1, contentMode: .fit)  // Ensure square cells
    .onTapGesture {
      onTap()
    }
    .onAppear {
      loadBlurImage()
      loadThumbnail()
    }
  }

  private func loadBlurImage() {
    if let blurhash = currentBlurhash {
      blurImage = NSImage(blurHash: blurhash, size: CGSize(width: 100, height: 100))
    }
  }

  private func loadThumbnail() {
    Task {
      let image = await ThumbnailCache.shared.thumbnail(for: item.url, size: CGSize(width: 100, height: 100))
      thumbnail = image
    }
  }
}
