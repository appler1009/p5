import AVKit
import MapKit
import SwiftUI

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

let animationDuration: TimeInterval = 0.1
let swipeNavigationOffsetThreshold: CGFloat = 35

struct SectionHeader: View {
  let title: String
  let iconName: String

  var body: some View {
    HStack {
      Image(systemName: iconName)
        .foregroundColor(.accentColor)
      Text(title)
        .font(.headline)
      Spacer()
    }
  }
}

struct MediaDetailsSidebar: View {
  let item: LocalFileSystemMediaItem

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 8) {
        // Header
        SectionHeader(title: "Details", iconName: item.type == .video ? "video.fill" : "photo.fill")
          .padding(.top, 8)
          .padding(.bottom, 4)

        // Basic Information
        Group {
          detailRow("Filename", item.displayName)
          detailRow("Type", mediaTypeString)
          detailRow("Path", item.originalUrl.path)  // TODO show original, edited, live, all three.
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

          // File Size
          if let fileSize = getFileSize() {
            detailRow("File Size", formatFileSize(fileSize))
            detailRow("Size in bytes", formatNumber(fileSize))
          }

          // Additional EXIF Metadata (Collapsible)
          if hasAdditionalMetadata(metadata: metadata) {
            Button(action: {
              withAnimation(.easeInOut(duration: 0.2)) {
                showAdditionalMetadata.toggle()
              }
            }) {
              HStack {
                Image(systemName: showAdditionalMetadata ? "chevron.down" : "chevron.right")
                  .font(.caption)
                Text("More Metadata")
                  .font(.headline)
                Spacer()
              }
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)

            if showAdditionalMetadata {
              VStack(alignment: .leading, spacing: 8) {
                if let altitude = metadata.gps?.altitude {
                  detailRow("Altitude", String(format: "%.1f m", altitude))
                }

                // Display all extra EXIF data
                ForEach(Array(metadata.extraEXIF.keys.sorted()), id: \.self) { key in
                  if let value = metadata.extraEXIF[key], shouldShowTag(key) {
                    let cleanKey = key.replacingOccurrences(of: "exif_", with: "")
                      .replacingOccurrences(of: "tiff_", with: "")
                      .replacingOccurrences(of: "gps_", with: "")
                      .replacingOccurrences(of: "image_", with: "")

                    if let intValue = Int(value) {
                      detailRow(cleanKey, String(intValue))
                    } else if let doubleValue = Double(value) {
                      detailRow(cleanKey, String(format: "%.6f", doubleValue))
                    } else {
                      detailRow(cleanKey, value)
                    }
                  }
                }
              }
            }
          }
        }

        Divider()
          .padding(.top, 16)

        // Mini Map
        if let metadata = item.metadata,
          let gps = metadata.gps
        {
          // Location header with icon
          SectionHeader(title: "Location", iconName: "location.fill")
            .padding(.top, 16)
            .padding(.bottom, 4)

          let coordinate = CLLocationCoordinate2D(latitude: gps.latitude, longitude: gps.longitude)
          let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
          )

          Map(position: .constant(.region(region))) {
            Annotation("", coordinate: coordinate) {
              Image(systemName: "mappin.and.ellipse")
                .foregroundColor(.red)
                .font(.title)
            }
          }
          .frame(height: 200)
          .disabled(true)
          .cornerRadius(8)
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.gray.opacity(0.3), lineWidth: 1)
          )

          // Coordinate details in table format
          VStack(alignment: .leading, spacing: 12) {
            detailRow("Latitude", String(format: "%.6f°", gps.latitude))
            detailRow("Longitude", String(format: "%.6f°", gps.longitude))
            if let altitude = gps.altitude {
              detailRow("Altitude", String(format: "%.1f m", altitude))
            }
          }
          .padding(.top, 8)

          Divider()
            .padding(.top, 16)
        }

        // S3 Sync Status
        SectionHeader(title: "S3 Sync", iconName: s3SyncIcon)
          .padding(.top, 16)
          .padding(.bottom, 4)

        VStack(alignment: .leading, spacing: 12) {
          detailRow("Status", s3SyncStatusText)
        }
      }
    }
    .padding(16)
    .padding(.bottom, 32)
    .frame(width: 350)
  }

  @State private var showAdditionalMetadata = false

  private func hasAdditionalMetadata(metadata: MediaMetadata) -> Bool {
    return metadata.extraEXIF.keys.contains { shouldShowTag($0) }
  }

  private func shouldShowTag(_ key: String) -> Bool {
    let blacklistedTags: Set<String> = [
      "ColorSpace", "BrightnessValue", "ExifVersion", "LensSpecification", "SubjectArea",
      "{ExifAux}",
    ]
    let cleanKey = key.replacingOccurrences(of: "exif_", with: "")
      .replacingOccurrences(of: "tiff_", with: "")
      .replacingOccurrences(of: "gps_", with: "")
      .replacingOccurrences(of: "image_", with: "")
    return !blacklistedTags.contains(cleanKey)
  }

  private func detailRow(_ label: String, _ value: String, allowCopy: Bool = true) -> some View {
    HStack(alignment: .top, spacing: 12) {
      // Label (always clickable for copy)
      Button(action: {
        copyToClipboard(value)
      }) {
        Text(label)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.secondary)
          .frame(width: 80, alignment: .leading)
      }
      .buttonStyle(.plain)
      .help("Copy \(label.lowercased())")

      // Value (always clickable for copy)
      Button(action: {
        copyToClipboard(value)
      }) {
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
      }
      .buttonStyle(.plain)
      .help("Copy value to clipboard")

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

  private func copyToClipboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }

  private var s3SyncIcon: String {
    switch item.s3SyncStatus {
    case .synced:
      return "cloud.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    case .notSynced:
      return "cloud.fill"
    case .notApplicable:
      return ""  // No icon for items where sync is not applicable
    }
  }

  private var s3SyncStatusText: String {
    switch item.s3SyncStatus {
    case .synced:
      return "Synced to S3"
    case .failed:
      return "Sync Failed"
    case .notSynced:
      return "Not Synced"
    case .notApplicable:
      return ""  // No status text for items where sync is not applicable
    }
  }

  private func getFileSize() -> Int? {
    // TODO show all three files' sizes
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: item.originalUrl.path)
      if let fileSize = attributes[.size] as? NSNumber {
        return fileSize.intValue
      }
    } catch {
      print("Error getting file size: \(error)")
    }
    return nil
  }

  private func formatFileSize(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
  }

  private func formatNumber(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
  }
}

struct FullMediaView: View {
  let item: LocalFileSystemMediaItem
  let onClose: () -> Void
  let onNext: () -> Void
  let onPrev: () -> Void

  @State private var fullImage: NSImage?
  @State private var player: AVPlayer?
  @State private var showVideo = false
  @AppStorage("fullMediaShowSidebar") private var showSidebar = false

  @State private var currentScale: CGFloat = 1.0
  @State private var imageOffset: CGSize = .zero
  @State private var rotationAngle: Angle = .degrees(0) {
    didSet {
      print("📐 Rotation angle changed: \(oldValue.degrees)° → \(rotationAngle.degrees)°")
    }
  }

  // MARK: - Extracted Components

  @ViewBuilder
  private var sidebarView: some View {
    if showSidebar {
      VStack(spacing: 0) {
        sidebarHeader
        Divider()
        MediaDetailsSidebar(item: item)
        Spacer()
      }
      .frame(width: 350)
      .background(Color(.windowBackgroundColor))
      .shadow(radius: 10)
      .transition(.move(edge: .leading))
    }
  }

  private var sidebarHeader: some View {
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
  }

  private var mainMediaView: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)
      mediaContentView
    }
    .overlay(alignment: .bottom) { mediaTitleOverlay }
    .overlay(alignment: .topTrailing) { closeButton }
    .overlay(alignment: .topLeading) { livePhotoToggleButton }
    .overlay(alignment: .leading) { previousButton }
    .overlay(alignment: .trailing) { nextButton }
    .overlay(keyCaptureView.opacity(0))
    .onTapGesture { onClose() }
  }

  @ViewBuilder
  private var mediaContentView: some View {
    if item.type == .video || (item.type == .livePhoto && showVideo) {
      videoPlayerView
    } else {
      imageView
    }
  }

  private var videoPlayerView: some View {
    Group {
      if let player = player {
        GeometryReader { outerGeo in
          ScrollView([.horizontal, .vertical], showsIndicators: false) {
            AVPlayerViewRepresentable(player: player)
              .id(item.id)
              .frame(
                width: outerGeo.size.width,
                height: outerGeo.size.height
              )
          }
          .onScrollPhaseChange { oldPhase, newPhase, context in
            guard currentScale <= 1.05 else { return }
            let offsetX = context.geometry.contentOffset.x
            if offsetX < (0 - swipeNavigationOffsetThreshold) {
              showPreviousMedia()
            } else if offsetX > swipeNavigationOffsetThreshold {
              showNextMedia()
            }
          }
        }
      } else {
        ProgressView()
      }
    }
  }

  private var imageView: some View {
    Group {
      if let image = fullImage {
        GeometryReader { outerGeo in
          ScrollView([.horizontal, .vertical], showsIndicators: false) {
             Image(nsImage: image)
               .resizable()
               .interpolation(.high)
               .aspectRatio(contentMode: .fit)
               .id(item.id)
               .scaleEffect(currentScale)
               .rotationEffect(rotationAngle)
               .frame(
                 width: outerGeo.size.width * currentScale,
                 height: outerGeo.size.height * currentScale
               )
              .gesture(magnifyGesture)
          }
          .onScrollPhaseChange { oldPhase, newPhase, context in
            guard currentScale <= 1.05 else { return }
            let offsetX = context.geometry.contentOffset.x
            if offsetX < (0 - swipeNavigationOffsetThreshold) {
              showPreviousMedia()
            } else if offsetX > swipeNavigationOffsetThreshold {
              showNextMedia()
            }
          }
        }
      } else {
        ProgressView()
      }
    }
  }

  // MARK: - Gesture Handlers

  private var magnifyGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        let targetScale = max(0.5, min(value, 5.0))
        withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) {
          currentScale = targetScale
        }
      }
  }

  private var swipeNavigationGesture: some Gesture {
    DragGesture(minimumDistance: 30)
      .onEnded { value in
        print("\(currentScale)")
        if currentScale >= 0.95 && currentScale <= 1.05 {  // Only swipe if not zoomed
          if value.translation.width > 0 {
            showNextMedia()
          } else if value.translation.width < 0 {
            showPreviousMedia()
          }
        }
      }
  }

  // MARK: - Overlay Components

  private var mediaTitleOverlay: some View {
    Text(item.displayName)
      .padding(8)
      .background(Color.black.opacity(0.7))
      .foregroundColor(.white)
      .cornerRadius(8)
      .padding(.bottom, 20)
  }

  private var closeButton: some View {
    Button(action: onClose) {
      Image(systemName: "xmark")
        .foregroundColor(.white)
        .padding(10)
        .background(Color.black.opacity(0.5))
        .clipShape(Circle())
    }
    .padding()
  }

  @ViewBuilder
  private var livePhotoToggleButton: some View {
    if item.type == .livePhoto {
      Button(action: toggleLivePhoto) {
        Image(systemName: showVideo ? "photo" : "livephoto")
          .foregroundColor(.white)
          .padding(10)
          .background(Color.black.opacity(0.5))
          .clipShape(Circle())
      }
      .padding()
    }
  }

  private var previousButton: some View {
    VStack {
      Spacer()
      Button(action: showPreviousMedia) {
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

  private var nextButton: some View {
    VStack {
      Spacer()
      Button(action: showNextMedia) {
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

  private var keyCaptureView: some View {
    KeyCaptureView(onKey: handleKeyPress)
  }

  // MARK: - Action Methods

  private func toggleLivePhoto() {
    showVideo.toggle()
    if showVideo {
      loadVideo()
    } else {
      player?.pause()
      loadImage()
    }
  }

  private func handleKeyPress(_ event: NSEvent) -> NSEvent? {
    switch event.keyCode {
    case 53:  // ESC
      if currentScale < 0.99 || currentScale > 1.01 {
        withAnimation(.easeInOut(duration: animationDuration)) {
          currentScale = 1.0
          imageOffset = .zero
        }
        return nil
      } else {
        onClose()
        return nil
      }
    case 123:  // left arrow
      showPreviousMedia()
      return nil
    case 124:  // right arrow
      showNextMedia()
      return nil
    case 23, 33:  // CMD+I or [
      withAnimation(.easeInOut(duration: animationDuration)) {
        showSidebar.toggle()
      }
      return nil
    case 15:  // R key
      if event.modifierFlags.contains(.command) {
        if event.modifierFlags.contains(.shift) {
          Task { await handleRotateCounterClockwise() }
        } else {
          Task { await handleRotateClockwise() }
        }
        return nil
      }
      return event
    default:
      return event
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebarView
      mainMediaView
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
      print("🔄 Item changed (ID: \(item.id)) - resetting rotation to 0°")
      fullImage = nil
      player = nil
      showVideo = false
      rotationAngle = .degrees(0)
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
    .onDisappear {
      player?.pause()
    }
    .animation(.easeInOut(duration: animationDuration), value: showSidebar)
  }

  private func showPreviousMedia() {
    player?.pause()
    currentScale = 1.0
    imageOffset = .zero
    print("⬅️ Navigating to previous - resetting rotation to 0°")
    rotationAngle = .degrees(0)
    onPrev()
  }

  private func handleRotateClockwise() async {
    print("↻ Handle rotate clockwise triggered")
    await rotatePhoto(clockwise: true)
  }

  private func handleRotateCounterClockwise() async {
    print("↺ Handle rotate counter-clockwise triggered")
    await rotatePhoto(clockwise: false)
  }

  private func rotatePhoto(clockwise: Bool) async {
    print("🔄 Starting rotation - clockwise: \(clockwise), current angle: \(rotationAngle.degrees)°")

    // Start rotation animation
    let targetAngle = clockwise ? Angle.degrees(90) : Angle.degrees(-90)
    print("🎯 Target angle: \(targetAngle.degrees)°")

    withAnimation(.easeInOut(duration: 0.3)) {
      rotationAngle = targetAngle
      print("🎬 Animation started - rotating to: \(rotationAngle.degrees)°")
    }

    // Wait a bit for animation to be visible
    print("⏳ Waiting for animation visibility...")
    try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
    print("✅ Animation wait complete, angle should be: \(rotationAngle.degrees)°")

    do {
      // Load the current image
      print("📷 Loading current image...")
      guard let image = NSImage(contentsOf: item.displayURL) else {
        print("❌ Failed to load image")
        // Reset rotation instantly if failed
        rotationAngle = .degrees(0)
        print("✅ Rotation reset to 0° (load failed)")
        return
      }
      print("✅ Image loaded successfully")

      // Rotate the image
      print("🔄 Processing image rotation...")
      let rotatedImage =
        clockwise
        ? ImageProcessing.shared.rotateImageClockwise(image)
        : ImageProcessing.shared.rotateImageCounterClockwise(image)

      guard let rotatedImage = rotatedImage else {
        print("❌ Image rotation processing failed")
        // Reset rotation instantly if failed
        rotationAngle = .degrees(0)
        print("✅ Rotation reset to 0° (rotation failed)")
        return
      }
      print("✅ Image rotated successfully")

      // Create edited file URL
      let editedURL = item.originalUrl.createEditedFileURL()
      print("📄 Created edited file URL: \(editedURL.lastPathComponent)")

      // Save rotated image with EXIF preservation
      print("💾 Saving rotated image with EXIF...")
      try await ImageProcessing.shared.saveRotatedImage(
        rotatedImage,
        to: editedURL,
        preservingEXIF: true,
        sourceURL: item.originalUrl
      )
      print("✅ Image saved successfully")

      // Update the media item
      item.editedUrl = editedURL
      print("📝 Updated media item editedUrl")

      // Update database
      DatabaseManager.shared.updateEditedUrl(for: item.id, editedUrl: editedURL)
      print("💾 Updated database")

      // Regenerate thumbnail
      print("🖼️ Regenerating thumbnail...")
      _ = await ThumbnailCache.shared.generateAndCacheThumbnail(for: editedURL, mediaItem: item)
      print("✅ Thumbnail regenerated")

      // Snap back to 0 rotation instantly (no animation)
      print("🔄 Instantly resetting rotation to 0°...")
      rotationAngle = .degrees(0)
      print("✅ Rotation reset to: \(rotationAngle.degrees)°")

      // Reload the image in the view (this will show the new rotated image)
      if item.type == .photo || (item.type == .livePhoto && !showVideo) {
        print("🔄 Reloading image in view...")
        loadImage()
        print("✅ Image reloaded in view")
      }

      print("🎉 Rotation completed successfully!")

    } catch {
      print("❌ Error rotating photo: \(error)")
      // Reset rotation instantly on error
      rotationAngle = .degrees(0)
      print("✅ Rotation reset to 0° (error)")
    }
  }

  private func showNextMedia() {
    player?.pause()
    currentScale = 1.0
    imageOffset = .zero
    print("➡️ Navigating to next - resetting rotation to 0°")
    rotationAngle = .degrees(0)
    onNext()
  }

  private func loadImage() {
    fullImage = NSImage(contentsOf: item.displayURL)
  }

  private func loadVideo() {
    let videoURL =
      item.type == .livePhoto
      ? item.liveUrl : item.originalUrl
    if let videoURL = videoURL {
      player = AVPlayer(url: videoURL)
      player?.play()
    }
  }
}

// Keep existing helper views
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
