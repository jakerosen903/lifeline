import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes invented test images: a solid colour with a white circle in the lower right quarter. Kit tests,
/// the UI seed and the fixture writer use it, so no real person's photo is ever a fixture.
public enum GeneratedPhoto {
    public enum Error: Swift.Error, Equatable { case cannotDraw, cannotWrite }

    /// A solid `rgb` rectangle with a white circle in its lower right quarter, written as JPEG (or PNG when `alpha`,
    /// with the rectangle half transparent), with `DateTimeOriginal`, GPS and the EXIF orientation when given.
    public static func write(to url: URL, width: Int, height: Int, rgb: Int, takenAt: String? = nil,
                             gps: (lat: Double, lon: Double)? = nil, orientation: Int = 1, alpha: Bool = false) throws {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Error.cannotDraw }
        let opacity: CGFloat = alpha ? 0.5 : 1
        context.setFillColor(red: CGFloat((rgb >> 16) & 0xFF) / 255 * opacity, green: CGFloat((rgb >> 8) & 0xFF) / 255 * opacity,
                             blue: CGFloat(rgb & 0xFF) / 255 * opacity, alpha: opacity)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Core Graphics draws from the lower left, so the lower right quarter has a high x and a low y.
        let side = Double(min(width, height)) / 4
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: Double(width) * 0.75 - side / 2, y: Double(height) * 0.25 - side / 2, width: side, height: side))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, (alpha ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
        else { throw Error.cannotDraw }
        CGImageDestinationAddImage(destination, image, properties(takenAt: takenAt, gps: gps, orientation: orientation) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Error.cannotWrite }
    }

    private static func properties(takenAt: String?, gps: (lat: Double, lon: Double)?, orientation: Int) -> [CFString: Any] {
        var props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if let takenAt { props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: takenAt] }
        if let gps {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(gps.lat), kCGImagePropertyGPSLatitudeRef: gps.lat < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude: abs(gps.lon), kCGImagePropertyGPSLongitudeRef: gps.lon < 0 ? "W" : "E",
            ]
        }
        return props
    }
}
