import XCTest
import Cocoa
@testable import MacsnapCore

final class ToolbarShelfTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1470, height: 956)

    func testPaletteButtonReplacesSwatches() {
        let toolbar = ToolbarView()
        XCTAssertTrue(toolbar.items.contains { $0.action == "style-color" })
        XCTAssertFalse(toolbar.items.contains { $0.action.hasPrefix("color-") })
        XCTAssertFalse(toolbar.items.contains { $0.action == "tool-eyedropper" })
        XCTAssertFalse(toolbar.colorShelfOpen)
    }

    func testShapeButtonReplacesShapeTools() {
        let toolbar = ToolbarView()
        XCTAssertTrue(toolbar.items.contains { $0.action == "tool-shape" })
        XCTAssertFalse(toolbar.items.contains { $0.action == "tool-rectangle" })
        XCTAssertFalse(toolbar.items.contains { $0.action == "tool-ellipse" })
        XCTAssertFalse(toolbar.shapeShelfOpen)
        XCTAssertFalse(toolbar.shapeFilled)
    }

    func testShapeToolbarIconFollowsActiveTool() {
        let toolbar = ToolbarView()
        XCTAssertEqual(toolbar.shapeToolbarIcon(), "tool-rectangle", "rectangle is the initial selection")
        toolbar.activeToolAction = "tool-rectangle"
        XCTAssertEqual(toolbar.shapeToolbarIcon(), "tool-rectangle")
        toolbar.activeToolAction = "tool-ellipse"
        XCTAssertEqual(toolbar.shapeToolbarIcon(), "tool-ellipse")
        toolbar.activeToolAction = "tool-arrow"
        XCTAssertEqual(toolbar.shapeToolbarIcon(), "tool-rectangle", "non-shape tools fall back to rectangle")
    }

    func testShelfLayoutInsideScreen() {
        let toolbar = ToolbarView()
        let layout = toolbar.colorShelfLayout(screenBounds: bounds)
        XCTAssertTrue(bounds.contains(layout.panel), "panel must be on screen: \(layout.panel)")
        XCTAssertEqual(layout.presets.count, 8)
        for rect in layout.presets + [layout.custom, layout.eyedropper] {
            XCTAssertTrue(layout.panel.contains(rect), "\(rect) must be inside panel")
        }
        // Presets ordered left to right without overlap.
        for (a, b) in zip(layout.presets, layout.presets.dropFirst()) {
            XCTAssertLessThanOrEqual(a.maxX, b.minX)
        }
        XCTAssertLessThanOrEqual(layout.presets.last!.maxX, layout.custom.minX)
        XCTAssertLessThanOrEqual(layout.custom.maxX, layout.eyedropper.minX)
    }

    func testShelfHitTestGatedOnOpen() {
        let toolbar = ToolbarView()
        let layout = toolbar.colorShelfLayout(screenBounds: bounds)
        XCTAssertNil(toolbar.colorShelfHit(at: CGPoint(x: layout.presets[3].midX, y: layout.presets[3].midY), screenBounds: bounds))
        toolbar.colorShelfOpen = true
        XCTAssertEqual(toolbar.colorShelfHit(at: CGPoint(x: layout.presets[3].midX, y: layout.presets[3].midY), screenBounds: bounds), .preset(3))
        XCTAssertEqual(toolbar.colorShelfHit(at: CGPoint(x: layout.custom.midX, y: layout.custom.midY), screenBounds: bounds), .custom)
        XCTAssertEqual(toolbar.colorShelfHit(at: CGPoint(x: layout.eyedropper.midX, y: layout.eyedropper.midY), screenBounds: bounds), .eyedropper)
        XCTAssertNil(toolbar.colorShelfHit(at: CGPoint(x: 10, y: 500), screenBounds: bounds))
    }

    func testShapeShelfLayoutInsideScreen() {
        let toolbar = ToolbarView()
        let layout = toolbar.shapeShelfLayout(screenBounds: bounds)
        XCTAssertTrue(bounds.contains(layout.panel), "panel must be on screen: \(layout.panel)")
        for rect in [layout.rectangle, layout.ellipse, layout.filled] {
            XCTAssertTrue(layout.panel.contains(rect), "\(rect) must be inside panel")
        }
        XCTAssertLessThanOrEqual(layout.rectangle.maxX, layout.ellipse.minX)
        XCTAssertLessThanOrEqual(layout.ellipse.maxX, layout.filled.minX)
    }

    func testShapeShelfHitTestGatedOnOpen() {
        let toolbar = ToolbarView()
        let layout = toolbar.shapeShelfLayout(screenBounds: bounds)
        XCTAssertNil(toolbar.shapeShelfHit(at: CGPoint(x: layout.rectangle.midX, y: layout.rectangle.midY), screenBounds: bounds))
        toolbar.shapeShelfOpen = true
        XCTAssertEqual(toolbar.shapeShelfHit(at: CGPoint(x: layout.rectangle.midX, y: layout.rectangle.midY), screenBounds: bounds), .rectangle)
        XCTAssertEqual(toolbar.shapeShelfHit(at: CGPoint(x: layout.ellipse.midX, y: layout.ellipse.midY), screenBounds: bounds), .ellipse)
        XCTAssertEqual(toolbar.shapeShelfHit(at: CGPoint(x: layout.filled.midX, y: layout.filled.midY), screenBounds: bounds), .filled)
        XCTAssertNil(toolbar.shapeShelfHit(at: CGPoint(x: 10, y: 500), screenBounds: bounds))
    }
}
