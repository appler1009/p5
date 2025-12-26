import SwiftUI

struct MediaItemView: View {
    let item: MediaItem
    let onTap: () -> Void
    @State private var thumbnail: NSImage?
    
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
                    .overlay(Text("Loading...").font(.caption))
            }
            
            if item.type == .video || item.type == .livePhoto {
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit) // Ensure square cells
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        thumbnail = ThumbnailCache.shared.thumbnail(for: item.url, size: CGSize(width: 100, height: 100))
    }
}