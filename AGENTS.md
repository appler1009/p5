# AGENTS.md - Media Browser Project

This file contains essential information for agentic coding assistants working on the Media Browser SwiftUI macOS application.

## Project Overview

Media Browser is a SwiftUI-based macOS application for browsing and managing media files (photos/videos) with cloud synchronization, GPS mapping, and advanced search capabilities.

## Agent Guidelines

### Communication Style
- Do not give extensive summary after the fix is done - just provide a simple git commit message
- Be concise and direct in responses
- Avoid unnecessary elaboration or explanation unless specifically requested

## Build System

### Swift Package Manager
- **Build**: `swift build`
- **Run**: `./.build/arm64-apple-macosx/debug/MediaBrowser`
- **Test**: `swift test`
- **Clean**: `swift package clean`

### Scripts
- **Build Script**: `./build.sh` - Builds and filters output to show only project files
- **Test Script**: `./test.sh` - Runs tests with code coverage and generates HTML report
- **Format Script**: `./format.sh` - Formats Swift files and cleans up whitespace

### Running a Single Test
```bash
swift test --filter testMediaScannerIsEdited
swift test --filter MediaBrowserTests/testExample
```

### Dependencies
- GRDB.swift for database
- AWS SDK Swift for S3 integration
- Platform: macOS 14+

## Code Style Guidelines

### General Principles
- Follow Swift API Design Guidelines
- Use modern Swift features (async/await, structured concurrency)
- Prefer value types (structs) over reference types (classes) where appropriate
- Use meaningful names that describe intent
- Keep functions small and focused on single responsibility
- Do not waste tokens on compliments and greetings

### File Structure
```
Sources/MediaBrowser/
├── ContentView.swift        # Main UI
├── MediaBrowserApp.swift    # App entry point
├── MediaItemView.swift      # Individual media item UI
├── SettingsView.swift       # Settings UI
├── MapView.swift           # Map display
├── FullMediaView.swift     # Full-screen media viewer
├── MediaScanner.swift      # Media discovery logic
├── DatabaseManager.swift   # GRDB database operations
├── S3Service.swift         # AWS S3 integration
├── ThumbnailCache.swift    # Image caching
├── MetadataExtractor.swift # EXIF/metadata parsing
├── DirectoryManager.swift  # Directory management
├── S3Config.swift          # S3 configuration
└── BlurHash*.swift         # BlurHash encoding/decoding

Tests/MediaBrowserTests/
└── MediaBrowserTests.swift # Unit tests
```

### Naming Conventions

#### Types and Protocols
- Use PascalCase for classes, structs, enums, protocols
- Example: `MediaScanner`, `S3Service`, `MediaItem`

#### Functions and Variables
- Use camelCase
- Functions: `scanDirectories()`, `uploadNextItem()`
- Variables: `mediaItems`, `selectedItem`
- Properties: `@Published var isScanning = false`

#### Constants
- Use camelCase for static constants
- Example: `private static let thumbnailSize = 200`

### Imports

#### Standard Order
```swift
import Foundation
import SwiftUI
import MapKit
import AppKit
// Third-party imports
import GRDB
import AWSS3
```

#### Import Style
- Group related imports
- Use `import struct/class/enum` when importing specific types
- Avoid wildcard imports (`import UIKit.*`)

### Type Definitions

#### Structs vs Classes
- Use `struct` for data models and value types
- Use `class` for services, managers, and objects with identity
- Examples:
  ```swift
  struct MediaItem { ... }        // Value type
  class MediaScanner { ... }      // Service with shared state
  ```

#### Enums
```swift
enum MediaType {
    case photo
    case video
}

enum S3SyncStatus: String {
    case notSynced
    case syncing
    case synced
    case failed
}
```

#### Optionals
- Use optionals sparingly, prefer non-optional types
- Use implicitly unwrapped optionals only for UI components
- Example: `@State private var selectedItem: MediaItem?`

### Functions and Methods

#### Signatures
```swift
// Good: Clear intent, proper parameter names
func scanDirectory(_ url: URL) async throws -> [MediaItem]

// Avoid: Unclear parameters
func scan(url: URL) async throws -> [MediaItem]
```

#### Async/Await
- Use `async` for potentially long-running operations
- Use `throws` for operations that can fail
- Example:
```swift
func uploadNextItem() async throws {
    // Implementation
}
```

#### Error Handling
- Use typed errors for specific failure modes
```swift
enum S3Error: Error {
    case invalidCredentials
    case uploadFailed(String)
    case networkError(Error)
}
```

- Use `do-catch` for error handling
```swift
do {
    try await uploadItem(item)
} catch S3Error.invalidCredentials {
    // Handle specific error
} catch {
    // Handle generic error
}
```

### SwiftUI Patterns

#### View Structure
```swift
struct ContentView: View {
    @State private var searchQuery = ""
    @ObservedObject private var mediaScanner = MediaScanner.shared

    var body: some View {
        VStack {
            // UI components
        }
        .navigationTitle("Media Browser")
        .searchable(text: $searchQuery)
    }
}
```

#### State Management
- Use `@State` for view-local state
- Use `@ObservedObject` for shared model objects
- Use `@Published` in ObservableObject for reactive updates
- Example:
```swift
class MediaScanner: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var isScanning = false
}
```

#### View Modifiers
- Apply modifiers in logical order (layout, then styling, then interaction)
- Group related modifiers
```swift
Text("Grid View")
    .font(.headline)
    .foregroundColor(.primary)
    .onTapGesture {
        viewMode = "Grid"
    }
```

### Database Operations

#### GRDB Patterns
```swift
func getAllItems() -> [MediaItem] {
    try! dbQueue.read { db in
        try MediaItem.fetchAll(db)
    }
}

func insertItem(_ item: MediaItem) {
    try! dbQueue.write { db in
        try item.insert(db)
    }
}
```

#### Database Models
```swift
struct MediaItem: Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var url: URL
    var type: MediaType
    // Properties
}
```

### Networking and Async Operations

#### AWS S3 Integration
```swift
func uploadFile(_ url: URL) async throws {
    let input = PutObjectInput(
        bucket: bucketName,
        key: fileName,
        body: .data(try Data(contentsOf: url))
    )
    _ = try await s3Client.putObject(input: input)
}
```

#### Task Management
```swift
Task {
    do {
        try await uploadNextItem()
    } catch {
        print("Upload failed: \(error)")
    }
}
```

### Testing

#### Test Structure
```swift
final class MediaBrowserTests: XCTestCase {
    func testMediaScannerIsEdited() throws {
        let scanner = MediaScanner.shared
        XCTAssertTrue(scanner.isEdited(base: "IMG_E1234"))
        XCTAssertFalse(scanner.isEdited(base: "IMG_1234"))
    }

    func testDatabaseInsertAndRetrieve() throws {
        let db = DatabaseManager.shared
        // Test database operations
    }
}
```

#### Test Naming
- Use `test` prefix
- Describe what is being tested
- Example: `testMediaScannerScan()`, `testDatabaseOperations()`

#### Test Execution Policy
- **Do not run unit tests automatically** - The developer will run tests manually as needed
- Only run tests when explicitly requested by the user
- Use `swift test` to run all tests or `swift test --filter <testName>` for specific tests

### File Organization

#### Extensions
- Group related extensions in separate files when appropriate
- Example: `MediaItem+Extensions.swift`

#### Constants
- Define constants in appropriate files or use enums
```swift
enum Constants {
    static let thumbnailSize: CGFloat = 200
    static let maxConcurrentUploads = 3
}
```

### Documentation

#### Code Comments
- Use `///` for public API documentation
- Use `//` for implementation comments
- Explain complex logic
- Example:
```swift
/// Scans the specified directories for media files
/// - Parameter directories: Array of directory URLs to scan
/// - Returns: Array of discovered media items
func scan(directories: [URL]) async -> [MediaItem] {
    // Implementation with comments for complex parts
}
```

### Security and Best Practices

#### Sensitive Data
- Never hardcode API keys or credentials
- Use environment variables or secure storage for secrets
- Example: AWS credentials via `~/.aws/credentials`

#### Error Messages
- Provide user-friendly error messages
- Log detailed errors for debugging
- Example:
```swift
catch {
    print("Failed to upload \(item.filename): \(error.localizedDescription)")
    // Log detailed error for debugging
    logger.error("Upload failed: \(error)")
}
```

#### Memory Management
- Use weak references for delegates to avoid retain cycles
- Clean up resources in `deinit`
- Use autorelease pools for large operations

### Git Workflow

#### Commit Messages
- Use imperative mood: "Add search functionality" not "Added search functionality"
- Keep first line under 50 characters
- Use body for detailed explanations if needed

#### Branching
- Use feature branches: `feature/add-search`
- Use bugfix branches: `bugfix/fix-upload-crash`
- Merge via pull requests with reviews

### Performance Considerations

#### Image Handling
- Use thumbnail caching to avoid loading full-size images unnecessarily
- Use `Image(decorative:)` for non-semantic images
- Implement lazy loading for large lists

#### Database Optimization
- Use appropriate indexes
- Batch database operations when possible
- Use background queues for heavy operations

#### UI Responsiveness
- Perform expensive operations asynchronously
- Use `ProgressView` for long-running tasks
- Update UI on main thread only

This document should be updated as the codebase evolves. Follow these guidelines to maintain consistency and quality in the Media Browser project.