import Foundation
import AVFoundation

/// Hardware-accelerated video compressor using AVAssetExportSession and dynamic bitrate calculation
/// to enforce the strict 150 MB upload threshold.
public enum VideoCompressor {
    
    public enum VideoCompressionError: Error, LocalizedError {
        case assetNotReadable
        case invalidDuration
        case exportSessionInitFailed
        case exportFailed(String)
        case outputStillExceedsLimit(Int64)
        
        public var errorDescription: String? {
            switch self {
            case .assetNotReadable:
                return "The selected video asset could not be read."
            case .invalidDuration:
                return "Video duration is zero or invalid."
            case .exportSessionInitFailed:
                return "Failed to initialize AVAssetExportSession with target preset."
            case .exportFailed(let reason):
                return "AVAssetExportSession failed: \(reason)"
            case .outputStillExceedsLimit(let bytes):
                return "Compressed video still exceeds 150 MB (\(bytes) bytes)."
            }
        }
    }
    
    /// Processes a video file: if <= 150 MB, returns original; if > 150 MB, compresses via AVAssetExportSession.
    public static func processVideo(
        sourceURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> URL {
        let metadata = try await MediaInspector.inspect(fileURL: sourceURL)
        
        // Fast-path: If file is already <= 150 MB, upload original directly!
        guard metadata.needsCompression else {
            return sourceURL
        }
        
        guard let durationSeconds = metadata.durationSeconds, durationSeconds > 0.1 else {
            throw VideoCompressionError.invalidDuration
        }
        
        // Calculate maximum allowable bitrate (bits/sec) to guarantee payload fits within 140 MB target
        let targetBytes: Int64 = MediaInspector.compressionTargetLimit // 140 MB safety target
        let targetBits = Double(targetBytes) * 8.0
        let audioAllowanceBitsPerSecond: Double = 128_000 // 128 kbps for AAC audio
        let totalAllowedBitrate = (targetBits / durationSeconds) * 0.94 // 6% safety margin for MP4 container atoms
        let permissibleVideoBitrate = max(totalAllowedBitrate - audioAllowanceBitsPerSecond, 500_000)
        
        let asset = AVURLAsset(url: sourceURL)
        
        // Select best compatible export preset based on calculated permissible bitrate
        let preset: String
        if permissibleVideoBitrate >= 6_000_000 {
            preset = AVAssetExportPresetHEVCHighestQuality
        } else if permissibleVideoBitrate >= 3_500_000 {
            preset = AVAssetExportPreset1920x1080
        } else if permissibleVideoBitrate >= 1_500_000 {
            preset = AVAssetExportPreset1280x720
        } else {
            preset = AVAssetExportPreset960x540
        }
        
        return try await exportWithPreset(
            asset: asset,
            preset: preset,
            targetByteLimit: MediaInspector.maxUploadByteLimit,
            progressHandler: progressHandler
        )
    }
    
    private static func exportWithPreset(
        asset: AVURLAsset,
        preset: String,
        targetByteLimit: Int64,
        progressHandler: (@Sendable (Float) -> Void)?
    ) async throws -> URL {
        // Verify preset compatibility synchronously (iOS 15-18 compatible)
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let chosenPreset = compatiblePresets.contains(preset) ? preset : AVAssetExportPresetMediumQuality
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: chosenPreset) else {
            throw VideoCompressionError.exportSessionInitFailed
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("compressed_\(UUID().uuidString).mp4")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true // Fast-start moov atom at beginning of MP4
        
        // Monitor progress via timer if requested
        let progressMonitorTask: Task<Void, Never>?
        if let progressHandler {
            progressMonitorTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                    progressHandler(exportSession.progress)
                    if exportSession.status != .exporting && exportSession.status != .waiting {
                        break
                    }
                }
            }
        } else {
            progressMonitorTask = nil
        }
        
        // Perform asynchronous export compatible with iOS 17 & iOS 18
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }
        progressMonitorTask?.cancel()
        
        switch exportSession.status {
        case .completed:
            // Verify final exported file size
            let outputMetadata = try await MediaInspector.inspect(fileURL: outputURL)
            if outputMetadata.byteSize > targetByteLimit {
                // Secondary fallback pass: downscale to 720p if HEVC highest still overflowed
                if chosenPreset != AVAssetExportPreset1280x720 && chosenPreset != AVAssetExportPreset960x540 {
                    try? FileManager.default.removeItem(at: outputURL)
                    return try await exportWithPreset(
                        asset: asset,
                        preset: AVAssetExportPreset1280x720,
                        targetByteLimit: targetByteLimit,
                        progressHandler: progressHandler
                    )
                }
                throw VideoCompressionError.outputStillExceedsLimit(outputMetadata.byteSize)
            }
            return outputURL
            
        case .failed:
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw VideoCompressionError.exportFailed(errorMsg)
            
        case .cancelled:
            throw VideoCompressionError.exportFailed("Export cancelled")
            
        default:
            throw VideoCompressionError.exportFailed("Unexpected export session state: \(exportSession.status.rawValue)")
        }
    }
}
