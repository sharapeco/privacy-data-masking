import ArgumentParser
import Foundation
import PDMaskCore

struct MaskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mask",
        abstract: "個人情報を黒塗りした画像を書き出す。"
    )

    @Option(help: "入力画像のパス。")
    var image: String

    @Option(help: "出力画像のパス（省略時は output/<元ファイル名>-masked.<拡張子>）。")
    var output: String?

    @Option(help: "検出結果 JSON の出力先（省略時は書き出さない）。")
    var report: String?

    @OptionGroup var detection: DetectionFlags

    func run() async throws {
        let outputPath = output ?? defaultOutputPath(for: image)
        guard URL(fileURLWithPath: outputPath).standardizedFileURL != URL(fileURLWithPath: image).standardizedFileURL else {
            throw PDMaskError("出力先が入力画像と同じです。元画像を上書きしないよう、別のパスを指定してください。")
        }

        let loaded = try ImageLoader.load(path: image)
        let result = try await DetectionPipeline.run(image: loaded, imagePath: image, options: detection.options)
        let redacted = try Redactor.redact(loaded, regions: result.regions)
        let type = Redactor.typeIdentifier(forOutput: outputPath, fallback: loaded.typeIdentifier)
        try Redactor.write(redacted, to: outputPath, typeIdentifier: type)

        if let report {
            try writeJSON(result, to: report, label: "detection report")
        }
        let summary = Dictionary(grouping: result.regions, by: \.category)
            .map { "\($0.key.rawValue)×\($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        FileHandle.standardError.write("Masked \(result.regions.count) regions (\(summary.isEmpty ? "none" : summary)) → \(outputPath)\n".data(using: .utf8)!)
    }

    private func defaultOutputPath(for input: String) -> String {
        let url = URL(fileURLWithPath: input)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        return "output/\(stem)-masked.\(ext)"
    }
}
