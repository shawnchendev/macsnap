import Testing
import Foundation
import Cocoa
@testable import OpensnapCore

@Suite struct ToolbarRenderTests {
    @Test func renderToolbarSnapshot() throws {
        let width: CGFloat = 1100
        let height: CGFloat = 150
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: Int(width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create CGContext")
            return
        }

        // Emulate flipped AppKit NSView (y = 0 at top)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1.0, y: -1.0)

        // Dark background
        context.setFillColor(CGColor(gray: 0.1, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let toolbar = ToolbarView()
        toolbar.hoveredAction = "tool-arrow"
        let screenBounds = CGRect(x: 0, y: 0, width: width, height: height)

        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        toolbar.draw(in: context, screenBounds: screenBounds)

        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to make image")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to encode PNG")
            return
        }
        let outPath = "/tmp/test_toolbar_hover.png"
        try png.write(to: URL(fileURLWithPath: outPath))
        print("Successfully rendered hovered toolbar to \(outPath)")
    }

    @Test func testDiscardButtonConfiguration() throws {
        let toolbar = ToolbarView()
        guard let item = toolbar.items.first(where: { $0.action == "action-discard" }) else {
            Issue.record("Toolbar is missing action-discard item")
            return
        }
        #expect(item.shortcut == "Esc")
        #expect(item.tooltip == "Discard")
        #expect(!item.isTool)
    }

    @Test func testDiscardButtonHitTest() throws {
        let toolbar = ToolbarView()
        let screenBounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let pairs = toolbar.itemRects(screenBounds: screenBounds)
        guard let discardPair = pairs.first(where: { $0.item.action == "action-discard" }) else {
            Issue.record("action-discard rect not found in toolbar itemRects")
            return
        }

        let center = CGPoint(x: discardPair.rect.midX, y: discardPair.rect.midY)
        let detected = toolbar.action(at: center, screenBounds: screenBounds)
        #expect(detected == "action-discard")
    }

    @Test func testRenderDiscardHoverSnapshot() throws {
        let width: CGFloat = 1100
        let height: CGFloat = 150
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: Int(width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create CGContext")
            return
        }

        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.setFillColor(CGColor(gray: 0.1, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let toolbar = ToolbarView()
        toolbar.hoveredAction = "action-discard"
        let screenBounds = CGRect(x: 0, y: 0, width: width, height: height)

        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        toolbar.draw(in: context, screenBounds: screenBounds)

        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to make image")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to encode PNG")
            return
        }
        let outPath = "/tmp/test_toolbar_discard_hover.png"
        try png.write(to: URL(fileURLWithPath: outPath))
        print("Successfully rendered hovered discard button to \(outPath)")
    }

    @Test func testNotchSafeAreaToolbarPositioning() throws {
        let toolbar = ToolbarView()
        let screenBounds = CGRect(x: 0, y: 0, width: 1470, height: 956)

        // 1. Without notch (external monitor or non-notched MacBook)
        toolbar.safeAreaTop = 0.0
        let noNotchRect = toolbar.toolbarRect(screenBounds: screenBounds)
        #expect(noNotchRect.minY == 16.0)
        #expect(noNotchRect.height == 42.0)
        #expect(noNotchRect.maxY == 58.0)

        // 2. Standard notch (14" / 16" MacBook Pro / M2 Air safeAreaInsets.top = 32.0)
        toolbar.safeAreaTop = 32.0
        let notchRect = toolbar.toolbarRect(screenBounds: screenBounds)
        #expect(notchRect.minY == 44.0) // 32.0 + 12.0 padding below notch
        #expect(notchRect.height == 42.0)
        #expect(notchRect.maxY == 86.0)

        // 3. Scaled notch (e.g. 44.0pt)
        toolbar.safeAreaTop = 44.0
        let scaledNotchRect = toolbar.toolbarRect(screenBounds: screenBounds)
        #expect(scaledNotchRect.minY == 56.0) // 44.0 + 12.0
        #expect(scaledNotchRect.maxY == 98.0)
    }
}
