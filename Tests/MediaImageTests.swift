import XCTest

final class MediaImageTests: XCTestCase {
    func testPNGIsNormalizedToJPEGWithDimensions() async throws {
        // Fixed 120x80 RGBA PNG avoids UIKit renderer initialization in hostless CI.
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAYAAADSm7GJAAAAz0lEQVR4nO3RwQkAIADEsNt/aR1DqHnkX+jOduja6wAMxmAM/pTBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRxncJzBcQbHGRx3Ae4UuVddJmojAAAAAElFTkSuQmCC"))
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
        try png.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = try await ImageDownsampler.processImage(at: source, forceJPEG: true)
        defer { try? FileManager.default.removeItem(at: output) }
        XCTAssertEqual(output.pathExtension, "jpg")
        let data = try Data(contentsOf: output)
        XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
        let metadata = try await MediaInspector.inspect(fileURL: output)
        let size = try XCTUnwrap(metadata.dimensions)
        XCTAssertEqual(size.width, 120)
        XCTAssertEqual(size.height, 80)
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
