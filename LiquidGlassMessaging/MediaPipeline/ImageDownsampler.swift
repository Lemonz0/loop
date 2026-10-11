import Foundation
import ImageIO

/// Hardware-accelerated image downsampler utilizing ImageIO/CoreGraphics thumbnailing
/// and adaptive JPEG compression to guarantee payloads stay under 150 MB.
public enum ImageDownsampler {
    
    public enum ImageDownsampleError: Error, LocalizedError {
        case unableToCreateSource
        case thumbnailGenerationFailed
        case failedToWriteData
        
        public var errorDescription: String? {
            switch self {
            case .unableToCreateSource:
                return "Failed to open image source file."
            case .thumbnailGenerationFailed:
                return "CoreGraphics failed to generate downscaled image thumbnail."
            case .failedToWriteData:
                return "Could not write compressed image to disk."
            }
        }
    }
    
    /// Downsamples an image from a URL, reducing resolution and compressing quality if needed to guarantee $\le$ 150 MB.
    public static func processImage(
        at sourceURL: URL,
        maxPixelDimension: CGFloat = 4096,
        targetByteLimit: Int64 = MediaInspector.compressionTargetLimit,
        forceJPEG: Bool = false
    ) async throws -> URL {
        let originalMetadata = try await MediaInspector.inspect(fileURL: sourceURL)
        
        guard forceJPEG || originalMetadata.byteSize > targetByteLimit else {
            return sourceURL
        }
        
        return try await Task.detached(priority: .userInitiated) {
            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                throw ImageDownsampleError.unableToCreateSource
            }
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
            ]
            
            guard let downsampledCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                throw ImageDownsampleError.thumbnailGenerationFailed
            }
            
            var compression: CGFloat = 0.92
            var compressedData = try encodeJPEG(downsampledCGImage, quality: compression)
            
            while Int64(compressedData.count) > targetByteLimit, compression > 0.3 {
                compression -= 0.15
                compressedData = try encodeJPEG(downsampledCGImage, quality: compression)
            }
            
            guard Int64(compressedData.count) <= targetByteLimit else {
                throw ImageDownsampleError.failedToWriteData
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let outputFileName = "compressed_\(UUID().uuidString).jpg"
            let destinationURL = tempDir.appendingPathComponent(outputFileName)
            
            try compressedData.write(to: destinationURL, options: .atomic)
            return destinationURL
        }.value
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) throws -> Data {
        guard let encoded = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil) else {
            throw ImageDownsampleError.failedToWriteData
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageDownsampleError.failedToWriteData }
        return encoded as Data
    }
}
