import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TaskManager

struct ImageCompressorTests {
    /// A large solid PNG, built without UIKit.
    private func makePNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func downsamplesToTheMaxDimensionAndShrinks() async throws {
        let original = try makePNG(width: 4000, height: 3000)
        let compressed = try await ImageCompressor().compressedJPEG(from: original, maxDimension: 2048, quality: 0.7)

        let source = try #require(CGImageSourceCreateWithData(compressed as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 2048)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1536)
        #expect(compressed.count < original.count)
    }

    @Test func rejectsNonImageData() async {
        await #expect(throws: ImageCompressionError.unreadableImage) {
            try await ImageCompressor().compressedJPEG(from: Data("not an image".utf8), maxDimension: 2048, quality: 0.7)
        }
    }
}
