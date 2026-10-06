import CoreGraphics
import Vision

public enum FaceDetector {
    /// Face rectangles scaled around their centers by `scale` (Vision's face box is
    /// tight around the eyes/nose/mouth, so a margin also covers hair and chin).
    public static func detect(in image: CGImage, scale: Double) async throws -> [NormalizedBox] {
        let faces = try await ImageRequestHandler(image).perform(DetectFaceRectanglesRequest())
        return faces.map { NormalizedBox($0.boundingBox).scaled(by: scale) }
    }
}
