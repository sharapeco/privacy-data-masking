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

    @OptionGroup var detection: DetectionFlags

    func run() async throws {
        let loaded = try ImageLoader.load(path: image)
        let report = try await DetectionPipeline.run(image: loaded, imagePath: image, options: detection.options)
        try writeJSON(report, to: output, label: "detection report (\(report.regions.count) regions)")
    }
}
