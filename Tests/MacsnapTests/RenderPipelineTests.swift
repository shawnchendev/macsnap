import XCTest
import CoreGraphics
@testable import MacsnapCore

final class RenderPipelineTests: XCTestCase {
    func testRedactionDestroysPixels() {
        // Create 100x100 white image
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let whiteImg = context.makeImage()!

        // Apply solid redaction across (20, 20, 60, 60)
        let redAnn = Annotation(
            id: 1,
            kind: .redaction,
            start: CGPoint(x: 20, y: 20),
            end: CGPoint(x: 80, y: 80),
            redactionStyle: .solid
        )

        let redacted = RenderPipeline.applyRedactions(
            to: whiteImg,
            annotations: [redAnn],
            selectionSize: CGSize(width: 100, height: 100),
            scale: 1.0
        )

        // Verify that pixels inside redaction rect are black (0xFF000000 or (0,0,0))
        let testCtx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        testCtx.draw(redacted, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let data = testCtx.data!.bindMemory(to: UInt32.self, capacity: 100 * 100)

        // Pixel at center (50, 50)
        // Memory offset: (height - 1 - y) * width + x
        let memY = 100 - 1 - 50
        let pixelVal = data[memY * 100 + 50]

        let r = (pixelVal >> 24) & 0xff
        let g = (pixelVal >> 16) & 0xff
        let b = (pixelVal >> 8) & 0xff
        XCTAssertEqual(r, 0)
        XCTAssertEqual(g, 0)
        XCTAssertEqual(b, 0)
    }

    func testRenderCaptureProducesOutput() {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 800,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let src = context.makeImage()!

        let ann = Annotation(
            id: 1,
            kind: .arrow,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 80, y: 80)
        )

        let rendered = RenderPipeline.renderCapture(
            source: src,
            selection: CGRect(x: 0, y: 0, width: 100, height: 100),
            annotations: [ann],
            backdropStyle: .aurora,
            imageShadow: true,
            boundaryMode: .framed,
            scale: 1.0
        )

        XCTAssertNotNil(rendered)
        XCTAssertGreaterThan(rendered!.width, 0)
        XCTAssertGreaterThan(rendered!.height, 0)
    }

    func testImageOrientation() {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        let src = context.makeImage()!

        let rendered = RenderPipeline.renderCapture(
            source: src,
            selection: CGRect(x: 0, y: 0, width: 100, height: 100),
            annotations: [],
            backdropStyle: .none,
            imageShadow: false,
            boundaryMode: .image,
            scale: 1.0
        )!

        let data = rendered.dataProvider!.data!
        let ptr = CFDataGetBytePtr(data)!
        let topR = ptr[20 * rendered.bytesPerRow]
        let botB = ptr[80 * rendered.bytesPerRow + 2]

        XCTAssertGreaterThan(topR, 200, "Top should be red")
        XCTAssertGreaterThan(botB, 200, "Bottom should be blue")
    }
}
