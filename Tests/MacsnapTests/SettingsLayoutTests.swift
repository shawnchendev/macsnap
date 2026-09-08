import XCTest
import Cocoa
@testable import MacsnapCore

/// Guards the Settings window layout: no ambiguous constraints, sane width.
final class SettingsLayoutTests: XCTestCase {
    @MainActor
    private func makeController() -> SettingsWindowController {
        let controller = SettingsWindowController()
        controller.window?.layoutIfNeeded()
        return controller
    }

    @MainActor
    private func assertContains(_ outer: NSView, _ inner: NSView, _ name: String) {
        XCTAssertFalse(inner.frame.isEmpty, "\(name) must not be empty")
        XCTAssertTrue(
            outer.bounds.contains(inner.frame),
            "\(name) frame \(inner.frame) must be inside \(outer.frame)"
        )
    }

    @MainActor
    private func boxes(in view: NSView) -> [NSBox] {
        view.subviews.compactMap { $0 as? NSBox }
    }

    @MainActor
    private func recorders(in view: NSView) -> [HotkeyRecorderButton] {
        var found: [HotkeyRecorderButton] = []
        func walk(_ v: NSView) {
            for sub in v.subviews {
                if let r = sub as? HotkeyRecorderButton { found.append(r) }
                walk(sub)
            }
        }
        walk(view)
        return found
    }

    @MainActor
    func testSettingsGeometry() {
        let controller = makeController()
        guard let content = controller.window?.contentView else {
            XCTFail("no content view")
            return
        }
        XCTAssertEqual(Double(controller.window?.frame.width ?? 0), 440, accuracy: 0.5)

        // General tab: two cards with exact heights, rows contained.
        controller.showTab(0)
        content.layoutSubtreeIfNeeded()
        let generalBoxes = boxes(in: content.subviews[1])
        XCTAssertEqual(generalBoxes.count, 2)
        XCTAssertEqual(Double(generalBoxes[0].frame.width), 404, accuracy: 0.5)
        XCTAssertEqual(Double(generalBoxes[0].frame.height), 127, accuracy: 0.5)
        XCTAssertEqual(Double(generalBoxes[1].frame.width), 404, accuracy: 0.5)
        XCTAssertEqual(Double(generalBoxes[1].frame.height), 50, accuracy: 0.5)
        XCTAssertTrue(generalBoxes[0].frame.intersects(generalBoxes[1].frame) == false)
        XCTAssertFalse(generalBoxes[0].frame.isEmpty)

        // Hotkeys tab: one card, four recorder pills contained in it.
        controller.showTab(1)
        content.layoutSubtreeIfNeeded()
        let hotkeysPage = content.subviews[2]
        let hotkeysBoxes = boxes(in: hotkeysPage)
        XCTAssertEqual(hotkeysBoxes.count, 1)
        XCTAssertEqual(Double(hotkeysBoxes[0].frame.width), 404, accuracy: 0.5)
        XCTAssertEqual(Double(hotkeysBoxes[0].frame.height), 191, accuracy: 0.5)
        let pills = recorders(in: hotkeysPage)
        XCTAssertEqual(pills.count, 4)
        for (i, pill) in pills.enumerated() {
            XCTAssertEqual(Double(pill.frame.width), 148, accuracy: 0.5)
            assertContains(hotkeysBoxes[0], pill, "recorder \(i)")
        }
    }

    /// One-off visual check: SETTINGS_SNAPSHOT=1 swift test --filter SettingsLayoutTests
    /// writes /tmp/macsnap-settings-*.png for human review.
    @MainActor
    func testRenderSnapshotsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["SETTINGS_SNAPSHOT"] == "1" else { return }
        for (index, tab) in ["general", "hotkeys", "about"].enumerated() {
            let controller = makeController()
            controller.showTab(index)
            guard let window = controller.window, let content = window.contentView else { continue }
            window.layoutIfNeeded()
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bounds = content.bounds
            guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            content.cacheDisplay(in: bounds, to: rep)
            guard let tiff = rep.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: "/tmp/macsnap-settings-\(tab).png")
            try png.write(to: url)
        }
    }
}
