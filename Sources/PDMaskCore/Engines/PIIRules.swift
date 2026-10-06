import Foundation

/// The minimum a rule needs to know about an OCR line: its text and where it sits.
public protocol RuleLine {
    var text: String { get }
    var box: NormalizedBox { get }
}

extension TextLine: RuleLine {}

/// A span of PII inside one OCR line.
public struct TextMatch: Hashable, Sendable {
    public var lineIndex: Int
    /// Range in the line's original (non-normalized) text.
    public var range: Range<String.Index>
    public var category: PIICategory

    public init(lineIndex: Int, range: Range<String.Index>, category: PIICategory) {
        self.lineIndex = lineIndex
        self.range = range
        self.category = category
    }
}

/// Rule-based PII detection: formats that can be recognized deterministically
/// (phone, email, postal code, birthdate, card number, My Number), plus backup
/// rules for names and addresses that catch what the LLM misses.
public enum PIIRules {

    /// Runs every rule that works on the OCR lines alone.
    public static func detect<L: RuleLine>(lines: [L]) -> [TextMatch] {
        let normalized = lines.map { NormalizedText($0.text) }
        var matches: [TextMatch] = []

        for (index, line) in normalized.enumerated() {
            matches += emails(in: line, lineIndex: index)
            matches += phones(in: line, lineIndex: index)
            matches += cardNumbers(in: line, lineIndex: index)
            matches += myNumbers(in: line, lineIndex: index)
            matches += maskedNumbers(in: line, lineIndex: index)
            matches += honorificNames(in: line, lineIndex: index)

            let addressMatches = addresses(in: line, lineIndex: index)
            matches += addressMatches
            matches += postalCodes(in: line, lineIndex: index, isAddressLine: !addressMatches.isEmpty)

            let context = birthdateContext(for: index, lines: lines)
            matches += birthdates(in: line, lineIndex: index, context: context)
        }
        matches += labeledValues(lines: lines, normalized: normalized)
        return matches
    }

    /// How far apart (in line heights) the vertical centers of two OCR boxes may be
    /// while still counting as the same row. Boxes shift a little with glyph shapes
    /// (descenders, small kana); a shift of 0.8 lines or more usually means another row.
    static let sameRowTolerance = 0.6

    /// Adds matches implied by already-detected names and addresses, from any source:
    /// the furigana printed above/below a name, address lines that continue onto the
    /// next line (building name, room number), and a postal-code-only line next to an address.
    public static func expand<L: RuleLine>(_ matches: [TextMatch], lines: [L]) -> [TextMatch] {
        var added: [TextMatch] = []

        let nameLines = Set(matches.filter { $0.category == .name }.map(\.lineIndex))
        for index in nameLines where !isKanaOnly(lines[index].text) {
            added += furigana(of: index, lines: lines).map { wholeLine($0, lines: lines, category: .name) }
        }

        var addressLines = Set(matches.filter { $0.category == .address }.map(\.lineIndex))
        for _ in 0..<2 {
            var next: Set<Int> = []
            for index in addressLines {
                guard let below = lineBelow(index, lines: lines),
                      !addressLines.contains(below),
                      abs(lines[below].box.minX - lines[index].box.minX) < 0.05,
                      case let text = NormalizedText(lines[below].text),
                      firstMatch(addressContinuationPattern, in: text.text) != nil,
                      phones(in: text, lineIndex: below).isEmpty,
                      emails(in: text, lineIndex: below).isEmpty
                else { continue }
                added.append(wholeLine(below, lines: lines, category: .address))
                next.insert(below)
            }
            if next.isEmpty { break }
            addressLines.formUnion(next)
        }

        for index in addressLines {
            for neighbor in [lineAbove(index, lines: lines), lineBelow(index, lines: lines)].compactMap({ $0 })
            where abs(lines[neighbor].box.minX - lines[index].box.minX) < 0.05
                && firstMatch(postalOnlyPattern, in: NormalizedText(lines[neighbor].text).text) != nil {
                added.append(wholeLine(neighbor, lines: lines, category: .postalCode))
            }
        }
        return added
    }

    /// The reading printed above or below a kanji name. It is often split into several
    /// boxes ("まつもと" "ひさし"), so after finding the closest kana-only line, every
    /// kana-only line on that same row over the name is included too.
    static func furigana<L: RuleLine>(of index: Int, lines: [L]) -> [Int] {
        let nameBox = lines[index].box
        func isCandidate(_ other: Int) -> Bool {
            other != index
                && isKanaOnly(lines[other].text)
                && !isLabel(lines[other].text)
                && horizontalOverlapRatio(nameBox, lines[other].box) >= 0.3
        }

        var result: [Int] = []
        for direction in [VerticalDirection.above, .below] {
            guard let anchor = verticalNeighbors(index, lines: lines, direction: direction)
                .filter({ isCandidate($0.index) })
                .min(by: { $0.gap < $1.gap })?
                .index
            else { continue }
            let anchorBox = lines[anchor].box
            result += lines.indices.filter { other in
                other == anchor || (isCandidate(other) && isSameRow(anchorBox, lines[other].box))
            }
        }
        return result
    }

    static func isSameRow(_ a: NormalizedBox, _ b: NormalizedBox) -> Bool {
        abs(a.midY - b.midY) < sameRowTolerance * max(a.height, b.height)
    }

    // MARK: - Format-based rules

    private static let emailPattern = regex(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"#)

    static func emails(in line: NormalizedText, lineIndex: Int) -> [TextMatch] {
        allMatches(emailPattern, in: line).map { TextMatch(lineIndex: lineIndex, range: $0, category: .email) }
    }

    // Domestic numbers start with 0, international ones with +81. Separators may be
    // hyphens, spaces or parentheses. The digit count is validated afterwards.
    private static let phonePattern = regex(#"(?<![\d-])(?:\+81[\s-]?\(?0?|\(?0)\d{1,4}\)?[\s-]?\d{1,4}[\s-]?\d{3,4}(?![\d-])"#)

    static func phones(in line: NormalizedText, lineIndex: Int) -> [TextMatch] {
        allMatches(phonePattern, in: line, mapToOriginal: false).compactMap { range in
            let digits = line.text[range].filter(\.isASCIIDigit)
            let valid: Bool
            if line.text[range].hasPrefix("+81") {
                let national = digits.dropFirst(2).drop(while: { $0 == "0" })
                valid = (9...10).contains(national.count)
            } else {
                valid = (10...11).contains(digits.count)
            }
            return valid ? TextMatch(lineIndex: lineIndex, range: line.originalRange(range), category: .phone) : nil
        }
    }

    private static let postalWithMarkPattern = regex(#"〒\s*\d{3}-?\d{4}(?!\d)"#)
    private static let postalBarePattern = regex(#"(?<![\d-])\d{3}-\d{4}(?![\d-])"#)
    private static let postalOnlyPattern = regex(#"^\s*〒?\s*\d{3}-\d{4}\s*$"#)

    static func postalCodes(in line: NormalizedText, lineIndex: Int, isAddressLine: Bool) -> [TextMatch] {
        var ranges = allMatches(postalWithMarkPattern, in: line)
        if isAddressLine || line.text.contains("郵便番号") {
            let marked = ranges
            ranges += allMatches(postalBarePattern, in: line).filter { bare in
                !marked.contains { $0.overlaps(bare) }
            }
        }
        return ranges.map { TextMatch(lineIndex: lineIndex, range: $0, category: .postalCode) }
    }

    private static let cardPattern = regex(#"(?<!\d)(?:\d[\s-]?){12,18}\d(?!\d)"#)

    static func cardNumbers(in line: NormalizedText, lineIndex: Int) -> [TextMatch] {
        allMatches(cardPattern, in: line, mapToOriginal: false).compactMap { range in
            let digits = line.text[range].compactMap(\.wholeNumberValue)
            guard (13...19).contains(digits.count), passesLuhn(digits) else { return nil }
            return TextMatch(lineIndex: lineIndex, range: line.originalRange(range), category: .cardNumber)
        }
    }

    static func passesLuhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    private static let myNumberPattern = regex(#"(?<!\d)(?<!\d[\s-])\d{4}[\s-]?\d{4}[\s-]?\d{4}(?![\s-]?\d)"#)

    static func myNumbers(in line: NormalizedText, lineIndex: Int) -> [TextMatch] {
        allMatches(myNumberPattern, in: line, mapToOriginal: false).compactMap { range in
            let digits = line.text[range].compactMap(\.wholeNumberValue)
            guard digits.count == 12, hasValidMyNumberCheckDigit(digits) else { return nil }
            return TextMatch(lineIndex: lineIndex, range: line.originalRange(range), category: .myNumber)
        }
    }

    /// Check digit of the Japanese individual number (マイナンバー), per the
    /// 総務省令 formula: weights 2..7 then 2..6 from the right of the first 11 digits.
    static func hasValidMyNumberCheckDigit(_ digits: [Int]) -> Bool {
        guard digits.count == 12 else { return false }
        let body = digits.prefix(11).reversed()
        var sum = 0
        for (offset, digit) in body.enumerated() {
            let n = offset + 1
            let weight = n <= 6 ? n + 1 : n - 5
            sum += digit * weight
        }
        let remainder = sum % 11
        let expected = remainder <= 1 ? 0 : 11 - remainder
        return digits[11] == expected
    }

    /// Digits and masking characters (after NFKC, "＊" is "*") separated by spaces or
    /// hyphens, e.g. "**** **** **** 4242", "090-****-5678", "XXXX-XXXX-1234".
    private static let maskedNumberPattern = regex(
        #"(?<![A-Za-z0-9*∗●•×])(?:[0-9*∗●•×Xx][\s-]?){7,}[0-9*∗●•×Xx](?![A-Za-z0-9*∗●•×])"#
    )
    private static let maskCharacters: Set<Character> = ["*", "∗", "●", "•", "×", "X", "x"]

    /// Numbers that are already partly masked still reveal part of a card, phone or ID
    /// number, so the whole value is blacked out. Classified by length: 13–19 positions
    /// is a card number, 10–11 starting with 0 is a phone number, anything else an ID.
    static func maskedNumbers(in line: NormalizedText, lineIndex: Int) -> [TextMatch] {
        allMatches(maskedNumberPattern, in: line, mapToOriginal: false).compactMap { range in
            let value = line.text[range]
            let masks = value.filter(maskCharacters.contains).count
            let digits = value.filter(\.isASCIIDigit).count
            guard masks >= 4, digits >= 2 else { return nil }

            let positions = masks + digits
            let category: PIICategory
            if (13...19).contains(positions) {
                category = .cardNumber
            } else if value.first == "0", (10...11).contains(positions) {
                category = .phone
            } else {
                category = .idNumber
            }
            return TextMatch(lineIndex: lineIndex, range: line.originalRange(range), category: category)
        }
    }

    private static let datePattern = regex(
        #"(?:(?:19|20)\d{2}|(?:明治|大正|昭和|平成|令和|[MTSHR])\s*(?:\d{1,2}|元))\s*(?:年|[/.-])\s*\d{1,2}\s*(?:月|[/.-])\s*\d{1,2}(?:\s*日)?(?:\s*生まれ|\s*生)?"#
    )
    private static let birthdateKeywordPattern = regex(#"生年月日|生まれ|誕生|DOB|birth|年齢|\d{1,3}\s*歳"#, caseInsensitive: true)
    private static let dateFollowedByBirthMarkPattern = regex(#"\d\s*日?\s*生"#)

    /// Dates are only treated as birthdates when a birth-related keyword is nearby;
    /// otherwise ordinary dates (e.g. "2026年1月" in a news citation) would be masked.
    static func birthdates(in line: NormalizedText, lineIndex: Int, context: [String]) -> [TextMatch] {
        let dates = allMatches(datePattern, in: line, mapToOriginal: false)
        guard !dates.isEmpty else { return [] }
        let hasKeyword = ([line.text] + context.map { NormalizedText($0).text })
            .contains { firstMatch(birthdateKeywordPattern, in: $0) != nil }
        return dates.compactMap { range in
            let selfMarked = firstMatch(dateFollowedByBirthMarkPattern, in: String(line.text[range])) != nil
            guard hasKeyword || selfMarked else { return nil }
            return TextMatch(lineIndex: lineIndex, range: line.originalRange(range), category: .birthdate)
        }
    }

    /// Text of the lines a birthdate label could sit on: the previous line in reading
    /// order, lines on the same row to the left, and the line directly above.
    private static func birthdateContext<L: RuleLine>(for index: Int, lines: [L]) -> [String] {
        var indices = sameRowLeft(index, lines: lines)
        if index > 0 { indices.append(index - 1) }
        if let above = lineAbove(index, lines: lines) { indices.append(above) }
        return Set(indices).map { lines[$0].text }
    }

    // MARK: - Backup rules for names and addresses

    private static let nameLabelPattern = regex(
        #"^\s*(氏名|お名前|名前|ご氏名|フリガナ|ふりがな|Name|NAME|担当者?|記入者|申請者|代表者|契約者|名義人?|受取人|差出人|宛名)(?![様殿各のはがをにへともで欄者人])\s*[:：]?\s*"#
    )
    private static let addressLabelPattern = regex(
        #"^\s*(住所|ご住所|現住所|所在地|お届け先|送付先|送り先)(?![様殿各のはがをにへともで欄者人])\s*[:：]?\s*"#
    )
    private static let cardLabelPattern = regex(
        #"^\s*(カード番号|クレジットカード番号|クレジットカード|カードNo\.?)(?![様殿各のはがをにへともで欄者人])\s*[:：]?\s*"#
    )
    private static let idLabelPattern = regex(
        #"^\s*(口座番号|会員番号|会員ID|顧客番号|お客様番号|個人番号|マイナンバー|免許証番号|保険証番号|被保険者番号|パスポート番号|旅券番号)(?![様殿各のはがをにへともで欄者人])\s*[:：]?\s*"#
    )
    private static let labelPatterns: [(NSRegularExpression, PIICategory)] = [
        (nameLabelPattern, .name),
        (addressLabelPattern, .address),
        (cardLabelPattern, .cardNumber),
        (idLabelPattern, .idNumber),
    ]

    /// Values following a label (name, address, card or ID number), either on the same
    /// line ("氏名：山田花子") or in separate boxes to the right of / below a bare label.
    static func labeledValues<L: RuleLine>(lines: [L], normalized: [NormalizedText]) -> [TextMatch] {
        var matches: [TextMatch] = []
        for (index, line) in normalized.enumerated() {
            for (pattern, category) in labelPatterns {
                guard let label = firstMatch(pattern, in: line.text) else { continue }
                let rest = label.upperBound..<line.text.endIndex
                if !line.text[rest].trimmingCharacters(in: .whitespaces).isEmpty {
                    matches.append(TextMatch(lineIndex: index, range: line.originalRange(rest), category: category))
                    continue
                }
                var values = valuesRightOf(label: index, lines: lines)
                if values.isEmpty, let below = lineBelow(index, lines: lines) {
                    values = [below]
                }
                matches += values.map { wholeLine($0, lines: lines, category: category) }
            }
        }
        return matches
    }

    /// The value boxes of a bare label in a table layout. Every line left-aligned with
    /// the label is treated as a row header; each box to the right is assigned to the
    /// header whose vertical center is closest (ties go to the upper header, since in
    /// top-aligned tables continuation lines sit below their label). This handles a
    /// label centered beside a two-line value, like 住所 next to postal code + address.
    static func valuesRightOf<L: RuleLine>(label index: Int, lines: [L]) -> [Int] {
        let label = lines[index].box
        let headers = lines.indices.filter { abs(lines[$0].box.minX - label.minX) <= 0.02 }

        func nearestHeader(to midY: Double) -> Int? {
            headers.min { a, b in
                let distanceA = abs(lines[a].box.midY - midY)
                let distanceB = abs(lines[b].box.midY - midY)
                if abs(distanceA - distanceB) > 1e-3 { return distanceA < distanceB }
                return lines[a].box.midY > lines[b].box.midY
            }
        }

        let assigned = lines.indices.filter { other in
            let box = lines[other].box
            return other != index
                && box.minX >= label.maxX - 0.01
                && abs(box.midY - label.midY) <= 2 * label.height
                && nearestHeader(to: box.midY) == index
        }
        // Only the nearest column of values, not further cells on the same row.
        guard let column = assigned.map({ lines[$0].box.minX }).min() else { return [] }
        return assigned.filter { lines[$0].box.minX <= column + 0.03 }
    }

    private static let kanji = "一-龯々〆ヵヶ"
    private static let honorificSamaPattern = regex(#"([\#(kanji)]{1,6})\s*(?:様|殿(?![堂下方様]))"#)
    private static let honorificSanPattern = regex(#"([\#(kanji)]{1,6}|[ァ-ヺー]{2,8})\s*(?:さん|くん|ちゃん|君)"#)

    /// Words that end right before an honorific but are not names (仕様, お客様, 宮殿, 店長さん...).
    private static let samaNonNamePrefixes: Set<String> = [
        "仕", "同", "模", "多", "異", "一", "王", "神", "仏", "殿", "皆", "貴", "有", "左", "文", "紋",
        "客", "奥", "子", "疲", "労", "話", "走", "傷", "陰", "互", "得意", "家族", "会員", "担当", "担当者", "利用者", "関係者"
    ]
    private static let donoNonNamePrefixes: Set<String> = ["御", "宮", "神", "本", "拝", "仏", "湯", "寝", "社", "沈", "貴", "大"]
    private static let sanNonNameWords: Set<String> = [
        "皆", "奥", "父", "母", "兄", "姉", "弟", "妹", "叔父", "叔母", "伯父", "伯母", "祖父", "祖母",
        "爺", "婆", "坊", "嬢", "娘", "息子", "赤", "大家", "隣", "パパ", "ママ", "サンタ"
    ]
    private static let sanNonNameSuffixes: Set<Character> = ["長", "員", "者", "師", "手", "屋", "士", "官"]

    static func honorificNames(in line: NormalizedText, lineIndex: Int) -> [TextMatch] {
        var matches: [TextMatch] = []
        let ns = line.text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        for result in honorificSamaPattern.matches(in: line.text, range: fullRange) {
            guard let range = Range(result.range(at: 1), in: line.text) else { continue }
            let name = String(line.text[range])
            let isDono = ns.substring(with: result.range).hasSuffix("殿")
            let stoplist = isDono ? donoNonNamePrefixes : samaNonNamePrefixes
            if stoplist.contains(where: { name.hasSuffix($0) }) { continue }
            matches.append(TextMatch(lineIndex: lineIndex, range: line.originalRange(range), category: .name))
        }

        for result in honorificSanPattern.matches(in: line.text, range: fullRange) {
            guard let range = Range(result.range(at: 1), in: line.text) else { continue }
            let name = String(line.text[range])
            if sanNonNameWords.contains(name) || name.last.map(sanNonNameSuffixes.contains) == true { continue }
            matches.append(TextMatch(lineIndex: lineIndex, range: line.originalRange(range), category: .name))
        }
        return matches
    }

    private static let prefectures = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県",
        "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
        "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
        "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県",
        "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
    ]
    private static let addressShapePattern = regex(
        #"[\#(kanji)ぁ-んァ-ヺー]{1,8}?(?:市|区|町|村|郡).*?(?:\d+\s*(?:丁目|番地?|号)|\d+-\d+|[一二三四五六七八九十]+丁目)"#
    )
    private static let addressContinuationPattern = regex(
        #"号室|\d+\s*号|\d+\s*階|\d+F\b|ビル|マンション|ハイツ|コーポ|アパート|レジデンス|荘|棟|号館"#
    )

    /// A line starting with 〒, or containing "municipality + block number"
    /// (a bare prefecture name such as "千葉13" is not an address). Covers from the
    /// start of the address to the end of the line, so building names are included.
    static func addresses(in line: NormalizedText, lineIndex: Int) -> [TextMatch] {
        let text = line.text
        var start: String.Index?
        if let postal = text.firstIndex(of: "〒"),
           text[..<postal].allSatisfy({ $0.isWhitespace }) {
            start = postal
        } else if let shape = firstMatch(addressShapePattern, in: text) {
            // The lazy match may start a few characters early ("担当者住所東京都…");
            // snap to the prefecture name when one is inside the match.
            let prefectureStart = prefectures
                .compactMap { text.range(of: $0, range: shape)?.lowerBound }
                .min()
            start = prefectureStart ?? shape.lowerBound
        }
        guard let start else { return [] }
        return [TextMatch(lineIndex: lineIndex, range: line.originalRange(start..<text.endIndex), category: .address)]
    }

    // MARK: - Geometry helpers

    private static func verticalOverlapRatio(_ a: NormalizedBox, _ b: NormalizedBox) -> Double {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return max(overlap, 0) / max(min(a.height, b.height), .ulpOfOne)
    }

    static func horizontalOverlapRatio(_ a: NormalizedBox, _ b: NormalizedBox) -> Double {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return max(overlap, 0) / max(min(a.width, b.width), .ulpOfOne)
    }

    private static func sameRowLeft<L: RuleLine>(_ index: Int, lines: [L]) -> [Int] {
        let box = lines[index].box
        return lines.indices.filter { other in
            other != index
                && verticalOverlapRatio(box, lines[other].box) > 0.5
                && lines[other].box.maxX <= box.minX + 0.01
        }
    }


    enum VerticalDirection {
        case above
        case below
    }

    /// The nearest line directly above (Vision's y grows upward), horizontally
    /// overlapping and within 1.5 line heights.
    static func lineAbove<L: RuleLine>(_ index: Int, lines: [L]) -> Int? {
        verticalNeighbors(index, lines: lines, direction: .above).min { $0.gap < $1.gap }?.index
    }

    static func lineBelow<L: RuleLine>(_ index: Int, lines: [L]) -> Int? {
        verticalNeighbors(index, lines: lines, direction: .below).min { $0.gap < $1.gap }?.index
    }

    /// Lines just above or below, horizontally overlapping and within 1.5 line heights,
    /// with the vertical gap between the boxes.
    static func verticalNeighbors<L: RuleLine>(
        _ index: Int,
        lines: [L],
        direction: VerticalDirection
    ) -> [(index: Int, gap: Double)] {
        let box = lines[index].box
        return lines.indices.compactMap { other in
            guard other != index else { return nil }
            let otherBox = lines[other].box
            let gap = direction == .above ? otherBox.minY - box.maxY : box.minY - otherBox.maxY
            let tolerance = -0.25 * min(box.height, otherBox.height)
            guard gap >= tolerance,
                  gap <= 1.5 * max(box.height, otherBox.height),
                  horizontalOverlapRatio(box, otherBox) > 0
            else { return nil }
            return (other, gap)
        }
    }

    // MARK: - Text helpers

    /// Form labels that are never PII themselves. The LLM occasionally returns the
    /// label "氏名" as a name; these are dropped.
    private static let labelWords: Set<String> = [
        "氏名", "名前", "お名前", "ご氏名", "フリガナ", "ふりがな", "なまえ", "Name", "NAME", "name",
        "住所", "ご住所", "現住所", "所在地", "お届け先", "送付先", "送り先", "生年月日", "電話", "電話番号",
        "TEL", "Tel", "メール", "メールアドレス", "Email", "E-mail", "担当", "担当者", "郵便番号", "宛名",
        "カード番号", "クレジットカード", "クレジットカード番号", "口座番号", "会員番号", "会員ID", "顧客番号",
        "お客様番号", "個人番号", "マイナンバー", "免許証番号", "保険証番号", "被保険者番号", "パスポート番号", "旅券番号"
    ]

    static func isLabel(_ text: String) -> Bool {
        let trimmed = NormalizedText(text).text
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":：")))
        return labelWords.contains(trimmed)
    }

    static func isKanaOnly(_ text: String) -> Bool {
        let chars = NormalizedText(text).text.filter { !$0.isWhitespace }
        guard chars.count >= 2 else { return false }
        return chars.unicodeScalars.allSatisfy { scalar in
            (0x3041...0x309F).contains(scalar.value)     // hiragana
                || (0x30A0...0x30FF).contains(scalar.value) // katakana, ー, ・
        }
    }

    private static func wholeLine<L: RuleLine>(_ index: Int, lines: [L], category: PIICategory) -> TextMatch {
        let text = lines[index].text
        return TextMatch(lineIndex: index, range: text.startIndex..<text.endIndex, category: category)
    }

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    /// All matches of `pattern` in the normalized text, as ranges in the
    /// original text (or in the normalized text when `mapToOriginal` is false).
    private static func allMatches(
        _ pattern: NSRegularExpression,
        in line: NormalizedText,
        mapToOriginal: Bool = true
    ) -> [Range<String.Index>] {
        let text = line.text
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            return mapToOriginal ? line.originalRange(range) : range
        }
    }

    private static func firstMatch(_ pattern: NSRegularExpression, in text: String) -> Range<String.Index>? {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .flatMap { Range($0.range, in: text) }
    }
}
