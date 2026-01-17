# Media Browser

A SwiftUI-based macOS application for browsing and managing media files (photos/videos) with cloud synchronization, GPS mapping, and advanced search capabilities.

## Building

### Requirements
- macOS 14.0+
- Swift 5.9+

### Build Commands
```bash
# Build the project
swift build

# Run the application
./.build/arm64-apple-macosx/debug/MediaBrowser

# Run tests
swift test

# Build and run with custom scripts
./build.sh  # Builds with filtered output
./test.sh   # Runs tests with coverage
./format.sh # Formats Swift files
```

## App Icons

The app uses a custom icon set. To set up the app icon:

1. Create the directory structure:
   ```
   Sources/MediaBrowser/AppIcon.iconset/
   └── Contents.json (already created)
   ```

2. Add your icon files in the required sizes:
   - `icon_16x16.png` (16x16)
   - `icon_16x16@2x.png` (32x32)
   - `icon_32x32.png` (32x32)
   - `icon_32x32@2x.png` (64x64)
   - `icon_128x128.png` (128x128)
   - `icon_128x128@2x.png` (256x256)
   - `icon_256x256.png` (256x256)
   - `icon_256x256@2x.png` (512x512)
   - `icon_512x512.png` (512x512)
   - `icon_512x512@2x.png` (1024x1024)

3. Generate the .icns file:
   ```bash
   cd Sources/MediaBrowser
   iconutil -c icns AppIcon.iconset
   ```

4. Clean up (optional):
   ```bash
   rm -rf AppIcon.iconset
   ```

The `AppIcon.icns` file will be included in the build automatically.

## Features

- Media file browsing and management
- Cloud synchronization with AWS S3
- GPS mapping for photos
- Advanced search capabilities
- Thumbnail caching
- Database-driven storage with GRDB

## Dependencies

- GRDB.swift - Database operations
- AWS SDK Swift - S3 integration
- SwiftUI - User interface
- MapKit - GPS mapping
- CoreLocation - Location services