// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "MediaBrowser",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "MediaBrowser", targets: ["MediaBrowser"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0"),
    .package(url: "https://github.com/ringsaturn/tzf-swift.git", from: "0.0.1"),
  ],
  targets: [
    .executableTarget(
      name: "MediaBrowser",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "AWSS3", package: "aws-sdk-swift"),
        .product(name: "AWSClientRuntime", package: "aws-sdk-swift"),
        .product(name: "AWSSDKIdentity", package: "aws-sdk-swift"),
        .product(name: "tzf", package: "tzf-swift"),
      ],
      path: "Sources/MediaBrowser",
      resources: [.copy("AppIcon.icns")]
    ),
    .testTarget(
      name: "MediaBrowserTests",
      dependencies: ["MediaBrowser"],
      path: "Tests/MediaBrowserTests"
    ),
  ]
)
