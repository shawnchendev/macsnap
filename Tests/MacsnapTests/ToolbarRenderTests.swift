import Testing
import Foundation
import Cocoa
@testable import MacsnapCore

@Suite struct ToolbarRenderTests {
    @Test func renderToolbarSnapshot() throws {
        let width: CGFloat = 1100
        let height: CGFloat = 110
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
}
