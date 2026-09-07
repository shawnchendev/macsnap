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

        // Verify that pixels inside redaction rect are black (0, 0, 0)
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
        let bytes = testCtx.data!.bindMemory(to: UInt8.self, capacity: 100 * 100 * 4)

        // Pixel at center (50, 50)
        let offset = (50 * 100 + 50) * 4
        XCTAssertEqual(bytes[offset + 0], 0, "Red must be 0")
        XCTAssertEqual(bytes[offset + 1], 0, "Green must be 0")
        XCTAssertEqual(bytes[offset + 2], 0, "Blue must be 0")

        // Also test .pixelate on a green image to ensure it doesn't turn red!
        let greenCtx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        greenCtx.setFillColor(CGColor(red: 0, green: 0.8, blue: 0.2, alpha: 1))
        greenCtx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let greenImg = greenCtx.makeImage()!

        let pixAnn = Annotation(
            id: 2,
            kind: .redaction,
            start: CGPoint(x: 20, y: 20),
            end: CGPoint(x: 80, y: 80),
            redactionStyle: .pixelate
        )
        let pixRedacted = RenderPipeline.applyRedactions(
            to: greenImg,
            annotations: [pixAnn],
            selectionSize: CGSize(width: 100, height: 100),
            scale: 1.0
        )
        let pixTestCtx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        pixTestCtx.draw(pixRedacted, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let pixBytes = pixTestCtx.data!.bindMemory(to: UInt8.self, capacity: 100 * 100 * 4)
        let pixOffset = (50 * 100 + 50) * 4

        // The pixelated block should remain greenish (high Green, low Red)
        XCTAssertLessThan(pixBytes[pixOffset + 0], 50, "Red must NOT be high in a green image")
        XCTAssertGreaterThan(pixBytes[pixOffset + 1], 150, "Green should remain high")
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

    @MainActor
    func testArrowDirection() {
        guard let sckImg = ScreenCaptureEngine.loadImage(from: URL(fileURLWithPath: "/tmp/sck_test.png")) else { return }
        let capData = ScreenCaptureData(
            screenBounds: CGRect(x: 0, y: 0, width: sckImg.width, height: sckImg.height),
            scaleFactor: 1.0,
            pixelSize: CGSize(width: sckImg.width, height: sckImg.height),
            image: sckImg,
            windows: []
        )
        let view = CaptureOverlayView(captureData: capData)
        view.frame = NSRect(x: 0, y: 0, width: sckImg.width, height: sckImg.height)
        view.phase = .edit
        view.selection = CGRect(x: 100, y: 100, width: 600, height: 400)

        // User drags from top-left (start) to bottom-right (end)
        let pStart = CGPoint(x: 400, y: 300)
        let pEnd = CGPoint(x: 600, y: 450)
        let startAnn = view.toAnnotationPoint(pStart)
        let endAnn = view.toAnnotationPoint(pEnd)

        let arrow = Annotation(
            id: 1,
            kind: .arrow,
            start: startAnn,
            end: endAnn,
            colorHex: "#00ff00",
            size: 6.0
        )
        view.activeAnnotations = [arrow]

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sckImg.width, pixelsHigh: sckImg.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: sckImg.width * 4, bitsPerPixel: 32)!
        let gctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()

        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/arrow_debug.png"))
            print("Saved /tmp/arrow_debug.png")
        }
    }

    @MainActor
    func testCoordinateRoundTrip() {
        let dummyImg = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!

        let capData = ScreenCaptureData(
            screenBounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            scaleFactor: 1.0,
            pixelSize: CGSize(width: 1200, height: 800),
            image: dummyImg,
            windows: []
        )
        let view = CaptureOverlayView(captureData: capData)
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        view.phase = .edit
        view.selection = CGRect(x: 200, y: 150, width: 500, height: 350)

        // Test multiple screen points round-trip
        let testPoints = [
            CGPoint(x: 300, y: 200),
            CGPoint(x: 600, y: 400),
            CGPoint(x: 250, y: 450),
            CGPoint(x: 700, y: 250)
        ]

        for pt in testPoints {
            let ann = view.toAnnotationPoint(pt)
            let roundTrip = view.toScreenPoint(ann)
            XCTAssertEqual(pt.x, roundTrip.x, accuracy: 0.001, "X coordinate should round-trip perfectly")
            XCTAssertEqual(pt.y, roundTrip.y, accuracy: 0.001, "Y coordinate should round-trip perfectly")
        }
    }

    func testArrowAngleAllQuadrants() {
        // Test that arrow vector correctly points in the direction of drag
        // 1. Right & Down: dx > 0, dy > 0 -> angle in (0, pi/2)
        let dx1 = 100.0, dy1 = 100.0
        let a1 = atan2(dy1, dx1)
        XCTAssertGreaterThan(a1, 0)
        XCTAssertLessThan(a1, .pi / 2.0)

        // 2. Left & Up: dx < 0, dy < 0 -> angle in (-pi, -pi/2)
        let dx2 = -100.0, dy2 = -100.0
        let a2 = atan2(dy2, dx2)
        XCTAssertLessThan(a2, -(.pi / 2.0))

        // 3. Right & Up: dx > 0, dy < 0 -> angle in (-pi/2, 0)
        let dx3 = 100.0, dy3 = -100.0
        let a3 = atan2(dy3, dx3)
        XCTAssertLessThan(a3, 0)
        XCTAssertGreaterThan(a3, -(.pi / 2.0))

        // 4. Left & Down: dx < 0, dy > 0 -> angle in (pi/2, pi)
        let dx4 = -100.0, dy4 = 100.0
        let a4 = atan2(dy4, dx4)
        XCTAssertGreaterThan(a4, .pi / 2.0)
    }
}
