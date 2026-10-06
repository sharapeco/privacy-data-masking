import Foundation

public func writeJSON<T: Encodable>(_ value: T, to path: String?, label: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data: Data
    do {
        data = try encoder.encode(value)
    } catch {
        throw PDMaskError("Failed to encode output JSON: \(error)")
    }

    if let path {
        guard FileManager.default.createFile(atPath: path, contents: data) else {
            throw PDMaskError("Could not write output file at \(path)")
        }
        FileHandle.standardError.write("Wrote \(label) to \(path)\n".data(using: .utf8)!)
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
}
