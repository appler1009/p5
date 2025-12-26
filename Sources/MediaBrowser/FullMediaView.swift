import AVKit
import SwiftUI

struct AVPlayerViewRepresentable: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = player
    view.controlsStyle = .floating
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    nsView.player = player
  }
}

struct KeyCaptureView: NSViewRepresentable {
  let onKey: (NSEvent) -> NSEvent?

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      return onKey(event)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    var monitor: Any?
    deinit {
      if let monitor = monitor {
        NSEvent.removeMonitor(monitor)
      }
    }
  }
}

struct FullMediaView: View {
  let item: MediaItem
  let onClose: () -> Void
  let onNext: () -> Void
  let onPrev: () -> Void

  @State private var fullImage: NSImage?
  @State private var player: AVPlayer?
  @State private var showVideo = false

  var body: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)

      if item.type == .video || (item.type == .livePhoto && showVideo) {
        if let player = player {
          AVPlayerViewRepresentable(player: player)
            .id(item.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ProgressView()
        }
      } else {
        if let image = fullImage {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(item.id)
        } else {
          ProgressView()
        }
      }
    }
    .overlay(alignment: .bottom) {
      Text(item.displayName ?? item.url.lastPathComponent)
        .padding(8)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(8)
        .padding(.bottom, 20)
    }
    .overlay(alignment: .topTrailing) {
      Button(action: onClose) {
        Image(systemName: "xmark")
          .foregroundColor(.white)
          .padding(10)
          .background(Color.black.opacity(0.5))
          .clipShape(Circle())
      }
      .padding()
    }
    .overlay(alignment: .topLeading) {
      if item.type == .livePhoto {
        Button(action: {
          showVideo.toggle()
          if showVideo {
            loadVideo()
          } else {
            loadImage()
          }
        }) {
          Image(systemName: showVideo ? "photo" : "livephoto")
            .foregroundColor(.white)
            .padding(10)
            .background(Color.black.opacity(0.5))
            .clipShape(Circle())
        }
        .padding()
      }
    }
    .overlay(alignment: .leading) {
      VStack {
        Spacer()
        Button(action: onPrev) {
          Image(systemName: "chevron.left")
            .foregroundColor(.white)
            .padding(10)
            .background(Color.black.opacity(0.5))
            .clipShape(Circle())
        }
        .padding(.leading)
        Spacer()
      }
    }
    .overlay(alignment: .trailing) {
      VStack {
        Spacer()
        Button(action: onNext) {
          Image(systemName: "chevron.right")
            .foregroundColor(.white)
            .padding(10)
            .background(Color.black.opacity(0.5))
            .clipShape(Circle())
        }
        .padding(.trailing)
        Spacer()
      }
    }
    .overlay(
      KeyCaptureView(onKey: { event in
        switch event.keyCode {
        case 53:
          onClose()
          return nil  // ESC
        case 123:
          onPrev()
          return nil  // left arrow
        case 124:
          onNext()
          return nil  // right arrow
        default: return event
        }
      })
      .opacity(0)
    )
    .onTapGesture {
      onClose()
    }
    .onChange(of: item.id) {
      fullImage = nil
      player = nil
      showVideo = false
      if item.type == .video || (item.type == .livePhoto && showVideo) {
        loadVideo()
      } else if item.type == .photo || (item.type == .livePhoto && !showVideo) {
        loadImage()
      }
    }
    .onAppear {
      showVideo = false
      if item.type == .video || (item.type == .livePhoto && showVideo) {
        loadVideo()
      } else if item.type == .photo || (item.type == .livePhoto && !showVideo) {
        loadImage()
      }
    }
  }

  private func loadImage() {
    fullImage = NSImage(contentsOf: item.url)
  }

  private func loadVideo() {
    let videoURL =
      item.type == .livePhoto
      ? item.url.deletingPathExtension().appendingPathExtension("mov") : item.url
    player = AVPlayer(url: videoURL)
    player?.play()
  }
}
