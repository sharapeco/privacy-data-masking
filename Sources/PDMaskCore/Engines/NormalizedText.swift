import Foundation

/// A line of OCR text normalized for matching (NFKC, dash variants unified),
/// keeping a map back to character positions in the original string so that
/// matches found on the normalized form can be located in the original.
struct NormalizedText {
    let original: String
    let text: String
    /// For each Character of `text`, the index of the original Character it came from.
    private let sourceIndices: [String.Index]

    private static let dashVariants: Set<Character> = ["‐", "‑", "‒", "–", "—", "―", "−", "－", "﹣"]
    private static let longVowelMarks: Set<Character> = ["ー", "ｰ"]

    init(_ original: String) {
        self.original = original
        var text = ""
        var sourceIndices: [String.Index] = []
        for index in original.indices {
            let character = original[index]
            var normalized = String(character).precomposedStringWithCompatibilityMapping
            if Self.dashVariants.contains(character) {
                normalized = "-"
            } else if Self.longVowelMarks.contains(character), text.last?.isASCIIDigit == true {
                // OCR often reads the hyphen in "090-1234" as the katakana long vowel mark.
                normalized = "-"
            }
            let countBefore = text.count
            text += normalized
            // Combining marks (e.g. a half-width dakuten) can merge into the previous
            // Character, in which case nothing new is appended to the map.
            let added = text.count - countBefore
            sourceIndices.append(contentsOf: repeatElement(index, count: max(added, 0)))
        }
        self.text = text
        self.sourceIndices = sourceIndices
    }

    /// Maps a range in `text` back to the corresponding range in `original`.
    func originalRange(_ range: Range<String.Index>) -> Range<String.Index> {
        let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let endOffset = text.distance(from: text.startIndex, to: range.upperBound)
        return originalRange(offsets: startOffset..<endOffset)
    }

    /// Maps a range of Character offsets in `text` back to a range in `original`.
    func originalRange(offsets: Range<Int>) -> Range<String.Index> {
        guard !sourceIndices.isEmpty, offsets.lowerBound < sourceIndices.count else {
            return original.endIndex..<original.endIndex
        }
        let start = sourceIndices[offsets.lowerBound]
        let end: String.Index
        if offsets.upperBound >= sourceIndices.count {
            end = original.endIndex
        } else if offsets.upperBound > 0,
                  sourceIndices[offsets.upperBound] == sourceIndices[offsets.upperBound - 1] {
            // The match ends in the middle of one original character's expansion
            // (e.g. "㈱" -> "(株)"); include that whole character.
            end = original.index(after: sourceIndices[offsets.upperBound])
        } else {
            end = sourceIndices[offsets.upperBound]
        }
        return start..<max(start, end)
    }

    /// Finds `needle` in this text ignoring whitespace and NFKC differences
    /// (OCR may read "松本　尚" as "松本尚"). Returns the range in `original`.
    func locate(_ needle: String) -> Range<String.Index>? {
        let needleChars = Array(NormalizedText(needle).text.filter { !$0.isWhitespace })
        guard !needleChars.isEmpty else { return nil }

        // Non-whitespace characters of `text` with their Character offsets.
        let haystack = text.enumerated().filter { !$0.element.isWhitespace }
        guard haystack.count >= needleChars.count else { return nil }

        for start in 0...(haystack.count - needleChars.count) {
            var matched = true
            for offset in 0..<needleChars.count where haystack[start + offset].element != needleChars[offset] {
                matched = false
                break
            }
            if matched {
                let first = haystack[start].offset
                let last = haystack[start + needleChars.count - 1].offset
                return originalRange(offsets: first..<(last + 1))
            }
        }
        return nil
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
