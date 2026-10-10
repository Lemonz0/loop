import XCTest
import UIKit
import ImageIO

final class MediaImageTests: XCTestCase {
    func testPNGIsNormalizedToJPEGWithDimensions() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
        try XCTUnwrap(image.pngData()).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = try await ImageDownsampler.processImage(at: source, forceJPEG: true)
        defer { try? FileManager.default.removeItem(at: output) }
        XCTAssertEqual(output.pathExtension, "jpg")
        let data = try Data(contentsOf: output)
        XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
        let metadata = try await MediaInspector.inspect(fileURL: output)
        // Renderer pixels vary with simulator scale; the aspect ratio stays fixed.
        let size = try XCTUnwrap(metadata.dimensions)
        XCTAssertEqual(size.width / size.height, 1.5, accuracy: 0.01)
        XCTAssertEqual(metadata.mimeType, "image/jpeg")
    }

    func testInvalidImageCannotBecomeJPEGAttachment() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
        try Data("not an image".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        do { _ = try await ImageDownsampler.processImage(at: source, forceJPEG: true); XCTFail("Invalid image accepted") }
        catch { XCTAssertTrue(error is ImageDownsampler.ImageDownsampleError) }
    }
}
