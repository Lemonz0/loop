import Foundation
import CoreGraphics
import AVFoundation

/// Inspects file byte sizes, MIME types, video durations, and dimensions.
public enum MediaInspector {
    /// Strict 150 Megabyte boundary in bytes (150 * 1024 * 1024 = 157,286,400 bytes).
    public static let maxUploadByteLimit: Int64 = 150 * 1024 * 1024
    
    /// Target ceiling used during compression to allow safety margins for transport overhead (140 MB).
    public static let compressionTargetLimit: Int64 = 140 * 1024 * 1024
    
    public struct MediaMetadata: Sendable {
        public let byteSize: Int64
        public let mimeType: String
        public let durationSeconds: Double?
        public let dimensions: CGSize?
        public let needsCompression: Bool
    }
    
    /// Inspects a local file URL.
    public static func inspect(fileURL: URL) async throws -> MediaMetadata {
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let size = Int64(resourceValues.fileSize ?? 0)
        let mimeType = resourceValues.contentType?.preferredMIMEType ?? "application/octet-stream"
        
        let needsCompression = size > maxUploadByteLimit
        
        if mimeType.hasPrefix("video/") {
            let asset = AVURLAsset(url: fileURL)
            let duration = try? await asset.load(.duration)
            let durationSeconds = duration.map { CMTimeGetSeconds($0) }
            
            var dimensions: CGSize? = nil
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                let naturalSize = try? await videoTrack.load(.naturalSize)
                let transform = try? await videoTrack.load(.preferredTransform)
                if let naturalSize, let transform {
                    let transformedSize = naturalSize.applying(transform)
                    dimensions = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                }
            }
            
            return MediaMetadata(
                byteSize: size,
                mimeType: mimeType,
                durationSeconds: durationSeconds,
                dimensions: dimensions,
                needsCompression: needsCompression
            )
        }
        
        return MediaMetadata(
            byteSize: size,
            mimeType: mimeType,
            durationSeconds: nil,
            dimensions: nil,
            needsCompression: needsCompression
        )
    }
}
