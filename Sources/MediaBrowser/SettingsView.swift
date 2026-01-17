import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject private var directoryManager: DirectoryManager
  @ObservedObject private var s3Service: S3Service
  @ObservedObject private var databaseManager: DatabaseManager
  @ObservedObject private var mediaScanner: MediaScanner

  init(
    directoryManager: DirectoryManager, s3Service: S3Service, databaseManager: DatabaseManager,
    mediaScanner: MediaScanner
  ) {
    self.directoryManager = directoryManager
    self.s3Service = s3Service
    self.databaseManager = databaseManager
    self.mediaScanner = mediaScanner
  }
  @AppStorage("lastThumbnailCleanupCount") private var lastCleanupCount = 0
  @State private var gridCellSize: Double = 80

  @State private var currentUploadItem: String?

  private var previewS3Uri: String {
    let bucket = s3Service.config.bucketName
    let basePath = s3Service.config.basePath

    // Create a sample date (today)
    let today = Date()
    let calendar = Calendar.current
    let year = calendar.component(.year, from: today)
    let month = String(format: "%02d", calendar.component(.month, from: today))
    let day = String(format: "%02d", calendar.component(.day, from: today))

    let components = [basePath, "\(year)", month, day, "sample-photo.jpg"].filter { !$0.isEmpty }
    let key = components.joined(separator: "/")

    return "s3://\(bucket)/\(key)"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 48) {
        // Database Path Section
        VStack(alignment: .leading, spacing: 12) {
          Text("Database")
            .font(.title2)
            .fontWeight(.semibold)

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Image(systemName: "externaldrive")
                .foregroundColor(.accentColor)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Database File")
                  .font(.body)
                  .fontWeight(.medium)
                Text(databaseManager.databasePath ?? "Not set")
                  .font(.callout)
                  .foregroundColor(.secondary)
                  .monospaced()
              }
            }
            Button("Open in Finder") {
              if let dbPath = databaseManager.databasePath {
                let url = URL(fileURLWithPath: dbPath)
                let directoryURL = url.deletingLastPathComponent()
                NSWorkspace.shared.open(directoryURL)
              }
            }
            .buttonStyle(.bordered)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Grid Settings Section
        VStack(alignment: .leading, spacing: 12) {
          Text("Grid Settings")
            .font(.title2)
            .fontWeight(.semibold)

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Image(systemName: "square.grid.2x2")
                .foregroundColor(.accentColor)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Grid Cell Size")
                  .font(.body)
                  .fontWeight(.medium)
                Text("Adjust the size of grid cells")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
            }
            Slider(value: $gridCellSize, in: 50...200)
              .labelsHidden()
              .frame(minWidth: 200)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Media Management Section
        VStack(alignment: .leading, spacing: 12) {
          Text("Media Management")
            .font(.title2)
            .fontWeight(.semibold)

          // Directory Management with Icon
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Image(systemName: "folder.badge.plus")
                .foregroundColor(.accentColor)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Media Directories")
                  .font(.body)
                  .fontWeight(.medium)
                Text("Configure folders to scan for media files")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
              Button("Add Directory") {
                directoryManager.addDirectory()
              }
              .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)

            // Directory List
            if !directoryManager.directoryStates.isEmpty {
              VStack(alignment: .leading, spacing: 1) {
                ForEach(directoryManager.directoryStates.indices, id: \.self) { index in
                  let (url, isStale) = directoryManager.directoryStates[index]
                  HStack {
                    Image(systemName: "folder")
                      .foregroundColor(.secondary)
                      .frame(width: 16)
                    Text(url.path)
                      .font(.callout)
                      .lineLimit(1)
                    if isStale {
                      Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .help("Bookmark is stale, renew access")
                    }
                    Spacer()
                    if isStale {
                      Button("Renew") {
                        directoryManager.renewDirectory(at: index)
                      }
                      .buttonStyle(.bordered)
                    } else {
                      Button(action: {
                        directoryManager.removeDirectory(at: index)
                      }) {
                        Image(systemName: "trash")
                          .foregroundColor(.red)
                      }
                      .buttonStyle(.plain)
                    }
                  }
                  .padding(.vertical, 1)
                  .padding(.horizontal, 4)
                  .cornerRadius(3)
                }
              }
            } else {
              HStack {
                Image(systemName: "info.circle")
                  .foregroundColor(.secondary)
                Text("No directories configured")
                  .font(.callout)
                  .foregroundColor(.secondary)
                Spacer()
              }
            }

            // Scan Button
            HStack {
              Spacer()
              Button("Scan") {
                Task {
                  await mediaScanner.scan(directories: directoryManager.directories)
                }
              }
              .disabled(mediaScanner.isScanning)
              .buttonStyle(.borderedProminent)
            }
            .padding(.top)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Import Settings Section
        VStack(alignment: .leading, spacing: 12) {
          Text("Import Settings")
            .font(.title2)
            .fontWeight(.semibold)

          ImportDirectorySection()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Database & Cache Section
        VStack(alignment: .leading, spacing: 12) {
          Text("Database & Cache")
            .font(.title2)
            .fontWeight(.semibold)

          // Database Reset with Icon
          HStack {
            Image(systemName: "arrow.counterclockwise")
              .foregroundColor(.orange)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text("Reset Database")
                .font(.body)
                .fontWeight(.medium)
              Text("Clear all scanned media data")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button("Reset") {
              Task { await mediaScanner.reset() }
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
          }

          Divider()

          // Thumbnail Cleanup with Icon
          HStack {
            Image(systemName: "trash.circle")
              .foregroundColor(.blue)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text("Cleanup Thumbnails")
                .font(.body)
                .fontWeight(.medium)
              Text("Remove unused thumbnail cache (\(lastCleanupCount) cleaned last time)")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button("Clean") {
              let count = directoryManager.cleanupThumbnails()
              lastCleanupCount = count
            }
            .buttonStyle(.bordered)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // S3 Sync Section
        VStack(alignment: .leading, spacing: 12) {
          Text("S3 Sync")
            .font(.title2)
            .fontWeight(.semibold)

          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
              // AWS Credentials Group
              GroupBox("AWS Credentials") {
                VStack(alignment: .leading, spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text("Access Key ID:")
                      .font(.callout)
                      .foregroundColor(.primary)
                      .fontWeight(.medium)
                    TextField("", text: $s3Service.config.accessKeyId)
                      .textFieldStyle(.roundedBorder)
                      .frame(minWidth: 300)
                  }

                  VStack(alignment: .leading, spacing: 4) {
                    Text("Secret Access Key:")
                      .font(.callout)
                      .foregroundColor(.primary)
                      .fontWeight(.medium)
                    SecureField("", text: $s3Service.config.secretAccessKey)
                      .textFieldStyle(.roundedBorder)
                      .frame(minWidth: 300)
                  }
                }
                .padding(8)
              }

              // S3 Configuration Group
              GroupBox("S3 Configuration") {
                VStack(alignment: .leading, spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text("Region:")
                      .font(.callout)
                      .foregroundColor(.primary)
                      .fontWeight(.medium)
                    TextField("", text: $s3Service.config.region)
                      .textFieldStyle(.roundedBorder)
                      .frame(minWidth: 300)
                  }

                  VStack(alignment: .leading, spacing: 4) {
                    Text("Bucket Name:")
                      .font(.callout)
                      .foregroundColor(.primary)
                      .fontWeight(.medium)
                    TextField("", text: $s3Service.config.bucketName)
                      .textFieldStyle(.roundedBorder)
                      .frame(minWidth: 300)
                  }

                  VStack(alignment: .leading, spacing: 4) {
                    Text("Base Path:")
                      .font(.callout)
                      .foregroundColor(.primary)
                      .fontWeight(.medium)
                    TextField("", text: $s3Service.config.basePath)
                      .textFieldStyle(.roundedBorder)
                      .frame(minWidth: 300)
                  }

                  // S3 URI Preview
                  if !s3Service.config.bucketName.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                      Text("Expected S3 Location:")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                      HStack {
                        Image(systemName: "link")
                          .foregroundColor(.accentColor)
                          .font(.caption)
                        Text(previewS3Uri)
                          .font(.callout)
                          .foregroundColor(.primary)
                          .monospaced()
                      }
                      .padding(8)
                      .background(Color(.controlBackgroundColor))
                      .cornerRadius(6)
                      .overlay(
                        RoundedRectangle(cornerRadius: 6)
                          .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                      )
                    }
                  }

                  // Auto-Sync Toggle
                  VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    HStack {
                      Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                      VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Sync")
                          .font(.callout)
                          .fontWeight(.medium)
                        Text("Automatically sync new media")
                          .font(.caption)
                          .foregroundColor(.secondary)
                      }
                      Spacer()
                      Toggle("", isOn: $s3Service.autoSyncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: s3Service.autoSyncEnabled) { _, newValue in
                          if newValue {
                            // Immediately upload one item when enabling auto-sync
                            Task {
                              await s3Service.uploadNextItem()
                            }
                          } else {
                            s3Service.stopAutoSync()
                          }
                        }
                    }
                  }
                }
                .padding(8)
                .frame(minWidth: 320)
              }

              // Status and Validation
              HStack(spacing: 8) {
                if s3Service.config.isValid {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                  Text("Configuration is valid")
                    .foregroundColor(.green)
                    .font(.callout)
                    .fontWeight(.medium)

                } else {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                  Text("Configuration incomplete")
                    .foregroundColor(.orange)
                    .font(.callout)
                    .fontWeight(.medium)
                }

                Spacer()

                if s3Service.isUploading {
                  HStack {
                    ProgressView()
                      .scaleEffect(0.5)
                    Text("Uploading: \(currentUploadItem ?? "looking...")")
                      .font(.callout)
                      .foregroundColor(.primary)
                      .onAppear {
                        setupUploadProgressNotifications()
                      }
                    Spacer()
                  }
                } else {
                  HStack {
                    Image(systemName: "checkmark.circle")
                      .foregroundColor(.green)
                    Text("Ready to upload")
                      .font(.callout)
                      .foregroundColor(.primary)
                    Spacer()
                  }
                }
              }
              .padding(.vertical, 4)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onAppear {
        self.gridCellSize = Double(self.databaseManager.getSetting("gridCellSize") ?? "80") ?? 80
      }
      .onChange(of: gridCellSize) { _, newValue in
        print("SettingsView: Grid cell size changed to: \(newValue)")
        databaseManager.setSetting("gridCellSize", value: String(newValue))
        NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
      }
      .onKeyPress(.escape) {
        NSApp.keyWindow?.close()
        return .handled
      }
    }
  }

  /// Update uploading file name
  func updateUploadProgress(fileName: String?) {
    Task { @MainActor in
      updateUploadProgress(fileName: fileName)
    }
  }

  /// Listen for S3 sync status updates
  private func setupUploadProgressNotifications() {
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("UploadProgressUpdated"),
      object: nil,
      queue: .main
    ) { notification in
      if let userInfo = notification.userInfo,
        let fileName = userInfo["fileName"] as? String
      {
        Task { @MainActor in
          updateUploadProgress(fileName: fileName)
        }
      }
    }
  }
}
