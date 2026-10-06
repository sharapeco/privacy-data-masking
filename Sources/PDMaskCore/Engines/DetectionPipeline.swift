import Foundation

public struct DetectionOptions: Sendable {
    public var detectFaces = true
    public var detectBarcodes = true
    public var faceScale = 1.3

    public init() {}
}

/// OCR → rules + LLM → regions, plus faces and barcodes. Any failure throws, so a
/// caller never gets a partial result that looks complete.
public enum DetectionPipeline {
    public static func run(image: LoadedImage, imagePath: String, options: DetectionOptions) async throws -> DetectionReport {
        let lines = try await TextDetector.detect(in: image.cgImage)

        let ruleMatches = PIIRules.detect(lines: lines)
        let llmMatches = try await PIIClassifier.classify(lines: lines)
        let expanded = PIIRules.expand(ruleMatches + llmMatches, lines: lines)

        var regions = textRegions(rule: ruleMatches + expanded, llm: llmMatches, lines: lines)
        if options.detectFaces {
            regions += try await FaceDetector.detect(in: image.cgImage, scale: options.faceScale)
                .map { Region(category: .face, source: .vision, box: $0) }
        }
        if options.detectBarcodes {
            regions += try await BarcodeDetector.detect(in: image.cgImage)
                .map { Region(category: .barcode, source: .vision, box: $0) }
        }

        return DetectionReport(
            imagePath: imagePath,
            imageWidth: image.width,
            imageHeight: image.height,
            lines: lines.map(\.info),
            regions: regions
        )
    }

    /// Unions rule and LLM matches. A match found by both (same line and category,
    /// overlapping ranges) is reported once per distinct range with source `both`.
    static func textRegions(rule: [TextMatch], llm: [TextMatch], lines: [TextLine]) -> [Region] {
        func overlaps(_ a: TextMatch, _ b: TextMatch) -> Bool {
            a.lineIndex == b.lineIndex && a.category == b.category && a.range.overlaps(b.range)
        }

        var tagged: [(TextMatch, DetectionSource)] = []
        for match in Set(rule) {
            tagged.append((match, llm.contains { overlaps($0, match) } ? .both : .rule))
        }
        for match in Set(llm) where !rule.contains(where: { $0 == match }) {
            tagged.append((match, rule.contains { overlaps($0, match) } ? .both : .llm))
        }

        return tagged
            .sorted {
                ($0.0.lineIndex, $0.0.range.lowerBound, $0.0.range.upperBound, $0.0.category.rawValue)
                    < ($1.0.lineIndex, $1.0.range.lowerBound, $1.0.range.upperBound, $1.0.category.rawValue)
            }
            .map { match, source in
                let line = lines[match.lineIndex]
                return Region(
                    category: match.category,
                    source: source,
                    text: String(line.text[match.range]),
                    lineIndex: match.lineIndex,
                    box: box(for: match.range, in: line)
                )
            }
    }

    /// Box of a substring, falling back to the whole line when Vision cannot
    /// locate it or returns a box that strays outside the line (over-masking is safe).
    static func box(for range: Range<String.Index>, in line: TextLine) -> NormalizedBox {
        let wholeLine = line.text.startIndex..<line.text.endIndex
        guard range != wholeLine, let box = line.box(for: range) else { return line.box }

        let slack = line.box.height * 0.5
        let isInsideLine = box.minX >= line.box.minX - slack
            && box.maxX <= line.box.maxX + slack
            && box.minY >= line.box.minY - slack
            && box.maxY <= line.box.maxY + slack
        return isInsideLine ? box : line.box
    }
}
