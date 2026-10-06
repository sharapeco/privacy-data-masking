import ArgumentParser
import PDMaskCore

/// Detection switches shared by `mask` and `detect`.
struct DetectionFlags: ParsableArguments {
    @Flag(help: "顔を検出しない。")
    var noFaces = false

    @Flag(help: "バーコード／QR コードを検出しない。")
    var noBarcodes = false

    @Option(help: "顔の矩形を中心から何倍に広げて塗るか。")
    var faceScale: Double = 1.3

    var options: DetectionOptions {
        var options = DetectionOptions()
        options.detectFaces = !noFaces
        options.detectBarcodes = !noBarcodes
        options.faceScale = faceScale
        return options
    }
}
