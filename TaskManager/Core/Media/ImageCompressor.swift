import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks images before upload.
protocol ImageCompressing: Sendable {
    /// Downsamples to `maxDimension` pixels on the long edge and re-encodes as JPEG.
    func compressedJPEG(from data: Data, maxDimension: Int, quality: Double) async throws -> Data
}

enum ImageCompressionError: Error, Equatable {
    case unreadableImage
    case encodingFailed
}

/// ImageIO-based compressor. An actor, so decoding never happens on the main thread, and
/// `CGImageSourceCreateThumbnailAtIndex` never decodes the full-size bitmap.
actor ImageCompressor: ImageCompressing {
    func compressedJPEG(from data: Data, maxDimension: Int = 2048, quality: Double = 0.7) throws -> Data {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ImageCompressionError.unreadableImage
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            // Bakes the EXIF orientation into the pixels so the result looks the same everywhere.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw ImageCompressionError.unreadableImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageCompressionError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageCompressionError.encodingFailed }
        return output as Data
    }
}
