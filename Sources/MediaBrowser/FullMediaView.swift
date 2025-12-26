import AVKit
import MapKit
import SwiftUI

struct MediaDetailsSidebar: View {
  let item: MediaItem

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header
      HStack {
        Image(systemName: item.type == .video ? "video.fill" : "photo.fill")
          .foregroundColor(.accentColor)
        Text("Details")
          .font(.headline)
        Spacer()
      }

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          // Basic Information
          Group {
            detailRow("Filename", item.displayName ?? item.url.lastPathComponent)
            detailRow("Type", mediaTypeString)
            detailRow("Path", item.url.path)
          }

          if let metadata = item.metadata {
            // Date Information
            if let creationDate = metadata.creationDate {
              detailRow("Created", formatDate(creationDate))
            }
            if let modificationDate = metadata.modificationDate {
              detailRow("Modified", formatDate(modificationDate))
            }

            // EXIF Information
            if let exifDate = metadata.exifDate {
              detailRow("EXIF Date", formatDate(exifDate))
            }

            // Dimensions
            if let dimensions = metadata.dimensions {
              detailRow("Dimensions", "\(Int(dimensions.width)) × \(Int(dimensions.height))")
            }

            // Duration (for videos)
            if let duration = metadata.duration {
              detailRow("Duration", formatDuration(duration))
            }

            // Camera Information
            if let make = metadata.make {
              detailRow("Camera Make", make)
            }
            if let model = metadata.model {
              detailRow("Camera Model", model)
            }
            if let lens = metadata.lens {
              detailRow("Lens", lens)
            }

            // Camera Settings
            if let iso = metadata.iso {
              detailRow("ISO", "ISO \(iso)")
            }
            if let aperture = metadata.aperture {
              detailRow("Aperture", String(format: "f/%.1f", aperture))
            }
            if let shutterSpeed = metadata.shutterSpeed {
              detailRow("Shutter Speed", shutterSpeed)
            }
          }
        }
        .padding(.bottom, 16)

        // Mini Map
        if let metadata = item.metadata,
          let gps = metadata.gps
        {
          // Location header with icon
          HStack {
            Image(systemName: "location.fill")
              .foregroundColor(.accentColor)
            Text("Location")
              .font(.headline)
            Spacer()
          }
          .padding(.bottom, 4)

          let coordinate = CLLocationCoordinate2D(latitude: gps.latitude, longitude: gps.longitude)
          let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
          )

          ZStack {
            Map(
              coordinateRegion: .constant(region),
              interactionModes: [],
              showsUserLocation: false
            )
            .frame(height: 200)
            .disabled(true)
            .cornerRadius(8)
            .overlay(
              // Add a pin overlay at the exact coordinate location
              VStack {
                Spacer()
                HStack {
                  Spacer()
                  VStack(spacing: 0) {
                    // Pin point
                    Circle()
                      .fill(Color.red)
                      .frame(width: 12, height: 12)
                      .overlay(
                        Circle()
                          .stroke(Color.white, lineWidth: 2)
                          .frame(width: 8, height: 8)
                      )

                    // Pin shadow/point
                    VStack(spacing: 0) {
                      Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: 8)
                      Triangle()
                        .fill(Color.red)
                        .frame(width: 12, height: 8)
                    }
                    .offset(y: -6)
                  }
                  .offset(x: -6, y: -10)  // Center the pin
                  Spacer()
                }
                .padding(.bottom, 25)
              }
            )
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
          }

          // Coordinate details in table format
          VStack(alignment: .leading, spacing: 4) {
            coordinateRow("Latitude", String(format: "%.6f°", gps.latitude))
            coordinateRow("Longitude", String(format: "%.6f°", gps.longitude))
            if let altitude = gps.altitude {
              coordinateRow("Altitude", String(format: "%.1f m", altitude))
            }
          }
          .padding(.top, 8)
        }
      }
    }
    .padding(16)
    .frame(width: 350)
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(label)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
        .frame(width: 80, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        if label == "Path" {
          // For Path, create a multi-line layout with full width
          Text(value)
            .font(.body)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          // For other fields, keep single line with ellipsis
          Text(value)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func coordinateRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(label)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
        .frame(width: 80, alignment: .leading)

      Text(value)
        .font(.body)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

      Spacer()
    }
  }

  private var mediaTypeString: String {
    switch item.type {
    case .photo:
      return "Photo"
    case .livePhoto:
      return "Live Photo"
    case .video:
      return "Video"
    }
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

// Updated FullMediaView with sidebar
struct FullMediaView: View {
  let item: MediaItem
  let onClose: () -> Void
  let onNext: () -> Void
  let onPrev: () -> Void

  @State private var fullImage: NSImage?
  @State private var player: AVPlayer?
  @State private var showVideo = false
  @State private var showSidebar = false

  var body: some View {
    HStack(spacing: 0) {
      // Sidebar (left side)
      if showSidebar {
        VStack(spacing: 0) {
          // Sidebar header
          HStack {
            Spacer()
            Button(action: { showSidebar = false }) {
              Image(systemName: "sidebar.right")
                .foregroundColor(.secondary)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Color(.controlBackgroundColor))

          Divider()

          MediaDetailsSidebar(item: item)

          Spacer()
        }
        .frame(width: 350)
        .background(Color(.windowBackgroundColor))
        .shadow(radius: 10)
        .transition(.move(edge: .leading))
      }

      // Main media view
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
          case 23:
            showSidebar.toggle()
            return nil  // CMD+I
          case 33:
            showSidebar.toggle()
            return nil  // [ key
          default: return event
          }
        })
        .opacity(0)
      )
      .onTapGesture {
        onClose()
      }
    }
    .overlay(alignment: .bottomLeading) {
      // Sidebar toggle button
      Button(action: { showSidebar.toggle() }) {
        HStack(spacing: 4) {
          Image(systemName: showSidebar ? "sidebar.right" : "sidebar.left")
            .font(.caption)
          if showSidebar {
            Text("Hide")
              .font(.caption2)
          } else {
            Text("Info")
              .font(.caption2)
          }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7))
        .cornerRadius(6)
      }
      .padding(.leading, 16)
      .padding(.bottom, 20)
      .animation(.easeInOut(duration: 0.2), value: showSidebar)
      .help("Toggle Sidebar (⌘I or [)")
      .keyboardShortcut("i", modifiers: .command)
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

// Keep existing helper views
struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

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
