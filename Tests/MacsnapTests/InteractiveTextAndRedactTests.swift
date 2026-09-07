import XCTest
import Cocoa
@testable import MacsnapCore

@MainActor
final class InteractiveTextAndRedactTests: XCTestCase {

    func testInlineTextEditingCycle() {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: 800,
            height: 600,
            bitsPerComponent: 8,
            bytesPerRow: 3200,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let img = ctx.makeImage()!
        let captureData = ScreenCaptureData(
            screenBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            scaleFactor: 1.0,
            pixelSize: CGSize(width: 800, height: 600),
            image: img,
            windows: []
        )

        let overlay = CaptureOverlayView(captureData: captureData)
        overlay.phase = CaptureOverlayPhase.edit
        overlay.selection = CGRect(x: 100, y: 100, width: 400, height: 300)

        // 1. Create text annotation
        overlay.createNewTextAnnotation(at: CGPoint(x: 150, y: 150))
        XCTAssertEqual(overlay.activeAnnotations.count, 1)
        XCTAssertEqual(overlay.editingTextAnnotationIndex, 0)
        XCTAssertNotNil(overlay.subviews.first(where: { $0 is NSTextField }))

        // 2. Commit empty text: should delete the empty placeholder
        overlay.commitActiveTextEditing()
        XCTAssertEqual(overlay.activeAnnotations.count, 0, "Empty text annotation should be removed upon commit")
        XCTAssertNil(overlay.editingTextAnnotationIndex)

        // 3. Create text annotation and type custom text
        overlay.createNewTextAnnotation(at: CGPoint(x: 150, y: 150))
        let tf = overlay.subviews.first(where: { $0 is NSTextField }) as? NSTextField
        XCTAssertNotNil(tf)
        tf?.stringValue = "Production Error #404"
        overlay.commitActiveTextEditing()

        XCTAssertEqual(overlay.activeAnnotations.count, 1)
        XCTAssertEqual(overlay.activeAnnotations[0].text, "Production Error #404")
        XCTAssertNil(overlay.editingTextAnnotationIndex)

        // 4. Double click to re-edit
        overlay.beginTextEditing(for: overlay.activeAnnotations[0], index: 0)
        XCTAssertEqual(overlay.editingTextAnnotationIndex, 0)
        let reeditTf = overlay.subviews.first(where: { $0 is NSTextField }) as? NSTextField
        XCTAssertEqual(reeditTf?.stringValue, "Production Error #404")
        reeditTf?.stringValue = "Production Error Resolved"
        overlay.commitActiveTextEditing()

        XCTAssertEqual(overlay.activeAnnotations[0].text, "Production Error Resolved")
    }

    func testPixelatedRedactionHasCorrectColors() {
        // Create a 100x100 solid cyan image (R: 0, G: 200, B: 200, A: 255)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let cyanImage = ctx.makeImage()!

        let redactAnn = Annotation(
            id: 1,
            kind: .redaction,
            start: CGPoint(x: 20, y: 20),
            end: CGPoint(x: 80, y: 80),
            redactionStyle: .pixelate
        )

        let redacted = RenderPipeline.applyRedactions(
            to: cyanImage,
            annotations: [redactAnn],
            selectionSize: CGSize(width: 100, height: 100),
            scale: 1.0
        )

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
        let ptr = testCtx.data!.bindMemory(to: UInt8.self, capacity: 100 * 100 * 4)

        // Sample center of redacted area (50, 50)
        let offset = (50 * 100 + 50) * 4
        let r = ptr[offset + 0]
        let g = ptr[offset + 1]
        let b = ptr[offset + 2]

        XCTAssertLessThan(r, 40, "Red channel must remain near zero for a cyan image")
        XCTAssertGreaterThan(g, 150, "Green channel must remain high")
        XCTAssertGreaterThan(b, 150, "Blue channel must remain high")
    }
}
