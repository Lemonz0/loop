import XCTest
import UIKit

@MainActor
final class PrivateImageCacheTests: XCTestCase {
    private func photo() throws -> URL {
        // Fixed 1px RGBA PNG avoids initializing UIKit's renderer in a hostless test process.
        let data = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: file)
        return file
    }

    func testCategoryRecreationUsesCachedImageAndNewURLLoadsNewPhoto() async throws {
        var downloads = 0
        let cache = PrivateImageCache { _ in
            downloads += 1
            let file = try self.photo()
            return file
        }
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
        let cache = PrivateImageCache { _ in
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
        let cache = PrivateImageCache { _ in
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
        let cache = PrivateImageCache { _ in file }
        let url = URL(string: "https://example.com/uploads/avatar.png")!
        _ = try await cache.image(for: url)
        cache.reset()
        XCTAssertNil(cache.cachedImage(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFeedAndTrollImagesSurviveCategorySwitchButRemovedPhotosArePurged() async throws {
        var downloads = 0
        let cache = PrivateImageCache { _ in downloads += 1; return try self.photo() }
        defer { cache.reset() }
        let feed = URL(string: "https://example.com/uploads/feed.png")!
        let troll = URL(string: "https://example.com/uploads/anonymous.png")!
        _ = try await cache.image(for: feed)
        let wallImage = try await cache.image(for: troll)
        cache.retainOnly([feed, troll])
        let revisited = try await cache.image(for: troll)
        XCTAssertTrue(revisited === wallImage)
        XCTAssertEqual(downloads, 2)
        cache.retainOnly([feed])
        XCTAssertNotNil(cache.cachedImage(for: feed))
        XCTAssertNil(cache.cachedImage(for: troll))
    }

    func testPrunedPendingDownloadCannotRepopulateCache() async throws {
        let file = try photo()
        let started = expectation(description: "Download started")
        var finish: CheckedContinuation<URL, Never>?
        let cache = PrivateImageCache { _ in
            await withCheckedContinuation { continuation in finish = continuation; started.fulfill() }
        }
        defer { cache.reset() }
        let url = URL(string: "https://example.com/uploads/revoked.png")!
        let waiter = Task { try await cache.image(for: url) }
        await fulfillment(of: [started], timeout: 2)
        cache.retainOnly([])
        finish?.resume(returning: file)
        do { _ = try await waiter.value; XCTFail("Revoked image cached") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(cache.cachedImage(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
