import ArgumentParser
import Foundation
import PDMaskCore

struct DetectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "detect",
        abstract: "個人情報の検出結果を JSON で出力する（画像は書き換えない）。"
    )

    @Option(help: "入力画像のパス。")
    var image: String

    @Option(help: "JSON の出力先（省略時は stdout）。")
    var output: String?

    func run() async throws {
        let loaded = try ImageLoader.load(path: image)
        let lines = try await TextDetector.detect(in: loaded.cgImage)
        let report = DetectionReport(
            imagePath: image,
            imageWidth: loaded.width,
            imageHeight: loaded.height,
            lines: lines.map(\.info),
            regions: []
        )
        try writeJSON(report, to: output, label: "detection report")
    }
}
