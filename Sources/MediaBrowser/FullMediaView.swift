import AVKit
import SwiftUI

struct AVPlayerViewRepresentable: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = player
    view.controlsStyle = .none
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
  @State private var showExif = false

  var body: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)

      if item.type == .video {
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
      VStack {
        if showExif, let metadata = item.metadata {
          ScrollView {
            VStack(alignment: .leading, spacing: 4) {
              if let creationDate = metadata.creationDate {
                Text("Created: \(creationDate.formatted())")
              }
              if let modificationDate = metadata.modificationDate {
                Text("Modified: \(modificationDate.formatted())")
              }
              if let dimensions = metadata.dimensions {
                Text("Dimensions: \(Int(dimensions.width)) x \(Int(dimensions.height))")
              }
              if let exifDate = metadata.exifDate {
                Text("EXIF Date: \(exifDate.formatted()) (local time)")
              }
              if let make = metadata.make {
                Text("Camera: \(make) \(metadata.model ?? "")")
              }
              if let lens = metadata.lens {
                Text("Lens: \(lens)")
              }
              if let iso = metadata.iso {
                Text("ISO: \(iso)")
              }
              if let aperture = metadata.aperture {
                Text("Aperture: f/\(String(format: "%.1f", aperture))")
              }
              if let shutterSpeed = metadata.shutterSpeed {
                Text("Shutter: \(shutterSpeed)s")
              }
              if let gps = metadata.gps {
                Text(
                  "GPS: \(String(format: "%.6f", gps.latitude)), \(String(format: "%.6f", gps.longitude))"
                )
                if let altitude = gps.altitude {
                  Text("Altitude: \(String(format: "%.1f", altitude))m")
                }
              }
              if let duration = metadata.duration {
                Text("Duration: \(String(format: "%.2f", duration))s")
              }
            }
            .padding()
          }
          .frame(maxHeight: 200)
        } else {
          HStack {
            Text(item.url.lastPathComponent)
            Button(action: { showExif.toggle() }) {
              Image(systemName: showExif ? "chevron.down" : "chevron.right")
                .foregroundColor(.white)
            }
          }
        }
      }
      .padding(8)
      .background(Color.black.opacity(0.7))
      .foregroundColor(.white)
      .cornerRadius(8)
      .padding(.bottom, 20)
    }
    .onTapGesture {
      onClose()
    }
    .onChange(of: item.id) {
      fullImage = nil
      player = nil
      if item.type == .video {
        loadVideo()
      } else {
        loadImage()
      }
    }
    .onAppear {
      if item.type == .video {
        loadVideo()
      } else {
        loadImage()
      }
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
  }

  private func loadImage() {
    fullImage = NSImage(contentsOf: item.url)
  }

  private func loadVideo() {
    player = AVPlayer(url: item.url)
    player?.play()
  }
}
