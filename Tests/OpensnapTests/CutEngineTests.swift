import XCTest
import CoreGraphics
@testable import OpensnapCore

final class CutEngineTests: XCTestCase {
    func testCoordinateShifting() {
        // Cut horizontal band from y=100 to y=150 (height 50)
        let s: Double = 100
        let e: Double = 150

        // Before cut: y = 50 -> unchanged
        XCTAssertEqual(CutEngine.shiftForCut(value: 50, start: s, end: e), 50)

        // Inside cut: y = 120 -> clamped to seam at 100
        XCTAssertEqual(CutEngine.shiftForCut(value: 120, start: s, end: e), 100)

        // After cut: y = 200 -> shifted back by 50 to 150
        XCTAssertEqual(CutEngine.shiftForCut(value: 200, start: s, end: e), 150)
    }

    func testAnnotationShift() {
        var ann = Annotation(
            id: 1,
            kind: .arrow,
            start: CGPoint(x: 50, y: 50),
            end: CGPoint(x: 200, y: 200)
        )
        let cut = CutOp(orientation: .horizontal, sourceStart: 80, sourceEnd: 120, logicalStart: 80, logicalEnd: 120)

        CutEngine.shiftAnnotation(&ann, for: cut)

        XCTAssertEqual(ann.start.y, 50) // before band
        XCTAssertEqual(ann.end.y, 160)   // 200 - 40 = 160
    }

    func testImageBandRemoval() {
        // Create 100x100 synthetic image
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

        // Remove horizontal band from 40 to 60 (20 pixels)
        let cutImg = CutEngine.removeBand(from: img, orientation: .horizontal, start: 40, end: 60)
        XCTAssertEqual(cutImg.width, 100)
        XCTAssertEqual(cutImg.height, 80)

        // Remove vertical band from 30 to 50 (20 pixels)
        let cutImgV = CutEngine.removeBand(from: img, orientation: .vertical, start: 30, end: 50)
        XCTAssertEqual(cutImgV.width, 80)
        XCTAssertEqual(cutImgV.height, 100)
    }
}
