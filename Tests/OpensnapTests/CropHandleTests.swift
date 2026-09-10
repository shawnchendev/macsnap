import XCTest
import Cocoa
@testable import OpensnapCore

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

    func testAnnotationCornerHandlesHitTest() {
        let overlay = createTestOverlay()
        overlay.tool = .select
        let arrow = Annotation(
            id: overlay.opLog.nextId,
            kind: .arrow,
            start: CGPoint(x: 150, y: 150),
            end: CGPoint(x: 250, y: 200),
            colorHex: "#ff375f",
            size: 4.0
        )
        overlay.commitAnnotation(arrow)
        overlay.selectedAnnotationIndices = [0]

        let rects = overlay.annotationHandleRects(for: 0)
        XCTAssertEqual(rects.count, 4, "Selected vectors must expose 4 corner handles (TL, TR, BR, BL)")

        // Each handle center must hit-test back to its own corner.
        for (corner, rect) in rects.enumerated() {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let hit = overlay.annotationResizeHandleAt(center)
            XCTAssertEqual(hit?.index, 0)
            XCTAssertEqual(hit?.corner, corner)
        }

        // A point far from the selection must not hit any handle.
        XCTAssertNil(overlay.annotationResizeHandleAt(CGPoint(x: 5, y: 5)))

        // Handles only exist for the select tool — drawing tools create, not resize.
        overlay.tool = .arrow
        let brCenter = CGPoint(x: rects[2].midX, y: rects[2].midY)
        XCTAssertNil(overlay.annotationResizeHandleAt(brCenter))
    }

    func testDragAnnotationCornerScalesVector() {
        let overlay = createTestOverlay()
        overlay.tool = .select
        let arrow = Annotation(
            id: overlay.opLog.nextId,
            kind: .arrow,
            start: CGPoint(x: 150, y: 150),
            end: CGPoint(x: 250, y: 200),
            colorHex: "#ff375f",
            size: 4.0
        )
        overlay.commitAnnotation(arrow)
        overlay.selectedAnnotationIndices = [0]
        let initial = overlay.activeAnnotations[0]

        // Press the bottom-right corner handle (index 2).
        let rects = overlay.annotationHandleRects(for: 0)
        let br = CGPoint(x: rects[2].midX, y: rects[2].midY)
        overlay.mouseDown(with: clickEvent(.leftMouseDown, at: br)!)

        // Drag down-right by 40 points in screen space.
        let dragged = CGPoint(x: br.x + 40, y: br.y + 40)
        overlay.mouseDragged(with: clickEvent(.leftMouseDragged, at: dragged)!)

        // The vector must grow with the anchored (top-left) corner fixed.
        let grown = overlay.activeAnnotations[0]
        XCTAssertGreaterThan(grown.bounds.width, initial.bounds.width)
        XCTAssertGreaterThan(grown.bounds.height, initial.bounds.height)
        XCTAssertEqual(grown.bounds.minX, initial.bounds.minX, accuracy: 0.01)
        XCTAssertEqual(grown.bounds.minY, initial.bounds.minY, accuracy: 0.01)

        // Release commits an .annotate op carrying the resized vector.
        overlay.mouseUp(with: clickEvent(.leftMouseUp, at: dragged)!)
        XCTAssertEqual(overlay.opLog.ops.last?.type, .annotate)
        XCTAssertEqual(overlay.opLog.ops.last?.annotations.first, grown)
    }

    func testAnnotationCornerClickWithoutDragRecordsNoOp() {
        let overlay = createTestOverlay()
        overlay.tool = .select
        let arrow = Annotation(
            id: overlay.opLog.nextId,
            kind: .arrow,
            start: CGPoint(x: 150, y: 150),
            end: CGPoint(x: 250, y: 200),
            colorHex: "#ff375f",
            size: 4.0
        )
        overlay.commitAnnotation(arrow)
        overlay.selectedAnnotationIndices = [0]
        let opsBefore = overlay.opLog.ops.count

        let rects = overlay.annotationHandleRects(for: 0)
        let br = CGPoint(x: rects[2].midX, y: rects[2].midY)
        overlay.mouseDown(with: clickEvent(.leftMouseDown, at: br)!)
        overlay.mouseUp(with: clickEvent(.leftMouseUp, at: br)!)

        XCTAssertEqual(overlay.activeAnnotations[0], arrow, "A press without drag must leave the vector untouched")
        XCTAssertEqual(overlay.opLog.ops.count, opsBefore, "A press without drag must not record an operation")
    }

    // MARK: - Synthetic event helpers

    /// The overlay has no window in tests, so (like the crop tests above)
    /// window Y must be flipped manually against the 600pt test view height.
    private func clickEvent(_ type: NSEvent.EventType, at screenPoint: CGPoint, clickCount: Int = 1) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: CGPoint(x: screenPoint.x, y: 600 - screenPoint.y),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: type == .leftMouseUp ? 0.0 : 1.0
        )
    }
}
