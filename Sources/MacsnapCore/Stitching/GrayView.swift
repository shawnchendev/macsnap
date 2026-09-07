import Foundation
import CoreGraphics

public enum StitchAxis: Sendable {
    case vertical
    case horizontal
}

public final class GrayView: @unchecked Sendable {
    public static let kDownsampleCross = 4

    public var pixels: [UInt8]
    public var width: Int
    public var height: Int
    public var sourceWidth: Int
    public var sourceHeight: Int

    public init(image: CGImage, axis: StitchAxis) {
        let sw = image.width
        let sh = image.height
        self.sourceWidth = sw
        self.sourceHeight = sh

        if axis == .vertical {
            // Motion axis (vertical) is kept at source resolution: height = sh
            // Cross axis (horizontal) is downsampled by 4: width = sw / 4
            self.width = max(1, sw / Self.kDownsampleCross)
            self.height = sh
        } else {
            // Motion axis (horizontal) kept at source resolution: width = sw
            // Cross axis (vertical) downsampled by 4: height = sh / 4
            self.width = sw
            self.height = max(1, sh / Self.kDownsampleCross)
        }

        self.pixels = [UInt8](repeating: 0, count: self.width * self.height)

        // Render into 8-bit grayscale context
        guard let colorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let context = CGContext(
                data: &self.pixels,
                width: self.width,
                height: self.height,
                bitsPerComponent: 8,
                bytesPerRow: self.width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))
    }

    public func axisLen(axis: StitchAxis) -> Int {
        axis == .vertical ? height : width
    }

    public func crossLen(axis: StitchAxis) -> Int {
        axis == .vertical ? width : height
    }

    public func pixel(x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return pixels[y * width + x]
    }
}
