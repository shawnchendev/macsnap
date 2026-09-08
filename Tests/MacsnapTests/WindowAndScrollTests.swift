import XCTest
import Cocoa
import CoreGraphics
@testable import MacsnapCore

final class WindowAndScrollTests: XCTestCase {
    private func target(id: UInt32, rect: CGRect) -> WindowTarget {
        WindowTarget(windowId: id, rect: rect, title: "t\(id)", appName: "App")
    }

    /// 200×100 image, top half red / bottom half blue (top-first rows).
    private func splitOverlay() -> CaptureOverlayView {
        var bytes = [UInt8](repeating: 255, count: 200 * 100 * 4)
        for y in 0..<100 {
            for x in 0..<200 {
                let o = (y * 200 + x) * 4
                bytes[o + 0] = y < 50 ? 255 : 0
                bytes[o + 1] = 0
                bytes[o + 2] = y < 50 ? 0 : 255
                bytes[o + 3] = 255
            }
        }
        let data = CFDataCreate(nil, bytes, bytes.count)!
        let provider = CGDataProvider(data: data)!
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let img = CGImage(
            width: 200, height: 100,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 800,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let capture = ScreenCaptureData(
            screenBounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            scaleFactor: 1.0, pixelSize: CGSize(width: 200, height: 100),
            image: img, windows: []
        )
        return CaptureOverlayView(captureData: capture)
    }

    private func topPixel(of image: CGImage) -> (UInt8, UInt8, UInt8) {
        let data = image.dataProvider!.data! as Data
        return (data[0], data[1], data[2])
    }

    @MainActor
    func testCommitCropsSourceToDraggedRegion() {
        let overlay = splitOverlay()
        overlay.selection = CGRect(x: 0, y: 50, width: 200, height: 50)
        overlay.commitSelection()
        XCTAssertEqual(overlay.phase, .edit)
        // Source is now exactly the dragged bottom half: nothing outside the
        // drag exists anymore, so crop handles cannot reveal it.
        XCTAssertEqual(overlay.pristineSource.width, 200)
        XCTAssertEqual(overlay.pristineSource.height, 50)
        XCTAssertEqual(overlay.selection, CGRect(x: 0, y: 0, width: 200, height: 50))
        XCTAssertEqual(overlay.committedScreenSelection, CGRect(x: 0, y: 50, width: 200, height: 50))
        let px = topPixel(of: overlay.pristineSource)
        XCTAssertEqual(px.0, 0)
        XCTAssertEqual(px.2, 255)
    }

    @MainActor
    func testCommitFullscreenKeepsFullSource() {
        let overlay = splitOverlay()
        overlay.selection = CGRect(x: 0, y: 0, width: 200, height: 100)
        overlay.commitSelection()
        XCTAssertEqual(overlay.pristineSource.width, 200)
        XCTAssertEqual(overlay.pristineSource.height, 100)
        XCTAssertEqual(overlay.selection, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    // MARK: - Eyedropper sampling (top-left-based image coords)

    @MainActor
    func testEyedropperSamplesTopAndBottom() {
        let overlay = splitOverlay() // top red, bottom blue
        let top = overlay.eyedropperHex(image: overlay.pristineSource, x: 100, y: 10)
        let bottom = overlay.eyedropperHex(image: overlay.pristineSource, x: 100, y: 90)
        XCTAssertEqual(top, "#ff0000", "Top pixel must be red, got \(top ?? "nil")")
        XCTAssertEqual(bottom, "#0000ff", "Bottom pixel must be blue, got \(bottom ?? "nil")")
    }

    @MainActor
    func testEyedropperClampsOutOfBounds() {
        let overlay = splitOverlay()
        XCTAssertNotNil(overlay.eyedropperHex(image: overlay.pristineSource, x: -50, y: -50))
        XCTAssertNotNil(overlay.eyedropperHex(image: overlay.pristineSource, x: 9999, y: 9999))
    }

    @MainActor
    func testEyedropperClickPathSamplesImage() {
        let overlay = splitOverlay() // 200×100, top red / bottom blue
        overlay.frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        // Host in a window so AppKit coordinate conversion behaves as in-app.
        let win = NSWindow(
            contentRect: overlay.frame, styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        win.contentView = overlay
        overlay.selection = CGRect(x: 0, y: 0, width: 200, height: 100)
        overlay.phase = .edit
        overlay.setTool(.eyedropper)
        XCTAssertEqual(overlay.tool, .eyedropper)

        // Click the on-screen point that maps to annotation (100, 75),
        // inside the blue bottom half. NSEvent locations are in window
        // (bottom-left) coords; the flipped view's y is height - windowY.
        let imgRect = overlay.imageRectOnScreen()
        let viewX = imgRect.minX + 100 * (imgRect.width / 200.0)
        let viewY = imgRect.minY + 75 * (imgRect.height / 100.0)
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: viewX, y: 956 - viewY),
            modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        overlay.mouseDown(with: event)

        XCTAssertEqual(overlay.activeColorHex, "#0000ff", "Click must sample the blue pixel under the cursor")
        XCTAssertEqual(overlay.tool, .select, "Eyedropper returns to Select after sampling")
        XCTAssertEqual(overlay.ocrStatusMessage, "Eyedropper: #0000ff · next shape uses it")
    }

    func testWindowIndexAtForemost() {
        let windows = [
            target(id: 1, rect: CGRect(x: 0, y: 0, width: 500, height: 500)),
            target(id: 2, rect: CGRect(x: 100, y: 100, width: 200, height: 200)),
        ]
        // List order is front-to-back: first containing window wins.
        XCTAssertEqual(WindowDiscovery.windowIndexAt(point: CGPoint(x: 150, y: 150), in: windows), 0)
        XCTAssertEqual(WindowDiscovery.windowAt(point: CGPoint(x: 150, y: 150), in: windows)?.windowId, 1)
        XCTAssertEqual(WindowDiscovery.windowIndexAt(point: CGPoint(x: 10, y: 10), in: windows), 0)
        XCTAssertNil(WindowDiscovery.windowIndexAt(point: CGPoint(x: 600, y: 600), in: windows))
    }

    func testWindowInDirection() {
        let windows = [
            target(id: 1, rect: CGRect(x: 0, y: 0, width: 100, height: 100)),     // center 50,50
            target(id: 2, rect: CGRect(x: 200, y: 0, width: 100, height: 100)),   // center 250,50
            target(id: 3, rect: CGRect(x: 0, y: 200, width: 100, height: 100)),   // center 50,250
        ]
        XCTAssertEqual(WindowDiscovery.windowInDirection(from: 0, keyCode: 124, in: windows), 1) // Right
        XCTAssertEqual(WindowDiscovery.windowInDirection(from: 0, keyCode: 125, in: windows), 2) // Down (y-down)
        XCTAssertEqual(WindowDiscovery.windowInDirection(from: 1, keyCode: 123, in: windows), 0) // Left
        XCTAssertEqual(WindowDiscovery.windowInDirection(from: 2, keyCode: 126, in: windows), 0) // Up
        // Nothing to the left of window 0: stays.
        XCTAssertEqual(WindowDiscovery.windowInDirection(from: 0, keyCode: 123, in: windows), 0)
        XCTAssertNil(WindowDiscovery.windowInDirection(from: 0, keyCode: 124, in: []))
    }

    func testScrollHUDFrameNeverOverlapsRegion() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let panel = CGSize(width: 430, height: 118)
        // Region in the middle: HUD goes below.
        var region = CGRect(x: 100, y: 500, width: 600, height: 300)
        var frame = ScrollHUDPanel.frameOutside(regionCocoa: region, screenCocoa: screen, panelSize: panel)
        XCTAssertFalse(frame.intersects(region))
        XCTAssertTrue(screen.contains(frame))
        // Region near the bottom (Cocoa minY): HUD goes above.
        region = CGRect(x: 100, y: 0, width: 600, height: 300)
        frame = ScrollHUDPanel.frameOutside(regionCocoa: region, screenCocoa: screen, panelSize: panel)
        XCTAssertFalse(frame.intersects(region))
        XCTAssertTrue(screen.contains(frame))
        // Full-height region: HUD still inside screen, overlap unavoidable but contained.
        region = CGRect(x: 100, y: 0, width: 600, height: 956)
        frame = ScrollHUDPanel.frameOutside(regionCocoa: region, screenCocoa: screen, panelSize: panel)
        XCTAssertTrue(screen.contains(frame))
    }

    func testScrollWorkerInitialSnapshot() {
        let worker = ScrollCaptureWorker(
            regionQuartz: CGRect(x: 0, y: 0, width: 200, height: 200),
            axis: .vertical,
            mode: .manual
        )
        let snap = worker.snapshot()
        XCTAssertEqual(snap.keptFrames, 0)
        XCTAssertFalse(snap.stalled)
        XCTAssertFalse(snap.failed)
        XCTAssertFalse(worker.didExit)
    }

    func testScrollWorkerStopsPromptly() {
        let worker = ScrollCaptureWorker(
            regionQuartz: CGRect(x: 0, y: 0, width: 120, height: 120),
            axis: .vertical,
            mode: .manual
        )
        worker.start()
        Thread.sleep(forTimeInterval: 0.6)
        worker.requestStop()
        worker.waitForExit()
        XCTAssertTrue(worker.didExit)
    }

    @MainActor
    func testEscapeClearsOCRCardWithoutDismissing() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let data = ScreenCaptureData(
            screenBounds: CGRect(x: 0, y: 0, width: 64, height: 64),
            scaleFactor: 1.0, pixelSize: CGSize(width: 64, height: 64),
            image: ctx.makeImage()!, windows: []
        )
        let overlay = CaptureOverlayView(captureData: data)
        overlay.ocrTextResult = "hello"
        overlay.handleEscape()
        XCTAssertNil(overlay.ocrTextResult)
    }

    @MainActor
    func testEscapeCancelsScrollModeChoice() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 1600,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let data = ScreenCaptureData(
            screenBounds: CGRect(x: 0, y: 0, width: 400, height: 400),
            scaleFactor: 1.0, pixelSize: CGSize(width: 400, height: 400),
            image: ctx.makeImage()!, windows: []
        )
        let overlay = CaptureOverlayView(captureData: data)
        overlay.captureKind = .scroll
        overlay.enterScrollModeChoice(region: CGRect(x: 50, y: 50, width: 200, height: 200))
        XCTAssertEqual(overlay.scrollPhase, .modeChoice)
        overlay.handleEscape()
        XCTAssertEqual(overlay.scrollPhase, .idle)
    }

    // MARK: - Menu bar helpers

    func testMacsnapBinaryPrefersSibling() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sibling = dir.appendingPathComponent("macsnap")
        FileManager.default.createFile(atPath: sibling.path, contents: Data())
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sibling.path)
        let found = MenuBarSupport.macsnapBinaryURL(
            ownExecutableURL: dir.appendingPathComponent("macsnap-menubar"),
            pathEnv: "/nonexistent"
        )
        XCTAssertEqual(found?.path, sibling.path)
    }

    func testMacsnapBinaryFallsBackToPATH() {
        let found = MenuBarSupport.macsnapBinaryURL(
            ownExecutableURL: URL(fileURLWithPath: "/nonexistent/macsnap-menubar"),
            pathEnv: "/nonexistent"
        )
        XCTAssertNil(found)
    }

    func testLaunchAgentPlistRoundTrip() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertFalse(MenuBarSupport.isLoginItemEnabled(home: home))
        try! MenuBarSupport.setLoginItemEnabled(true, menubarProgram: "/tmp/fake/macsnap-menubar", home: home)
        XCTAssertTrue(MenuBarSupport.isLoginItemEnabled(home: home))
        let plist = try! String(contentsOf: MenuBarSupport.launchAgentURL(home: home), encoding: .utf8)
        XCTAssertTrue(plist.contains("com.macsnap.menubar"))
        XCTAssertTrue(plist.contains("/tmp/fake/macsnap-menubar"))
        try! MenuBarSupport.setLoginItemEnabled(false, menubarProgram: "", home: home)
        XCTAssertFalse(MenuBarSupport.isLoginItemEnabled(home: home))
    }

    func testShouldOfferSettingsButton() {
        XCTAssertTrue(MenuBarSupport.shouldOfferSettingsButton(stderr: "[macsnap] Screen Recording permission is required."))
        XCTAssertTrue(MenuBarSupport.shouldOfferSettingsButton(stderr: "Failed to capture screen (check Screen Recording permissions)"))
        XCTAssertFalse(MenuBarSupport.shouldOfferSettingsButton(stderr: "Could not acquire instance lock"))
        XCTAssertFalse(MenuBarSupport.shouldOfferSettingsButton(stderr: ""))
    }

    func testDiagLogWritesAndRotates() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        MenuBarSupport.diagLog("first", home: home)
        MenuBarSupport.diagLog("second", home: home)
        let content = try! String(contentsOf: MenuBarSupport.diagLogURL(home: home), encoding: .utf8)
        XCTAssertTrue(content.contains("first"))
        XCTAssertTrue(content.contains("second"))
    }

    func testWelcomeSentinelRoundTrip() {
        let state = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: state) }
        XCTAssertTrue(MenuBarSupport.needsWelcome(stateDir: state))
        MenuBarSupport.markWelcomed(stateDir: state)
        XCTAssertFalse(MenuBarSupport.needsWelcome(stateDir: state))
    }

    func testSaveToRecentShelvesCapture() {
        // Redirect the shelf to a temp dir so the test never touches home.
        let recent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
        defer {
            unsetenv("MACSNAP_RECENT_DIR")
            try? FileManager.default.removeItem(at: recent)
        }
        setenv("MACSNAP_RECENT_DIR", recent.path, 1)

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let shelf = RecentsShelfView()
        XCTAssertTrue(shelf.items.isEmpty)
        shelf.saveToRecent(image: ctx.makeImage()!, log: OperationLog())
        XCTAssertEqual(shelf.items.count, 1)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: recent.path)) ?? []
        XCTAssertTrue(files.contains { $0.hasSuffix(".png") })
        XCTAssertTrue(files.contains { $0.hasSuffix(".png.json") })
    }

    @MainActor
    func testBackdropCycleEnablesGrowth() {
        let overlay = splitOverlay()
        overlay.backdropStyle = .off
        overlay.canvasBoundaryMode = .image
        overlay.cycleBackground() // off -> slate (visible)
        XCTAssertEqual(overlay.backdropStyle, .slate)
        XCTAssertEqual(overlay.canvasBoundaryMode, .framed,
                       "a visible backdrop must grow the canvas or it shows nothing")
    }

    @MainActor
    func testBackdropCycleToInvisibleKeepsBoundary() {
        let overlay = splitOverlay()
        overlay.backdropStyle = .none
        overlay.canvasBoundaryMode = .image
        overlay.cycleBackground() // none -> off (invisible)
        XCTAssertEqual(overlay.backdropStyle, .off)
        XCTAssertEqual(overlay.canvasBoundaryMode, .image)
    }
}
