import ImageCaptureCore
import SwiftUI

struct ImportView: View {
  @State private var isScanning = false
  @State private var connectionMessage = "Scanning for connected iPhones..."
  @State private var detectedDevices: [String] = []
  @State private var deviceBrowser: ICDeviceBrowser?
  @State private var hasInitialized = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      // Sidebar
      VStack(alignment: .leading, spacing: 16) {
        Text("Sources")
          .font(.headline)
          .padding(.bottom, 8)

        VStack(spacing: 12) {
          Button(action: {
            scanForDevices()
          }) {
            HStack {
              Image(systemName: "iphone.and.arrow.forward")
                .frame(width: 20)
              Text("iPhone (USB)")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)

          Button(action: {
            openFilePicker()
          }) {
            HStack {
              Image(systemName: "folder")
                .frame(width: 20)
              Text("Browse Files")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          Text("USB Connection")
            .font(.subheadline)
            .fontWeight(.medium)

          Text(connectionMessage)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)

        Spacer()
      }
      .padding()
      .frame(minWidth: 280)
    } detail: {
      // Main content area
      VStack(spacing: 24) {
        if isScanning {
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Scanning for connected devices...")
              .font(.headline)
              .foregroundColor(.primary)
          }
        } else if detectedDevices.isEmpty {
          VStack(spacing: 20) {
            Image(systemName: "iphone.slash")
              .font(.system(size: 80))
              .foregroundColor(.secondary)

            VStack(spacing: 12) {
              Text("No iPhone Detected")
                .font(.title2)
                .fontWeight(.semibold)

              Text("Connect your iPhone via USB and select photos to import")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
              Button("Scan Devices") {
                scanForDevices()
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)

              Button("Browse Files") {
                openFilePicker()
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
            }
          }
          .padding(40)
        } else {
          VStack(spacing: 16) {
            ForEach(detectedDevices, id: \.self) { device in
              HStack {
                Image(systemName: "iphone")
                  .foregroundColor(.green)
                Text(device)
                  .font(.headline)
                Spacer()
                Button("Select") {
                  // Handle device selection
                }
                .buttonStyle(.borderedProminent)
              }
              .padding()
              .background(Color.gray.opacity(0.1))
              .cornerRadius(8)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(NSColor.controlBackgroundColor))
    }
    .navigationTitle("Import from iPhone")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
    .onAppear {
      if !hasInitialized {
        hasInitialized = true
        scanForDevices()
      }
    }
    .frame(minWidth: 700, minHeight: 500)
  }

  private func scanForDevices() {
    isScanning = true
    detectedDevices.removeAll()

    // Use ImageCaptureCore which is the proper framework for camera devices
    deviceBrowser = ICDeviceBrowser()

    // Create a simple delegate class
    let delegate = DeviceDelegate(
      onDeviceFound: { device in
        print("DEBUG: ICDevice found: \(device.name ?? "Unknown")")

        if let cameraDevice = device as? ICCameraDevice {
          print("DEBUG: ICCameraDevice found: \(cameraDevice.name ?? "Unknown")")
          print("DEBUG: Device capabilities: \(cameraDevice.capabilities)")
          print("DEBUG: Device name: \(cameraDevice.name ?? "Unknown")")

          // Check for iPhone indicators
          let deviceName = cameraDevice.name ?? "Unknown"
          let deviceType = deviceName.lowercased()

          // Simple iPhone detection - just check the device name
          DispatchQueue.main.async {
            if deviceType.contains("iphone") && !self.detectedDevices.contains(deviceName) {
              self.detectedDevices.append("iPhone (\(deviceName))")
              print("DEBUG: Added iPhone via ImageCapture: \(deviceName)")
            } else {
              print("DEBUG: Device found: \(deviceName)")
            }
            if deviceType.contains("iphone") && !self.detectedDevices.contains(deviceName) {
              self.detectedDevices.append("iPhone (\(deviceName))")
              print("DEBUG: Added iPhone via ImageCapture: \(deviceName)")
            } else {
              print("DEBUG: Device found but not identified as iPhone: \(deviceName)")
            }
          }
        }
      },
      onDeviceRemoved: { device in
        print("DEBUG: ICDevice removed: \(device.name ?? "Unknown")")
        DispatchQueue.main.async {
          self.detectedDevices.removeAll {
            $0.lowercased().contains((device.name ?? "").lowercased())
          }
        }
      }
    )

    deviceBrowser?.delegate = delegate
    deviceBrowser?.start()

    // Stop browsing after a timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
      isScanning = false
      if self.detectedDevices.isEmpty {
        self.connectionMessage = """
          No iPhones detected via USB.

          Try:
          • Unlock your iPhone
          • Tap "Trust This Computer" on iPhone
          • Use Apple USB-C cable
          • Check if iPhone appears in Image Capture app
          • Grant Full Disk Access in System Settings
          • Restart your iPhone
          """
      }
    }
  }

  private func openFilePicker() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.image, .movie]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.message = "Select photos and videos to import"
    panel.prompt = "Import"

    if panel.runModal() == .OK {
      let urls = panel.urls
      importManualFiles(urls)
    }
  }

  private func importManualFiles(_ urls: [URL]) {
    let importDirectory = DirectoryManager.shared.importDirectory

    for url in urls {
      let fileName = url.lastPathComponent
      let destinationUrl = importDirectory.appendingPathComponent(fileName)

      do {
        // Copy file to import directory
        try FileManager.default.copyItem(at: url, to: destinationUrl)

        // Add to MediaScanner
        let mediaType: MediaType
        if url.pathExtension.lowercased().contains("jpg")
          || url.pathExtension.lowercased().contains("heic")
          || url.pathExtension.lowercased().contains("png")
        {
          mediaType = .photo
        } else {
          mediaType = .video
        }

        let mediaItem = MediaItem(
          id: Int.random(in: 1...Int.max),
          url: destinationUrl,
          type: mediaType,
          metadata: nil,
          displayName: nil
        )

        MediaScanner.shared.items.append(mediaItem)

      } catch {
        print("Failed to import file \(url.lastPathComponent): \(error)")
      }
    }

    // Trigger metadata extraction and refresh
    Task {
      await MediaScanner.shared.scan(directories: DirectoryManager.shared.directories)
      dismiss()
    }
  }
}

// MARK: - Device Delegate for ImageCaptureCore
class DeviceDelegate: NSObject, ICDeviceBrowserDelegate {
  let onDeviceFound: (ICDevice) -> Void
  let onDeviceRemoved: (ICDevice) -> Void

  init(onDeviceFound: @escaping (ICDevice) -> Void, onDeviceRemoved: @escaping (ICDevice) -> Void) {
    self.onDeviceFound = onDeviceFound
    self.onDeviceRemoved = onDeviceRemoved
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    onDeviceFound(device)
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    onDeviceRemoved(device)
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
    print("DEBUG: ICDevice name changed: \(device.name ?? "Unknown")")
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeSharingState device: ICDevice) {
    print("DEBUG: ICDevice sharing state changed: \(device.name ?? "Unknown")")
  }
}
