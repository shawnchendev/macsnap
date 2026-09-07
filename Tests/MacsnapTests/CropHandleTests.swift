import XCTest
import Cocoa
@testable import MacsnapCore

@MainActor
final class CropHandleTests: XCTestCase {
    private func createTestOverlay() -> CaptureOverlayView {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
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
        overlay.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        overlay.phase = .edit
        overlay.selection = CGRect(x: 100, y: 100, width: 400, height: 300)
        overlay.initialCaptureSelection = overlay.selection
        return overlay
    }

    func testCropHandleGeometryAndHitTest() {
        let overlay = createTestOverlay()
        let handleRects = overlay.cropHandleRects()
        XCTAssertEqual(handleRects.count, 8, "Must generate 8 crop handles (4 corners + 4 edges)")

        // 0: Top-Left corner
        let tlCenter = CGPoint(x: handleRects[0].midX, y: handleRects[0].midY)
        XCTAssertEqual(overlay.cropHandleIndex(at: tlCenter), 0)

        // 2: Top-Right corner
        let trCenter = CGPoint(x: handleRects[2].midX, y: handleRects[2].midY)
        XCTAssertEqual(overlay.cropHandleIndex(at: trCenter), 2)

        // 4: Bottom-Right corner
        let brCenter = CGPoint(x: handleRects[4].midX, y: handleRects[4].midY)
        XCTAssertEqual(overlay.cropHandleIndex(at: brCenter), 4)

        // 6: Bottom-Left corner
        let blCenter = CGPoint(x: handleRects[6].midX, y: handleRects[6].midY)
        XCTAssertEqual(overlay.cropHandleIndex(at: blCenter), 6)

        // Point far outside should not hit any handle
        XCTAssertNil(overlay.cropHandleIndex(at: CGPoint(x: 5, y: 5)))
    }

    func testDragBottomRightCornerResizesCanvas() {
        let overlay = createTestOverlay()
        let handleRects = overlay.cropHandleRects()
        let brCenter = CGPoint(x: handleRects[4].midX, y: handleRects[4].midY)

        // Mouse down on bottom-right corner (handle 4)
        let downEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: brCenter.x, y: 600 - brCenter.y),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        overlay.mouseDown(with: downEvent)

        // Mouse drag right and down by 40 points
        let dragEvent = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: brCenter.x + 40, y: 600 - (brCenter.y + 40)),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        overlay.mouseDragged(with: dragEvent)

        // Selection width and height should have increased
        XCTAssertGreaterThan(overlay.selection.width, 400.0)
        XCTAssertGreaterThan(overlay.selection.height, 300.0)
        XCTAssertEqual(overlay.selection.origin.x, 100.0, "Top-left origin must stay fixed when dragging bottom-right")
        XCTAssertEqual(overlay.selection.origin.y, 100.0, "Top-left origin must stay fixed when dragging bottom-right")

        // Mouse up to commit crop
        let upEvent = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: CGPoint(x: brCenter.x + 40, y: 600 - (brCenter.y + 40)),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0.0
        )!
        overlay.mouseUp(with: upEvent)

        // Operation log should contain .crop
        XCTAssertEqual(overlay.opLog.ops.last?.type, .crop)
    }

    func testDragTopLeftCornerShiftsAnnotations() {
        let overlay = createTestOverlay()
        // Add an arrow annotation at (100, 100) -> (150, 150)
        let arrow = Annotation(
            id: overlay.opLog.nextId,
            kind: .arrow,
            start: CGPoint(x: 100, y: 100),
            end: CGPoint(x: 150, y: 150),
            colorHex: "#ff375f",
            size: 4.0
        )
        overlay.commitAnnotation(arrow)
        XCTAssertEqual(overlay.activeAnnotations.count, 1)

        let handleRects = overlay.cropHandleRects()
        let tlCenter = CGPoint(x: handleRects[0].midX, y: handleRects[0].midY)

        // Mouse down on top-left corner (handle 0)
        let downEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: tlCenter.x, y: 600 - tlCenter.y),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        overlay.mouseDown(with: downEvent)

        // Mouse drag down and right by 30 points
        let dragEvent = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: CGPoint(x: tlCenter.x + 30, y: 600 - (tlCenter.y + 30)),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        overlay.mouseDragged(with: dragEvent)

        // Origin should have shifted to the right and down
        XCTAssertGreaterThan(overlay.selection.origin.x, 100.0)
        XCTAssertGreaterThan(overlay.selection.origin.y, 100.0)

        // Annotation start coordinate relative to new origin should have shifted left/up by the same amount
        let shiftX = overlay.selection.origin.x - 100.0
        XCTAssertEqual(overlay.activeAnnotations[0].start.x, 100.0 - shiftX, accuracy: 0.001)

        // Mouse up
        let upEvent = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: CGPoint(x: tlCenter.x + 30, y: 600 - (tlCenter.y + 30)),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0.0
        )!
        overlay.mouseUp(with: upEvent)

        // Test Undo restores original selection
        overlay.undo()
        XCTAssertEqual(overlay.selection.origin.x, 100.0, accuracy: 0.001)
        XCTAssertEqual(overlay.selection.origin.y, 100.0, accuracy: 0.001)
        XCTAssertEqual(overlay.activeAnnotations[0].start.x, 100.0, accuracy: 0.001)

        // Test Redo
        overlay.redo()
        XCTAssertEqual(overlay.selection.origin.x, 100.0 + shiftX, accuracy: 0.001)
    }
}
