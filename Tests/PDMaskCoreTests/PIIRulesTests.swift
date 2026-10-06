import Testing
@testable import PDMaskCore

struct TestLine: RuleLine {
    var text: String
    var box: NormalizedBox

    /// A line at the given row (0 = top), stacked with a fixed line height.
    init(_ text: String, row: Int = 0, x: Double = 0.1, width: Double = 0.6, height: Double = 0.03) {
        self.text = text
        self.box = NormalizedBox(x: x, y: 0.9 - Double(row) * height * 1.5, width: width, height: height)
    }

    init(_ text: String, box: NormalizedBox) {
        self.text = text
        self.box = box
    }
}

/// Matched substrings of each line, as (category, text) pairs.
private func detected(_ lines: [TestLine]) -> [(PIICategory, String)] {
    PIIRules.detect(lines: lines).map { ($0.category, String(lines[$0.lineIndex].text[$0.range])) }
}

private func detected(_ text: String) -> [(PIICategory, String)] {
    detected([TestLine(text)])
}

private func contains(_ results: [(PIICategory, String)], _ category: PIICategory, _ text: String) -> Bool {
    results.contains { $0.0 == category && $0.1 == text }
}

@Suite struct FormatRules {
    @Test(arguments: [
        ("TEL 090-1234-5678", "090-1234-5678"),
        ("電話：03-1234-5678", "03-1234-5678"),
        ("(03)1234-5678", "(03)1234-5678"),
        ("0120-123-456", "0120-123-456"),
        ("09012345678", "09012345678"),
        ("+81 90-1234-5678", "+81 90-1234-5678"),
        ("ＴＥＬ ０９０－１２３４－５６７８", "０９０－１２３４－５６７８"),
        ("090ー1234ー5678", "090ー1234ー5678"),
    ])
    func phone(text: String, expected: String) {
        #expect(contains(detected(text), .phone, expected))
    }

    @Test(arguments: ["0120", "2026年1月", "千葉13", "1234", "注文番号 12345"])
    func notPhone(text: String) {
        #expect(!detected(text).contains { $0.0 == .phone })
    }

    @Test func email() {
        #expect(contains(detected("mail: hanako.yamada@example.co.jp"), .email, "hanako.yamada@example.co.jp"))
    }

    @Test(arguments: [
        ("〒100-0001", "〒100-0001"),
        ("〒 260-0013 千葉県千葉市中央区中央4丁目5-1", "〒 260-0013"),
        ("郵便番号 100-0001", "100-0001"),
    ])
    func postalCode(text: String, expected: String) {
        #expect(contains(detected(text), .postalCode, expected))
    }

    @Test func barePostalCodeOutsideAddressIsIgnored() {
        #expect(!detected("品番 123-4567").contains { $0.0 == .postalCode })
    }

    @Test func cardNumber() {
        #expect(contains(detected("カード 4111 1111 1111 1111"), .cardNumber, "4111 1111 1111 1111"))
        #expect(!detected("4111 1111 1111 1112").contains { $0.0 == .cardNumber })
    }

    @Test func myNumber() {
        #expect(contains(detected("個人番号 1234 5678 9018"), .myNumber, "1234 5678 9018"))
        #expect(!detected("1234 5678 9017").contains { $0.0 == .myNumber })
    }
}

@Suite struct BirthdateRules {
    @Test(arguments: [
        ("生年月日 1990年1月1日", "1990年1月1日"),
        ("1990年1月1日生", "1990年1月1日生"),
        ("昭和62年4月5日生まれ", "昭和62年4月5日生まれ"),
        ("DOB: 1990/01/31", "1990/01/31"),
        ("H2.1.8 (35歳)", "H2.1.8"),
        ("生年月日 １９９０年１月１日", "１９９０年１月１日"),
    ])
    func sameLine(text: String, expected: String) {
        #expect(contains(detected(text), .birthdate, expected))
    }

    @Test func labelOnPreviousLine() {
        let lines = [TestLine("生年月日", row: 0), TestLine("1990年1月1日", row: 1)]
        #expect(contains(detected(lines), .birthdate, "1990年1月1日"))
    }

    @Test func labelOnSameRowToTheLeft() {
        let lines = [
            TestLine("1990年1月1日", box: NormalizedBox(x: 0.4, y: 0.5, width: 0.3, height: 0.03)),
            TestLine("生年月日", box: NormalizedBox(x: 0.1, y: 0.5, width: 0.2, height: 0.03)),
        ]
        #expect(contains(detected(lines), .birthdate, "1990年1月1日"))
    }

    @Test(arguments: [
        "「非核三原則を見直すべき」（２０２６年１月、ＮＨＫアンケート）",
        "発行日 2024年4月1日",
        "2026/10/06 更新",
    ])
    func ordinaryDatesAreNotBirthdates(text: String) {
        #expect(!detected(text).contains { $0.0 == .birthdate })
    }
}

@Suite struct NameAndAddressRules {
    @Test(arguments: [
        ("氏名：山田花子", "山田花子"),
        ("お名前 山田 花子", "山田 花子"),
        ("フリガナ ヤマダ ハナコ", "ヤマダ ハナコ"),
    ])
    func labeledName(text: String, expected: String) {
        #expect(contains(detected(text), .name, expected))
    }

    @Test func bareLabelUsesValueToTheRight() {
        let lines = [
            TestLine("氏名", box: NormalizedBox(x: 0.1, y: 0.5, width: 0.1, height: 0.03)),
            TestLine("山田花子", box: NormalizedBox(x: 0.3, y: 0.5, width: 0.2, height: 0.03)),
        ]
        #expect(contains(detected(lines), .name, "山田花子"))
    }

    @Test func bareLabelUsesValueBelow() {
        let lines = [TestLine("住所", row: 0), TestLine("どこかの場所", row: 1)]
        #expect(contains(detected(lines), .address, "どこかの場所"))
    }

    @Test(arguments: [
        ("山田様", "山田"),
        ("田中太郎 様", "田中太郎"),
        ("佐藤さん", "佐藤"),
        ("林殿", "林"),
        ("ジョンさん", "ジョン"),
    ])
    func honorific(text: String, expected: String) {
        #expect(contains(detected(text), .name, expected))
    }

    @Test(arguments: ["お客様", "仕様書", "同様に", "皆様へ", "お疲れ様です", "宮殿", "殿堂入り", "店長さん", "お母さん", "担当者様"])
    func notHonorificName(text: String) {
        #expect(!detected(text).contains { $0.0 == .name })
    }

    @Test(arguments: [
        ("〒260-0013 千葉県千葉市中央区中央4丁目5-1", "〒260-0013 千葉県千葉市中央区中央4丁目5-1"),
        ("お届け先：千葉県千葉市中央区中央4丁目5-1 グランドハイツ302号室", "千葉県千葉市中央区中央4丁目5-1 グランドハイツ302号室"),
        ("東京都千代田区千代田1-1", "東京都千代田区千代田1-1"),
        ("港区六本木6-10-1", "港区六本木6-10-1"),
    ])
    func address(text: String, expected: String) {
        #expect(contains(detected(text), .address, expected))
    }

    @Test(arguments: ["千葉13", "自民", "衆議院", "千葉市中央区", "千葉駅前店"])
    func notAddress(text: String) {
        #expect(!detected(text).contains { $0.0 == .address })
    }
}

@Suite struct Expansion {
    @Test func furiganaBelowKanjiName() {
        // Same geometry as the test screenshot: name, then smaller reading below it.
        let lines = [
            TestLine("松本尚", box: NormalizedBox(x: 0.05, y: 0.95, width: 0.229, height: 0.03)),
            TestLine("まつもとひさし", box: NormalizedBox(x: 0.054, y: 0.919, width: 0.266, height: 0.019)),
            TestLine("シェアする", box: NormalizedBox(x: 0.062, y: 0.868, width: 0.129, height: 0.015)),
        ]
        let name = TextMatch(lineIndex: 0, range: lines[0].text.startIndex..<lines[0].text.endIndex, category: .name)
        let added = PIIRules.expand([name], lines: lines)
        #expect(added.map(\.lineIndex) == [1])
        #expect(added.first?.category == .name)
    }

    @Test func kanaNameDoesNotPullInNeighbors() {
        let lines = [TestLine("やまだ", row: 0), TestLine("はなこ", row: 1)]
        let name = TextMatch(lineIndex: 0, range: lines[0].text.startIndex..<lines[0].text.endIndex, category: .name)
        #expect(PIIRules.expand([name], lines: lines).isEmpty)
    }

    @Test func addressContinuesOntoBuildingLine() {
        let lines = [
            TestLine("東京都千代田区千代田1-1", row: 0),
            TestLine("サンプルマンション302号室", row: 1),
            TestLine("ご注文ありがとうございます", row: 2),
        ]
        let address = TextMatch(lineIndex: 0, range: lines[0].text.startIndex..<lines[0].text.endIndex, category: .address)
        let added = PIIRules.expand([address], lines: lines)
        #expect(added.map(\.lineIndex) == [1])
    }
}

@Suite struct NormalizedTextTests {
    @Test func locateIgnoresWhitespace() {
        let line = NormalizedText("松本尚")
        let range = line.locate("松本　尚")
        #expect(range.map { String(line.original[$0]) } == "松本尚")
    }

    @Test func locateAcrossFullWidth() {
        let line = NormalizedText("TEL ０９０-１２３４")
        let range = line.locate("090-1234")
        #expect(range.map { String(line.original[$0]) } == "０９０-１２３４")
    }

    @Test func locateMissingReturnsNil() {
        #expect(NormalizedText("自民").locate("松本") == nil)
    }
}

@Suite struct BoxTests {
    @Test func scaledIsClampedToImage() {
        let box = NormalizedBox(x: 0.9, y: 0.0, width: 0.2, height: 0.2).scaled(by: 1.5)
        #expect(box.minX >= 0 && box.maxX <= 1 && box.minY >= 0 && box.maxY <= 1)
    }

    @Test func scaledGrowsAroundCenter() {
        let box = NormalizedBox(x: 0.4, y: 0.4, width: 0.2, height: 0.2).scaled(by: 1.5)
        #expect(abs(box.x - 0.35) < 1e-9 && abs(box.width - 0.3) < 1e-9)
    }
}

@Suite struct Regressions {
    @Test func cardNumberIsNotAlsoMyNumber() {
        #expect(!detected("4111 1111 1111 1111").contains { $0.0 == .myNumber })
    }

    @Test func postalCodeReportedOnce() {
        let postal = detected("〒100-0001 東京都千代田区千代田1-1").filter { $0.0 == .postalCode }
        #expect(postal.map(\.1) == ["〒100-0001"])
    }

    @Test func phoneBelowAddressIsNotAddressContinuation() {
        let lines = [
            TestLine("サンプルマンション302号室", row: 0),
            TestLine("090-1234-5678", row: 1),
        ]
        let address = TextMatch(lineIndex: 0, range: lines[0].text.startIndex..<lines[0].text.endIndex, category: .address)
        #expect(PIIRules.expand([address], lines: lines).isEmpty)
    }

    @Test func furiganaLabelIsNotFurigana() {
        let lines = [TestLine("氏名", row: 0, width: 0.1), TestLine("ふりがな", row: 1, width: 0.15)]
        let name = TextMatch(lineIndex: 0, range: lines[0].text.startIndex..<lines[0].text.endIndex, category: .name)
        #expect(PIIRules.expand([name], lines: lines).isEmpty)
    }

    @Test func staffLabel() {
        #expect(contains(detected("担当 佐藤"), .name, "佐藤"))
    }

    @Test(arguments: ["氏名", "氏名：", "ふりがな", " 住所 "])
    func labelsAreRecognized(text: String) {
        #expect(PIIRules.isLabel(text))
    }
}
