import AppKit
import Foundation
import ImageIO

/// Decodes images at the size they are shown (ImageIO thumbnails) and keeps them in a size-limited cache,
/// so a note full of screenshots does not hold full-resolution bitmaps in memory (spec §3, §10.5).
public final class ImageCache: @unchecked Sendable {
    public static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// The image scaled down to at most `maxPixelWidth` pixels wide (never scaled up).
    public func thumbnail(for url: URL, maxPixelWidth: Int) -> NSImage? {
        guard maxPixelWidth > 0, let size = pixelSize(for: url) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(maxPixelWidth)|\(modified)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let scale = min(1, Double(maxPixelWidth) / size.width)
        let longest = Int((max(size.width, size.height) * scale).rounded(.up))
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // An explicit bitmap rep keeps the pixel size exact (NSImage(cgImage:) reports backing-scale sizes).
        let image = NSImage(size: NSSize(width: cgImage.width, height: cgImage.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        cache.setObject(image, forKey: key, cost: cgImage.width * cgImage.height * 4)
        return image
    }

    /// Pixel dimensions from the file header, without decoding the image.
    public func pixelSize(for url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}
