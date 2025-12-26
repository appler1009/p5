import SwiftUI
import Combine
import AVFoundation

class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache = NSCache<NSString, NSImage>()
    
    func thumbnail(for url: URL, size: CGSize) -> NSImage? {
        let key = "\(url.absoluteString)_\(size.width)x\(size.height)" as NSString
        if let image = cache.object(forKey: key) {
            return image
        }
        let image = generateThumbnail(for: url, size: size)
        if let image = image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
    
    private func generateThumbnail(for url: URL, size: CGSize) -> NSImage? {
        var cgImage: CGImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let img = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height)
           ] as CFDictionary) {
            cgImage = img
        } else {
            // For videos, use AVAssetImageGenerator
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = size
            generator.appliesPreferredTrackTransform = true
            cgImage = try? generator.copyCGImage(at: CMTime.zero, actualTime: nil)
        }
        
        if var cgImage = cgImage {
            // Crop to square if not square
            let width = cgImage.width
            let height = cgImage.height
            let minDim = min(width, height)
            if width != height {
                let x = (width - minDim) / 2
                let y = (height - minDim) / 2
                let rect = CGRect(x: x, y: y, width: minDim, height: minDim)
                if let cropped = cgImage.cropping(to: rect) {
                    cgImage = cropped
                }
            }
            return NSImage(cgImage: cgImage, size: size)
        }
        return nil
    }
}