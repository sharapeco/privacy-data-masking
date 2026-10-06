import Foundation
import FoundationModels

/// Finds personal names and postal addresses in OCR lines with the on-device
/// language model. Formats that rules handle well (phone, email, ...) are left
/// to `PIIRules` so the model only has to make the judgment calls.
public enum PIIClassifier {
    /// The on-device model's context is about 4096 tokens shared by the
    /// instructions, the lines and the response, so long images are split.
    static let maxLinesPerChunk = 40
    static let maxCharactersPerChunk = 1500
    /// Lines repeated between chunks so a name and its furigana are not split apart.
    static let chunkOverlap = 2

    private static let instructions = """
        画像から読み取ったテキスト行が与えられます。各行の先頭の [番号] は行番号です。
        個人を特定できる「人名」と「住所」に当たる部分をすべて探してください。
        人名には、姓だけ・名だけの表記、ふりがな・ローマ字表記、敬称付きの名前（〇〇様）も含みます。住所には郵便番号や建物名・部屋番号も含みます。
        「氏名」「住所」のような項目名そのもの、政党名・選挙区・役職・組織名・会社名・店舗名・地名だけのもの・UI のボタンや見出しの文言は該当しません。
        text には該当行の文字列から該当部分だけをそのまま書き写してください。
        """

    /// Alternative wording tried once if the guardrails reject the first attempt.
    private static let fallbackInstructions = """
        あなたは画像の匿名化処理を手伝います。テキスト行が与えられるので、伏字にすべき箇所（人の名前と住所）を特定してください。
        各行の先頭の [番号] は行番号です。姓だけの名前、名前のふりがなや敬称付きの名前、郵便番号付きの住所も対象です。
        組織名・会社名・店舗名・政党名・地名だけのもの・ボタンの文言は対象外です。
        text には該当行の文字列から該当部分だけをそのまま書き写してください。
        """

    public static func classify(lines: [TextLine]) async throws -> [TextMatch] {
        guard !lines.isEmpty else { return [] }
        try FoundationModelsAvailability.requireAvailable()

        var matches: [TextMatch] = []
        for chunk in chunks(of: lines) {
            let findings = try await respond(to: chunk)
            matches += findings.compactMap { locate($0, in: lines, chunk: chunk) }
        }
        return matches
    }

    private static func respond(to chunk: ArraySlice<TextLine>) async throws -> [PIIFinding] {
        let prompt = chunk.map { "[\($0.index)] \($0.text)" }.joined(separator: "\n")
        do {
            return try await respond(prompt: prompt, instructions: instructions)
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            do {
                return try await respond(prompt: prompt, instructions: fallbackInstructions)
            } catch LanguageModelSession.GenerationError.guardrailViolation {
                throw PDMaskError("オンデバイスモデルの安全ガードレールにより判定が拒否されました。塗り漏れを防ぐため出力を中止します。")
            }
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw PDMaskError("テキストが長すぎてオンデバイスモデルの入力上限を超えました（行 \(chunk.first!.index)〜\(chunk.last!.index)）。")
        }
    }

    private static func respond(prompt: String, instructions: String) async throws -> [PIIFinding] {
        // A fresh session per chunk keeps earlier chunks out of the context window.
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(
            to: prompt,
            generating: PIIFindings.self,
            options: GenerationOptions(sampling: .greedy)
        ).content.findings
    }

    static func chunks(of lines: [TextLine]) -> [ArraySlice<TextLine>] {
        chunkRanges(lineLengths: lines.map(\.text.count)).map { lines[$0] }
    }

    /// Splits lines into consecutive ranges of at most `maxLinesPerChunk` lines and
    /// `maxCharactersPerChunk` characters (a single longer line gets its own chunk),
    /// with `chunkOverlap` lines repeated between neighboring chunks.
    static func chunkRanges(lineLengths: [Int]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        while start < lineLengths.count {
            var end = start
            var characters = 0
            while end < lineLengths.count,
                  end - start < maxLinesPerChunk,
                  end == start || characters + lineLengths[end] <= maxCharactersPerChunk {
                characters += lineLengths[end]
                end += 1
            }
            result.append(start..<end)
            if end >= lineLengths.count { break }
            start = max(end - chunkOverlap, start + 1)
        }
        return result
    }

    /// Turns a model finding into a range in the OCR text, guarding against
    /// hallucinations: the text must exist in the stated line, else in some other
    /// line of the chunk; if it exists nowhere, the whole stated line is masked
    /// (when that line is real), since over-masking is safer than leaking.
    private static func locate(_ finding: PIIFinding, in lines: [TextLine], chunk: ArraySlice<TextLine>) -> TextMatch? {
        let category: PIICategory = finding.kind == .name ? .name : .address
        if PIIRules.isLabel(finding.text) { return nil }

        if lines.indices.contains(finding.lineIndex),
           let range = NormalizedText(lines[finding.lineIndex].text).locate(finding.text) {
            return TextMatch(lineIndex: finding.lineIndex, range: range, category: category)
        }
        for line in chunk {
            if let range = NormalizedText(line.text).locate(finding.text) {
                return TextMatch(lineIndex: line.index, range: range, category: category)
            }
        }
        guard chunk.contains(where: { $0.index == finding.lineIndex }) else { return nil }
        let text = lines[finding.lineIndex].text
        return TextMatch(lineIndex: finding.lineIndex, range: text.startIndex..<text.endIndex, category: category)
    }
}
