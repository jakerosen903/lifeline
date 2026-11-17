import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Pure file functions for a picked photo: what it says about itself, a downscaled copy with none of that, its hash, a thumbnail.
public enum PhotoImport {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case unreadable
        public var errorDescription: String? { "Lifeline cannot read this file as a photo." }
    }

    /// What the file says about itself (decision 5): the camera's date and the GPS point. Nothing else.
    public struct Metadata: Sendable, Equatable {
        public var takenAt: PhotoTakenAt?
        public var lat: Double?
        public var lon: Double?
    }

    public static let maxPixel = 2048
    private static let jpegQuality = 0.85
    private static let chunkSize = 1_048_576

    public static func metadata(of source: URL) throws -> Metadata {
        let image = try imageSource(at: source)
        let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]
        // `DateTimeOriginal` only: `DateTime` is an edit date and a file date is not when the picture was taken.
        let takenAt = ((props?[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String)
            .flatMap(PhotoTakenAt.init(exif:))
        let point = (props?[kCGImagePropertyGPSDictionary] as? [CFString: Any]).flatMap(point(from:))
        return Metadata(takenAt: takenAt, lat: point?.lat, lon: point?.lon)
    }

    /// Decisions 3 and 4: orientation applied to the pixels, longest edge at most `maxPixel` and never enlarged,
    /// opaque 8-bit Display P3 on white, JPEG 0.85, and no properties at all. Returns the stored pixel size.
    public static func writeDownscaled(from source: URL, to destination: URL, maxPixel: Int = maxPixel) throws -> (width: Int, height: Int) {
        let scaled = try downsampled(try imageSource(at: source), maxPixel: maxPixel)
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(data: nil, width: scaled.width, height: scaled.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Error.unreadable }
        let frame = CGRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(frame)
        context.draw(scaled, in: frame)
        guard let flat = context.makeImage() else { throw Error.unreadable }
        // Encode to memory, then write: a full disk or a locked folder then throws the file system's own error.
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw Error.unreadable }
        CGImageDestinationAddImage(encoder, flat, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw Error.unreadable }
        try (data as Data).write(to: destination)
        return (scaled.width, scaled.height)
    }

    /// Lower-case hex; reads the file in 1 MB chunks, so a large file never sits in memory whole.
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// For display: the stored copy downsampled so its longest edge is at most `maxPixel`. The decode happens here, on the caller's thread.
    public static func thumbnail(at file: URL, maxPixel: Int) throws -> CGImage {
        try downsampled(try imageSource(at: file), maxPixel: maxPixel)
    }

    // MARK: - Private

    private static func imageSource(at url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { throw Error.unreadable }
        return source
    }

    /// The orientation applied, the longest edge at most `maxPixel` and at most the image's own (ImageIO would enlarge otherwise).
    private static func downsampled(_ source: CGImageSource, maxPixel: Int) throws -> CGImage {
        guard maxPixel > 0, let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw Error.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel, max(width, height)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Error.unreadable }
        return image
    }

    /// Both coordinates, each with its reference letter, and in range; otherwise none. South and west are negative.
    private static func point(from gps: [CFString: Any]) -> (lat: Double, lon: Double)? {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double, let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double, let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String,
              ["N", "S"].contains(latRef), ["E", "W"].contains(lonRef) else { return nil }
        let signed = (lat: latRef == "S" ? -lat : lat, lon: lonRef == "W" ? -lon : lon)
        guard (-90.0...90.0).contains(signed.lat), (-180.0...180.0).contains(signed.lon) else { return nil }
        return signed
    }
}
