import CoreGraphics
import Foundation
import ImageIO

public struct LoadedImage {
    /// Pixels with the EXIF orientation already applied, so every detector
    /// and the redactor work in the same upright coordinate space.
    public var cgImage: CGImage
    /// UTI of the source file (e.g. public.jpeg), reused for the output format.
    public var typeIdentifier: String

    public var width: Int { cgImage.width }
    public var height: Int { cgImage.height }
}

public enum ImageLoader {
    public static func load(path: String) throws -> LoadedImage {
        guard FileManager.default.fileExists(atPath: path) else {
            throw PDMaskError("画像が見つかりません: \(path)")
        }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw PDMaskError("画像を読み込めません: \(path)")
        }

        // Generating a full-size "thumbnail" with the transform flag is the ImageIO way
        // to bake the EXIF orientation into the pixels.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PDMaskError("画像をデコードできません: \(path)")
        }
        return LoadedImage(cgImage: image, typeIdentifier: typeIdentifier)
    }
}
