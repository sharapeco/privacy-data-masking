import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum Redactor {
    /// Draws the image and fills every region with opaque black. Text regions get a
    /// small margin because OCR boxes hug the glyphs tightly.
    public static func redact(_ image: LoadedImage, regions: [Region]) throws -> CGImage {
        let width = image.width
        let height = image.height
        // Keep standard named spaces (sRGB, Display P3, ...); convert custom ICC
        // profiles to sRGB, since an embedded profile can name the device it came from.
        let colorSpace = image.cgImage.colorSpace.flatMap { $0.name != nil && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDMaskError("描画用のコンテキストを作成できません。")
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image.cgImage, in: fullRect)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for region in regions {
            let rect = region.box.pixelRect(imageWidth: width, imageHeight: height)
            let margin = padding(for: region, rect: rect)
            context.fill(rect.insetBy(dx: -margin, dy: -margin).intersection(fullRect))
        }

        guard let result = context.makeImage() else {
            throw PDMaskError("黒塗り画像を生成できません。")
        }
        return result
    }

    private static func padding(for region: Region, rect: CGRect) -> CGFloat {
        switch region.category {
        case .face:
            return 0  // already enlarged by DetectionOptions.faceScale
        case .barcode:
            return 4
        default:
            return max(2, rect.height * 0.15)
        }
    }

    /// Writes the image with no metadata (EXIF/GPS/TIFF/IPTC are not carried over;
    /// orientation is already baked into the pixels). Writes to a temporary file and
    /// moves it into place, so a failure never leaves a partial file at `path`.
    public static func write(_ image: CGImage, to path: String, typeIdentifier: String) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL, typeIdentifier as CFString, 1, nil
        ) else {
            throw PDMaskError("この形式では書き出せません: \(typeIdentifier)")
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PDMaskError("画像を書き出せません: \(path)")
        }

        do {
            if FileManager.default.fileExists(atPath: path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PDMaskError("画像を保存できません: \(path) (\(error.localizedDescription))")
        }
    }

    /// Output format: from the output file's extension when it names an image type,
    /// otherwise the input's format.
    public static func typeIdentifier(forOutput path: String, fallback: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return type.identifier
        }
        return fallback
    }
}
