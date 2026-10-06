import CoreGraphics
import Vision

public enum BarcodeDetector {
    /// Barcodes and QR codes can encode personal data (membership IDs, ID cards).
    public static func detect(in image: CGImage) async throws -> [NormalizedBox] {
        let barcodes = try await ImageRequestHandler(image).perform(DetectBarcodesRequest())
        return barcodes.map { NormalizedBox($0.boundingBox) }
    }
}
