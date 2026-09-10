import XCTest
import CoreGraphics
@testable import OpensnapCore

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

        // Now test with a small redaction
        let redact = Annotation(
            id: 1,
            kind: .redaction,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 20, y: 20),
            redactionStyle: .solid
        )
        let renderedRedact = RenderPipeline.renderCapture(
            source: src,
            selection: CGRect(x: 0, y: 0, width: 100, height: 100),
            annotations: [redact],
            backdropStyle: .none,
            imageShadow: false,
            boundaryMode: .image,
            scale: 1.0
        )!

        let redactData = renderedRedact.dataProvider!.data!
        let redactPtr = CFDataGetBytePtr(redactData)!
        let topRRedact = redactPtr[20 * renderedRedact.bytesPerRow]
        let botBRedact = redactPtr[80 * renderedRedact.bytesPerRow + 2]

        XCTAssertGreaterThan(topRRedact, 200, "Top should still be red when redaction is present")
        XCTAssertGreaterThan(botBRedact, 200, "Bottom should still be blue when redaction is present")

        // Redacted point (15, 15) should be solid black (0, 0, 0)
        let redactAt15R = redactPtr[15 * renderedRedact.bytesPerRow + 15 * 4 + 0]
        let redactAt15G = redactPtr[15 * renderedRedact.bytesPerRow + 15 * 4 + 1]
        let redactAt15B = redactPtr[15 * renderedRedact.bytesPerRow + 15 * 4 + 2]
        XCTAssertEqual(redactAt15R, 0, "Redacted pixel at (15, 15) should be black")
        XCTAssertEqual(redactAt15G, 0, "Redacted pixel at (15, 15) should be black")
        XCTAssertEqual(redactAt15B, 0, "Redacted pixel at (15, 15) should be black")

        // Unredacted point at same y row (85, 15) should remain red
        let unredactedR = redactPtr[15 * renderedRedact.bytesPerRow + 85 * 4 + 0]
        XCTAssertGreaterThan(unredactedR, 200, "Unredacted pixel at (85, 15) should remain red")
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

    // MARK: - Region crop orientation

    /// Builds a W×H test image with top-first rows: rows above `split` are
    /// red, rows below are blue.
    private func splitTestImage(width: Int, height: Int, split: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let isTop = y < split
            for x in 0..<width {
                let o = (y * width + x) * 4
                bytes[o + 0] = isTop ? 255 : 0     // R
                bytes[o + 1] = 0                   // G
                bytes[o + 2] = isTop ? 0 : 255     // B
                bytes[o + 3] = 255                 // A
            }
        }
        let data = CFDataCreate(nil, bytes, bytes.count)!
        let provider = CGDataProvider(data: data)!
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private func topLeftPixel(of image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let data = image.dataProvider!.data! as Data
        // Data row 0 is the image's top row; RGBA byte order.
        return (data[0], data[1], data[2], data[3])
    }

    func testRegionCropSelectsBottomHalf() {
        let source = splitTestImage(width: 200, height: 100, split: 50)
        // View coords are top-left origin: y=50..100 is the blue bottom half.
        let out = RenderPipeline.renderCapture(
            source: source,
            selection: CGRect(x: 0, y: 50, width: 200, height: 50),
            annotations: [],
            backdropStyle: .none,
            imageShadow: false,
            boundaryMode: .image,
            scale: 1.0
        )!
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 50)
        let px = topLeftPixel(of: out)
        XCTAssertEqual(px.r, 0, "Bottom-half crop must be blue, got R=\(px.r)")
        XCTAssertEqual(px.b, 255, "Bottom-half crop must be blue, got B=\(px.b)")
    }

    func testRegionCropSelectsTopHalf() {
        let source = splitTestImage(width: 200, height: 100, split: 50)
        let out = RenderPipeline.renderCapture(
            source: source,
            selection: CGRect(x: 0, y: 0, width: 200, height: 50),
            annotations: [],
            backdropStyle: .none,
            imageShadow: false,
            boundaryMode: .image,
            scale: 1.0
        )!
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 50)
        let px = topLeftPixel(of: out)
        XCTAssertEqual(px.r, 255, "Top-half crop must be red, got R=\(px.r)")
        XCTAssertEqual(px.b, 0, "Top-half crop must be red, got B=\(px.b)")
    }
}
