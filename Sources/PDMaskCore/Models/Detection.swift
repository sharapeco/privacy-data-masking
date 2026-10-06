import CoreGraphics
import Vision

/// Normalized bounding box in Vision's coordinate system: origin at the
/// lower-left corner of the image, values in 0...1, y increasing upward.
public struct NormalizedBox: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: NormalizedRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midY: Double { y + height / 2 }

    /// Scales the box around its center (e.g. 1.3 = 30% larger), clamped to the image.
    public func scaled(by factor: Double) -> NormalizedBox {
        let newWidth = width * factor
        let newHeight = height * factor
        return NormalizedBox(
            x: x - (newWidth - width) / 2,
            y: y - (newHeight - height) / 2,
            width: newWidth,
            height: newHeight
        ).clamped()
    }

    /// Clips the box to the 0...1 image area.
    public func clamped() -> NormalizedBox {
        let left = min(max(minX, 0), 1)
        let right = min(max(maxX, 0), 1)
        let bottom = min(max(minY, 0), 1)
        let top = min(max(maxY, 0), 1)
        return NormalizedBox(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    public func union(_ other: NormalizedBox) -> NormalizedBox {
        let left = min(minX, other.minX)
        let bottom = min(minY, other.minY)
        return NormalizedBox(
            x: left,
            y: bottom,
            width: max(maxX, other.maxX) - left,
            height: max(maxY, other.maxY) - bottom
        )
    }

    /// Rectangle in pixel coordinates with a lower-left origin (matches CGContext).
    public func pixelRect(imageWidth: Int, imageHeight: Int) -> CGRect {
        CGRect(
            x: x * Double(imageWidth),
            y: y * Double(imageHeight),
            width: width * Double(imageWidth),
            height: height * Double(imageHeight)
        )
    }
}

public enum PIICategory: String, Codable, Sendable {
    case name
    case address
    case phone
    case email
    case postalCode
    case birthdate
    case cardNumber
    case myNumber
    /// Other personal ID numbers: membership, account, license numbers, partly masked numbers.
    case idNumber
    case face
    case barcode
}

/// Which detector found a region.
public enum DetectionSource: String, Codable, Sendable {
    case rule
    case llm
    case both
    case vision
}

public struct Region: Codable, Sendable {
    public var category: PIICategory
    public var source: DetectionSource
    /// Matched text for text regions; nil for faces and barcodes.
    public var text: String?
    /// Index into `DetectionReport.lines` for text regions.
    public var lineIndex: Int?
    public var box: NormalizedBox

    public init(category: PIICategory, source: DetectionSource, text: String? = nil, lineIndex: Int? = nil, box: NormalizedBox) {
        self.category = category
        self.source = source
        self.text = text
        self.lineIndex = lineIndex
        self.box = box
    }
}

public struct OCRLineInfo: Codable, Sendable {
    public var index: Int
    public var text: String
    public var box: NormalizedBox
}

public struct DetectionReport: Codable, Sendable {
    public var imagePath: String
    public var imageWidth: Int
    public var imageHeight: Int
    public var lines: [OCRLineInfo]
    public var regions: [Region]

    public init(imagePath: String, imageWidth: Int, imageHeight: Int, lines: [OCRLineInfo], regions: [Region]) {
        self.imagePath = imagePath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.lines = lines
        self.regions = regions
    }
}
