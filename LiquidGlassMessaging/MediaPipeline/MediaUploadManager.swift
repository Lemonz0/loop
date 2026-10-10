import Foundation
import PhotosUI
import SwiftUI

/// High-level media coordinator orchestrating PhotosPicker imports, automated compression
/// under 150 MB, and background URLSession upload execution.
@Observable
@MainActor
public final class MediaUploadManager {
    public static let shared = MediaUploadManager()
    
    public var isProcessing: Bool = false
    public var processingStatus: String = ""
    public var uploadProgress: Double = 0.0
    public var lastError: String?
    
    public init() {}
    
    // MARK: - PhotosPicker Intake & Pipeline
    
    /// Processes a selected PhotosPickerItem, compresses if > 150 MB, and uploads to the server.
    public func processAndUpload(
        item: PhotosPickerItem,
        serverBaseURL: URL,
        authToken: String?,
        roomID: String
    ) async throws -> MediaAttachment {
        guard !isProcessing else { throw URLError(.resourceUnavailable) }
        isProcessing = true
        uploadProgress = 0.0
        lastError = nil
        defer { isProcessing = false }
        
        processingStatus = "Inspecting media..."
        
        // 1. Determine media type and extract original file to disk
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw URLError(.cannotDecodeContentData) }
            return try await handleImageUpload(imageData: data, serverBaseURL: serverBaseURL, authToken: authToken, roomID: roomID)
        }
        guard let video = try await item.loadTransferable(type: MovieTransferable.self) else { throw URLError(.cannotDecodeContentData) }
        return try await handleVideoUpload(videoURL: video.url, serverBaseURL: serverBaseURL, authToken: authToken, roomID: roomID)
    }
    
    // MARK: - Video Pipeline
    
    private func handleVideoUpload(videoURL: URL, serverBaseURL: URL, authToken: String?, roomID: String) async throws -> MediaAttachment {
        processingStatus = "Checking video size..."
        let metadata = try await MediaInspector.inspect(fileURL: videoURL)
        
        let finalVideoURL: URL
        if metadata.needsCompression {
            processingStatus = "Auto-compressing video to fit 150 MB..."
            finalVideoURL = try await VideoCompressor.processVideo(sourceURL: videoURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = Double(progress) * 0.4 // Compression accounts for first 40%
                }
            }
        } else {
            finalVideoURL = videoURL
        }
        
        let finalMetadata = try await MediaInspector.inspect(fileURL: finalVideoURL)
        processingStatus = "Uploading (\(ByteCountFormatter.string(fromByteCount: finalMetadata.byteSize, countStyle: .file)))..."
        
        let remoteURL = try await uploadFile(fileURL: finalVideoURL, mimeType: "video/mp4", serverBaseURL: serverBaseURL, authToken: authToken, roomID: roomID)
        
        return MediaAttachment(
            fileName: finalVideoURL.lastPathComponent,
            mimeType: "video/mp4",
            byteSize: finalMetadata.byteSize,
            localURL: finalVideoURL,
            remoteURL: remoteURL,
            thumbnailURL: nil,
            width: finalMetadata.dimensions.map { Double($0.width) },
            height: finalMetadata.dimensions.map { Double($0.height) },
            durationSeconds: finalMetadata.durationSeconds,
            mediaType: .video
        )
    }
    
    // MARK: - Image Pipeline
    
    private func handleImageUpload(imageData: Data, serverBaseURL: URL, authToken: String?, roomID: String) async throws -> MediaAttachment {
        let tempDir = FileManager.default.temporaryDirectory
        let tempSource = tempDir.appendingPathComponent("picked_\(UUID().uuidString).dat")
        try imageData.write(to: tempSource)
        defer { try? FileManager.default.removeItem(at: tempSource) }
        
        processingStatus = "Inspecting image size..."
        // Encode actual JPEG bytes; PhotosPicker may supply HEIC, PNG or RAW.
        let finalImageURL = try await ImageDownsampler.processImage(at: tempSource, forceJPEG: true)
        
        let finalMetadata = try await MediaInspector.inspect(fileURL: finalImageURL)
        processingStatus = "Uploading image..."
        
        let remoteURL: URL
        do { remoteURL = try await uploadFile(fileURL: finalImageURL, mimeType: "image/jpeg", serverBaseURL: serverBaseURL, authToken: authToken, roomID: roomID) }
        catch { try? FileManager.default.removeItem(at: finalImageURL); throw error }
        
        return MediaAttachment(
            fileName: finalImageURL.lastPathComponent,
            mimeType: "image/jpeg",
            byteSize: finalMetadata.byteSize,
            localURL: finalImageURL,
            remoteURL: remoteURL,
            thumbnailURL: nil,
            width: finalMetadata.dimensions.map { Double($0.width) },
            height: finalMetadata.dimensions.map { Double($0.height) },
            durationSeconds: nil,
            mediaType: .image
        )
    }
    
    // MARK: - URLSession Background Upload
    
    private func uploadFile(
        fileURL: URL,
        mimeType: String,
        serverBaseURL: URL,
        authToken: String?,
        roomID: String? = nil
    ) async throws -> URL {
        let uploadEndpoint = serverBaseURL.appendingPathComponent("api/media/upload")
        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(fileURL.lastPathComponent, forHTTPHeaderField: "X-File-Name")
        guard let authToken else { throw URLError(.userAuthenticationRequired) }
        if let roomID { request.setValue(roomID, forHTTPHeaderField: "X-Room-ID") }
        if let roomID,
           let circle = AuthSessionManager.shared.circles.first(where: { $0.roomId == roomID }) {
            request.setValue(circle.id, forHTTPHeaderField: "X-Circle-ID")
        }
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(httpResponse.statusCode) else {
            struct Failure: Decodable { let errorMessage: String? }
            throw AccountHTTPError(status: httpResponse.statusCode, message: (try? JSONDecoder().decode(Failure.self, from: data))?.errorMessage ?? "Media upload failed (\(httpResponse.statusCode)).")
        }
        
        struct UploadResponse: Codable {
            let fileUrl: String
        }
        
        if let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data), let url = URL(string: decoded.fileUrl, relativeTo: serverBaseURL)?.absoluteURL {
            return url
        }
        throw URLError(.cannotParseResponse)
    }
    
    public func uploadVoice(file: URL, duration: TimeInterval, serverURL: URL, roomID: String) async throws -> MediaAttachment {
        guard !isProcessing else { throw URLError(.resourceUnavailable) }
        isProcessing = true; processingStatus = "Uploading voice message…"; lastError = nil
        defer { isProcessing = false }
        let remote = try await uploadFile(fileURL: file, mimeType: "audio/mp4", serverBaseURL: serverURL, authToken: AuthSessionManager.shared.currentSession?.token, roomID: roomID)
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        return MediaAttachment(fileName: file.lastPathComponent, mimeType: "audio/mp4", byteSize: size, remoteURL: remote, durationSeconds: duration, mediaType: .audio)
    }
    /// Directly uploads in-memory data (e.g. custom wallpaper) to the backend storage endpoint.
    public func uploadRawMedia(
        data: Data,
        fileName: String,
        serverBaseURL: URL
    ) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try await uploadFile(
            fileURL: tempURL,
            mimeType: "image/jpeg",
            serverBaseURL: serverBaseURL,
            authToken: AuthSessionManager.shared.currentSession?.token
        )
    }
}

// Helper struct for Transferable video import from PhotosPicker
public struct MovieTransferable: Transferable {
    public let url: URL
    
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let copyURL = tempDir.appendingPathComponent("imported_\(UUID().uuidString).mp4")
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return MovieTransferable(url: copyURL)
        }
    }
}
