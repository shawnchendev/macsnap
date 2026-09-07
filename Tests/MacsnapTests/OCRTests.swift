import Testing
import Foundation
import Cocoa
import Vision
@testable import MacsnapCore

@Suite struct OCRTests {
    @Test func testOCRRecognition() async throws {
        // Create an image with text "Hello Macsnap OCR"
        let width = 400
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }

        // White background
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw black text
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        let font = NSFont.systemFont(ofSize: 28, weight: .bold)
        let str = NSAttributedString(string: "Hello Macsnap OCR", attributes: [
            .font: font,
            .foregroundColor: NSColor.black
        ])
        str.draw(at: CGPoint(x: 20, y: 30))

        guard let image = context.makeImage() else {
            Issue.record("Failed to make image")
            return
        }

        let (text, error) = await OCRService.recognizeText(from: image)
        print("Recognized text: '\(text)', error: '\(String(describing: error))'")
        #expect(text.contains("Hello") || text.contains("Macsnap") || text.contains("OCR"))
    }
}
