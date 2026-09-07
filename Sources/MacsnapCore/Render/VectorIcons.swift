import Foundation
import CoreGraphics
import Cocoa

public enum VectorIcons {
    public static func drawIcon(
        action: String,
        in context: CGContext,
        bounds: CGRect,
        color: NSColor = .white
    ) {
        context.saveGState()

        let iconSize: CGFloat = 18.0
        let originX = bounds.midX - iconSize / 2.0
        let originY = bounds.midY - iconSize / 2.0

        context.translateBy(x: originX, y: originY)
        // Flip vertically if context is AppKit-based or top-down
        let scale = iconSize / 24.0
        context.scaleBy(x: scale, y: scale)

        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch action {
        case "tool-select":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 5, y: 20))
            path.addLine(to: CGPoint(x: 17, y: 9))
            path.addLine(to: CGPoint(x: 12, y: 8))
            path.addLine(to: CGPoint(x: 9, y: 3))
            path.closeSubpath()
            context.addPath(path)
            context.strokePath()

        case "tool-arrow":
            context.move(to: CGPoint(x: 7, y: 7))
            context.addLine(to: CGPoint(x: 17, y: 17))
            context.move(to: CGPoint(x: 7, y: 17))
            context.addLine(to: CGPoint(x: 17, y: 17))
            context.move(to: CGPoint(x: 17, y: 7))
            context.addLine(to: CGPoint(x: 17, y: 17))
            context.strokePath()

        case "tool-line":
            context.move(to: CGPoint(x: 5, y: 5))
            context.addLine(to: CGPoint(x: 19, y: 19))
            context.strokePath()

        case "tool-freehand":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 4, y: 8))
            path.addCurve(to: CGPoint(x: 14, y: 13), control1: CGPoint(x: 7, y: 19), control2: CGPoint(x: 10, y: 4))
            path.addCurve(to: CGPoint(x: 21, y: 17), control1: CGPoint(x: 17, y: 19), control2: CGPoint(x: 18, y: 13))
            context.addPath(path)
            context.strokePath()

        case "tool-highlighter":
            context.setLineWidth(4.5)
            context.move(to: CGPoint(x: 5, y: 8))
            context.addLine(to: CGPoint(x: 19, y: 16))
            context.strokePath()

        case "tool-spotlight":
            context.strokeEllipse(in: CGRect(x: 4, y: 7, width: 13, height: 13))
            context.move(to: CGPoint(x: 15.5, y: 8.5))
            context.addLine(to: CGPoint(x: 20, y: 4))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: 9, y: 12, width: 3, height: 3))

        case "tool-marker":
            context.strokeEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16))
            let font = NSFont.systemFont(ofSize: 11, weight: .bold)
            let str = NSAttributedString(string: "1", attributes: [
                .font: font,
                .foregroundColor: color
            ])
            let strRect = CGRect(x: 8.5, y: 4, width: 10, height: 14)
            str.draw(in: strRect)

        case "tool-rectangle":
            let rect = CGRect(x: 4, y: 4, width: 16, height: 16)
            let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(path)
            context.strokePath()

        case "tool-ellipse":
            context.strokeEllipse(in: CGRect(x: 3, y: 6, width: 18, height: 12))

        case "tool-redact":
            let shield = CGMutablePath()
            shield.move(to: CGPoint(x: 12, y: 21))
            shield.addLine(to: CGPoint(x: 20, y: 18))
            shield.addLine(to: CGPoint(x: 19, y: 11))
            shield.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 18.5, y: 7), control2: CGPoint(x: 15.5, y: 4))
            shield.addCurve(to: CGPoint(x: 5, y: 11), control1: CGPoint(x: 8.5, y: 4), control2: CGPoint(x: 5.5, y: 7))
            shield.addLine(to: CGPoint(x: 4, y: 18))
            shield.closeSubpath()
            context.addPath(shield)
            context.strokePath()

            // Pixel grid inside
            for y in stride(from: 8, through: 14, by: 3) {
                for x in stride(from: 8, through: 14, by: 3) {
                    if (x + y) % 2 == 0 {
                        context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 2.5, height: 2.5))
                    }
                }
            }

        case "tool-cut":
            context.stroke(CGRect(x: 5, y: 14.5, width: 14, height: 5.5))
            context.stroke(CGRect(x: 5, y: 4, width: 14, height: 5.5))
            context.setLineDash(phase: 0, lengths: [2, 2])
            context.setLineWidth(1.4)
            context.move(to: CGPoint(x: 5, y: 12))
            context.addLine(to: CGPoint(x: 19, y: 12))
            context.strokePath()

        case "tool-text":
            context.move(to: CGPoint(x: 5, y: 19))
            context.addLine(to: CGPoint(x: 19, y: 19))
            context.move(to: CGPoint(x: 12, y: 19))
            context.addLine(to: CGPoint(x: 12, y: 5))
            context.move(to: CGPoint(x: 9, y: 5))
            context.addLine(to: CGPoint(x: 15, y: 5))
            context.strokePath()

        case "tool-ocr":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 5, y: 17))
            path.addLine(to: CGPoint(x: 5, y: 20))
            path.addLine(to: CGPoint(x: 8, y: 20))

            path.move(to: CGPoint(x: 16, y: 20))
            path.addLine(to: CGPoint(x: 19, y: 20))
            path.addLine(to: CGPoint(x: 19, y: 17))

            path.move(to: CGPoint(x: 19, y: 7))
            path.addLine(to: CGPoint(x: 19, y: 4))
            path.addLine(to: CGPoint(x: 16, y: 4))

            path.move(to: CGPoint(x: 8, y: 4))
            path.addLine(to: CGPoint(x: 5, y: 4))
            path.addLine(to: CGPoint(x: 5, y: 7))
            context.addPath(path)
            context.strokePath()

            let font = NSFont.systemFont(ofSize: 9, weight: .bold)
            let str = NSAttributedString(string: "A", attributes: [
                .font: font,
                .foregroundColor: color
            ])
            str.draw(in: CGRect(x: 8.5, y: 6, width: 8, height: 12))

        case "tool-eyedropper":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 6, y: 6))
            path.addLine(to: CGPoint(x: 4, y: 4))
            path.addLine(to: CGPoint(x: 8, y: 4))
            path.addLine(to: CGPoint(x: 17, y: 13))
            path.addLine(to: CGPoint(x: 19, y: 17))
            path.addLine(to: CGPoint(x: 17, y: 19))
            path.addLine(to: CGPoint(x: 13, y: 17))
            path.closeSubpath()
            context.addPath(path)
            context.strokePath()

        case "action-undo":
            context.move(to: CGPoint(x: 6, y: 12))
            context.addLine(to: CGPoint(x: 11, y: 17))
            context.move(to: CGPoint(x: 6, y: 12))
            context.addLine(to: CGPoint(x: 11, y: 7))
            context.move(to: CGPoint(x: 6, y: 12))
            context.addArc(center: CGPoint(x: 14, y: 12), radius: 6, startAngle: .pi, endAngle: 0, clockwise: false)
            context.strokePath()

        case "action-redo":
            context.move(to: CGPoint(x: 18, y: 12))
            context.addLine(to: CGPoint(x: 13, y: 17))
            context.move(to: CGPoint(x: 18, y: 12))
            context.addLine(to: CGPoint(x: 13, y: 7))
            context.move(to: CGPoint(x: 18, y: 12))
            context.addArc(center: CGPoint(x: 10, y: 12), radius: 6, startAngle: 0, endAngle: .pi, clockwise: true)
            context.strokePath()

        case "action-copy":
            context.stroke(CGRect(x: 8, y: 8, width: 11, height: 12))
            context.stroke(CGRect(x: 5, y: 4, width: 11, height: 12))

        case "action-save":
            context.stroke(CGRect(x: 5, y: 4, width: 14, height: 16))
            context.move(to: CGPoint(x: 8, y: 12))
            context.addLine(to: CGPoint(x: 12, y: 8))
            context.addLine(to: CGPoint(x: 16, y: 12))
            context.move(to: CGPoint(x: 12, y: 8))
            context.addLine(to: CGPoint(x: 12, y: 17))
            context.strokePath()

        case "action-pin":
            context.move(to: CGPoint(x: 12, y: 20))
            context.addLine(to: CGPoint(x: 12, y: 13))
            context.stroke(CGRect(x: 7, y: 7, width: 10, height: 6))
            context.move(to: CGPoint(x: 12, y: 7))
            context.addLine(to: CGPoint(x: 12, y: 4))
            context.strokePath()

        case "action-close":
            context.move(to: CGPoint(x: 6, y: 6))
            context.addLine(to: CGPoint(x: 18, y: 18))
            context.move(to: CGPoint(x: 6, y: 18))
            context.addLine(to: CGPoint(x: 18, y: 6))
            context.strokePath()

        default:
            context.stroke(CGRect(x: 4, y: 4, width: 16, height: 16))
        }

        context.restoreGState()
    }
}
