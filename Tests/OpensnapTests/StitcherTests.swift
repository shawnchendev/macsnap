import XCTest
import CoreGraphics
@testable import OpensnapCore

final class StitcherTests: XCTestCase {
    func testStitcherStationary() {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 120,
            height: 120,
            bitsPerComponent: 8,
            bytesPerRow: 480,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        let img = context.makeImage()!

        let stitcher = Stitcher(axis: .vertical)
        stitcher.start(initialFrame: img)

        // Adding identical frame should report stationary
        let motion = stitcher.addFrame(img)
        XCTAssertEqual(motion.kind, .stationary)
    }

    func testStitcherFinishProducesValidImage() {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let img = context.makeImage()!

        let stitcher = Stitcher(axis: .vertical)
        stitcher.start(initialFrame: img)

        let finished = stitcher.finish()
        XCTAssertNotNil(finished)
        XCTAssertEqual(finished?.width, 100)
        XCTAssertEqual(finished?.height, 100)
    }
}
