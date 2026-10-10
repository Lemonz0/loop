import Foundation

public struct AccountHTTPError: LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public var errorDescription: String? { message }
}
private struct ErrorBody: Decodable { let errorMessage: String? }
private final class AccountRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public actor AccountHTTPClient {
    public static let shared = AccountHTTPClient()
    public nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        return value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled
    }
    private let session: URLSession
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: AccountRedirectDelegate(), delegateQueue: nil)
    }
    public func request<T: Decodable & Sendable>(_ path: String, baseURL: URL, token: String? = nil,
                                                 body: Data? = nil, as type: T.Type) async throws -> T {
        guard AccountCodec.serverURL(baseURL.absoluteString) != nil else { throw AccountHTTPError(status: 0, message: "Use HTTPS, or an HTTP address on your local network.") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = body == nil ? "GET" : "POST"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.errorMessage ?? "Server rejected the request (\(http.statusCode))."
            throw AccountHTTPError(status: http.statusCode, message: message)
        }
        return try AccountCodec.decoder().decode(type, from: data)
    }
    public func downloadMedia(_ value: URL, baseURL: URL, token: String) async throws -> URL {
        guard let url = URL(string: value.absoluteString, relativeTo: baseURL)?.absoluteURL,
              url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
              url.path.hasPrefix("/uploads/") else {
            throw AccountHTTPError(status: 403, message: "Media must belong to your signed-in server.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (temporary, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw AccountHTTPError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Media could not be loaded.")
        }
        let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= 150 * 1024 * 1024 else { try? FileManager.default.removeItem(at: temporary); throw URLError(.dataLengthExceedsMaximum) }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let destination = directory.appendingPathComponent("loop-private-" + UUID().uuidString).appendingPathExtension(url.pathExtension)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    public func uploadSocialPhoto(_ data: Data, baseURL: URL, token: String, circleID: String) async throws -> String {
        guard data.count <= 20 * 1024 * 1024 else { throw AccountHTTPError(status: 413, message: "Choose a photo under 20 MB.") }
        guard AccountCodec.serverURL(baseURL.absoluteString) != nil else { throw URLError(.badURL) }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/circles/\(circleID)/social/media"))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: responseData))?.errorMessage ?? "Photo upload failed."
            throw AccountHTTPError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: message)
        }
        return try JSONDecoder().decode(SocialPhotoUploadResponse.self, from: responseData).fileUrl
    }

}

private struct SocialPhotoUploadResponse: Decodable { let fileUrl: String }
