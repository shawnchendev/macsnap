import Foundation
import CoreGraphics
import Cocoa

public enum MeasurementReadout {
    public static func drawReadout(
        in context: CGContext,
        at point: CGPoint,
        text: String,
        screenBounds: CGRect
    ) {
        guard !text.isEmpty else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attrStr = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ])

        let textSize = attrStr.size()
        let paddingH: CGFloat = 8.0
        let paddingV: CGFloat = 4.0
        let pillWidth = textSize.width + paddingH * 2
        let pillHeight = textSize.height + paddingV * 2

        // Offset slightly down and right from cursor, but keep on screen
        var pillX = point.x + 14
        var pillY = point.y + 14

        if pillX + pillWidth > screenBounds.maxX - 10 {
            pillX = point.x - pillWidth - 14
        }
        if pillY + pillHeight > screenBounds.maxY - 10 {
            pillY = point.y - pillHeight - 14
        }

        let pillRect = CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)

        context.saveGState()

        // Soft drop shadow
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor(white: 0, alpha: 0.35).cgColor)

        // Dark translucent pill
        let pillColor = NSColor(calibratedWhite: 0.12, alpha: 0.88)
        context.setFillColor(pillColor.cgColor)
        let path = CGPath(roundedRect: pillRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()

        // Border
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        context.restoreGState()

        // Draw text
        let textOrigin = CGPoint(x: pillRect.minX + paddingH, y: pillRect.minY + paddingV)
        attrStr.draw(at: textOrigin)
    }
}
