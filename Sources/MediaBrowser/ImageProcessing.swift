import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI

struct ImageProcessing {
  static let shared = ImageProcessing()

  /// Rotates an image 90 degrees clockwise
  func rotateImageClockwise(_ image: NSImage) -> NSImage? {
    return rotateImage(image, by: .pi / 2)  // 90 degrees clockwise
  }

  /// Rotates an image 90 degrees counter-clockwise
  func rotateImageCounterClockwise(_ image: NSImage) -> NSImage? {
    return rotateImage(image, by: -.pi / 2)  // 90 degrees counter-clockwise
  }

  private func rotateImage(_ image: NSImage, by angle: CGFloat) -> NSImage? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    // Create a bitmap context for drawing the rotated image
    let width = cgImage.width
    let height = cgImage.height

    // For 90-degree rotations, we swap width and height
    let rotatedWidth = angle == .pi / 2 || angle == -.pi / 2 ? height : width
    let rotatedHeight = angle == .pi / 2 || angle == -.pi / 2 ? width : height

    guard
      let context = CGContext(
        data: nil,
        width: rotatedWidth,
        height: rotatedHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue)
    else {
      return nil
    }

    context.translateBy(x: CGFloat(rotatedWidth) / 2, y: CGFloat(rotatedHeight) / 2)
    context.rotate(by: angle)
    context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let rotatedCGImage = context.makeImage() else {
      return nil
    }

    return NSImage(
      cgImage: rotatedCGImage, size: NSSize(width: rotatedWidth, height: rotatedHeight))
  }

  /// Saves a rotated image to disk, optionally preserving EXIF metadata
  func saveRotatedImage(
    _ image: NSImage, to url: URL, preservingEXIF: Bool = true, sourceURL: URL? = nil
  ) async throws {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw NSError(
        domain: "ImageProcessing", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to get CGImage from NSImage"])
    }

    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, "public.jpeg" as CFString, 1, nil)
    guard let destination = destination else {
      throw NSError(
        domain: "ImageProcessing", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }

    var properties: [CFString: Any]?
    if preservingEXIF, let sourceURL = sourceURL {
      properties = MetadataExtractor.extractEXIFProperties(from: sourceURL)
    }

    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary?)

    if !CGImageDestinationFinalize(destination) {
      throw NSError(
        domain: "ImageProcessing", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"])
    }
  }
}
