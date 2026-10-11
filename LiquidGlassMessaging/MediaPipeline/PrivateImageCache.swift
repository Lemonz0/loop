import Foundation
import UIKit

/// Session-only image cache shared by views, with separate avatar and post instances.
/// Stories never use this cache; post entries are pruned against authorized snapshots.
@MainActor
final class PrivateImageCache {
    private let images = NSCache<NSURL, UIImage>()
    private var files: [URL: URL] = [:]
    private var pending: [URL: Task<UIImage, Error>] = [:]
    private var loadIDs: [URL: UUID] = [:]
    private var generation = 0
    private let download: @MainActor (URL) async throws -> URL

    init(download: @escaping @MainActor (URL) async throws -> URL) {
        self.download = download
        images.totalCostLimit = 32 * 1024 * 1024
        images.countLimit = 200
    }

    func cachedImage(for url: URL) -> UIImage? {
        if let image = images.object(forKey: url as NSURL) { return image }
        guard let file = files[url], let image = UIImage(contentsOfFile: file.path) else { return nil }
        store(image, for: url)
        return image
    }

    func image(for url: URL) async throws -> UIImage {
        if let image = cachedImage(for: url) { return image }
        if let task = pending[url] { return try await task.value }
        let attempt = generation
        let loadID = UUID()
        loadIDs[url] = loadID
        // A disappearing view cancels its waiter, not the download shared by other views.
        let task = Task { @MainActor in
            let file = try await download(url)
            guard generation == attempt, loadIDs[url] == loadID, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: file)
                throw CancellationError()
            }
            guard let image = UIImage(contentsOfFile: file.path) else {
                try? FileManager.default.removeItem(at: file)
                throw URLError(.cannotDecodeContentData)
            }
            files[url] = file
            store(image, for: url)
            return image
        }
        pending[url] = task
        defer { if loadIDs[url] == loadID { pending[url] = nil; loadIDs[url] = nil } }
        return try await task.value
    }

    func reset() {
        generation += 1
        for task in pending.values { task.cancel() }
        pending.removeAll()
        loadIDs.removeAll()
        images.removeAllObjects()
        for file in files.values { try? FileManager.default.removeItem(at: file) }
        files.removeAll()
    }

    /// Remove deleted, reported, or consent-revoked photos after a server refresh.
    func retainOnly(_ allowed: Set<URL>) {
        for url in Set(files.keys).union(pending.keys).subtracting(allowed) {
            pending.removeValue(forKey: url)?.cancel()
            loadIDs[url] = nil
            images.removeObject(forKey: url as NSURL)
            if let file = files.removeValue(forKey: url) { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func store(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: url as NSURL, cost: cost)
    }
}
