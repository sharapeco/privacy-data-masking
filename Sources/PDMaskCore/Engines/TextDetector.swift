import CoreGraphics
import Vision

public struct TextLine: Sendable {
    public var index: Int
    public var text: String
    public var box: NormalizedBox
    var recognized: RecognizedText

    public var info: OCRLineInfo {
        OCRLineInfo(index: index, text: text, box: box)
    }

    /// Bounding box of a substring of `text`, or nil if Vision cannot locate it.
    public func box(for range: Range<String.Index>) -> NormalizedBox? {
        guard let observation = recognized.boundingBox(for: range) else { return nil }
        let rect = observation.boundingBox
        guard rect.width > 0, rect.height > 0 else { return nil }
        return NormalizedBox(rect)
    }
}

public enum TextDetector {
    public static func detect(in image: CGImage) async throws -> [TextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(languageCode: "ja"), Locale.Language(languageCode: "en")]
        request.recognitionLevel = .accurate

        let observations = try await ImageRequestHandler(image).perform(request)

        var lines: [TextLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            lines.append(TextLine(
                index: lines.count,
                text: candidate.string,
                box: NormalizedBox(observation.boundingBox),
                recognized: candidate
            ))
        }
        return lines
    }
}
