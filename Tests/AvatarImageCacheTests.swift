import XCTest
import UIKit

@MainActor
final class AvatarImageCacheTests: XCTestCase {
    private func photo() throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        return file
    }

    func testCategoryRecreationUsesCachedImageAndNewURLLoadsNewPhoto() async throws {
        var downloads = 0
        let cache = AvatarImageCache { _ in downloads += 1; return try self.photo() }
        defer { cache.reset() }
        let url = URL(string: "https://example.com/uploads/avatar.png")!
        let first = try await cache.image(for: url)
        XCTAssertTrue(cache.cachedImage(for: url) === first)
        let revisited = try await cache.image(for: url)
        XCTAssertTrue(revisited === first)
        XCTAssertEqual(downloads, 1)
        _ = try await cache.image(for: URL(string: "https://example.com/uploads/new-avatar.png")!)
        XCTAssertEqual(downloads, 2)
    }

    func testSimultaneousAvatarsShareDownload() async throws {
        var downloads = 0
        let cache = AvatarImageCache { _ in
            downloads += 1
            try await Task.sleep(for: .milliseconds(30))
            return try self.photo()
        }
        defer { cache.reset() }
        let url = URL(string: "https://example.com/uploads/avatar.png")!
        async let first = cache.image(for: url)
        async let second = cache.image(for: url)
        let images = try await (first, second)
        XCTAssertTrue(images.0 === images.1)
        XCTAssertEqual(downloads, 1)
    }

    func testLogoutRejectsLateDownloadAndRemovesPrivateFiles() async throws {
        let file = try photo()
        let started = expectation(description: "Download started")
        var finish: CheckedContinuation<URL, Never>?
        let cache = AvatarImageCache { _ in
            await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        }
        let url = URL(string: "https://example.com/uploads/avatar.png")!
        let waiter = Task { try await cache.image(for: url) }
        await fulfillment(of: [started], timeout: 2)
        cache.reset()
        finish?.resume(returning: file)
        do { _ = try await waiter.value; XCTFail("Late download survived logout") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(cache.cachedImage(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testLogoutClearsCachedImageAndFile() async throws {
        let file = try photo()
        let cache = AvatarImageCache { _ in file }
        let url = URL(string: "https://example.com/uploads/avatar.png")!
        _ = try await cache.image(for: url)
        cache.reset()
        XCTAssertNil(cache.cachedImage(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
