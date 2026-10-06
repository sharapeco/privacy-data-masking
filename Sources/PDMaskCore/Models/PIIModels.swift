import FoundationModels

@Generable
enum PIIKind: String, Codable {
    case name
    case address
}

@Generable
struct PIIFinding: Codable {
    @Guide(description: "The number shown in brackets at the start of the line, e.g. 3 for [3]")
    var lineIndex: Int

    @Guide(description: "name for a person's name (including its furigana or romanized reading), address for a postal address")
    var kind: PIIKind

    @Guide(description: "The exact part of that line that is the name or address, copied character for character")
    var text: String
}

@Generable
struct PIIFindings: Codable {
    @Guide(description: "Every person's name and postal address found in the lines. Empty if there are none")
    var findings: [PIIFinding]
}
