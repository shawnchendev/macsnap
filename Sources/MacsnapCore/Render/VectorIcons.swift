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
        // All paths are defined in standard top-down 24x24 coordinate space (matching AppKit isFlipped views)
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
            path.move(to: CGPoint(x: 5, y: 4))
            path.addLine(to: CGPoint(x: 17, y: 15))
            path.addLine(to: CGPoint(x: 12, y: 16))
            path.addLine(to: CGPoint(x: 9, y: 21))
            path.closeSubpath()
            context.addPath(path)
            context.strokePath()

        case "tool-arrow":
            context.move(to: CGPoint(x: 7, y: 17))
            context.addLine(to: CGPoint(x: 17, y: 7))
            context.move(to: CGPoint(x: 7, y: 7))
            context.addLine(to: CGPoint(x: 17, y: 7))
            context.move(to: CGPoint(x: 17, y: 17))
            context.addLine(to: CGPoint(x: 17, y: 7))
            context.strokePath()

        case "tool-line":
            context.move(to: CGPoint(x: 5, y: 19))
            context.addLine(to: CGPoint(x: 19, y: 5))
            context.strokePath()

        case "tool-freehand":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 4, y: 16))
            path.addCurve(to: CGPoint(x: 14, y: 11), control1: CGPoint(x: 7, y: 5), control2: CGPoint(x: 10, y: 20))
            path.addCurve(to: CGPoint(x: 21, y: 7), control1: CGPoint(x: 17, y: 5), control2: CGPoint(x: 18, y: 11))
            context.addPath(path)
            context.strokePath()

        case "tool-highlighter":
            context.setLineWidth(4.5)
            context.move(to: CGPoint(x: 5, y: 16))
            context.addLine(to: CGPoint(x: 19, y: 8))
            context.strokePath()

        case "tool-spotlight":
            context.strokeEllipse(in: CGRect(x: 4, y: 4, width: 13, height: 13))
            context.move(to: CGPoint(x: 15.5, y: 15.5))
            context.addLine(to: CGPoint(x: 20, y: 20))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: 9.25, y: 9.25, width: 2.5, height: 2.5))

        case "tool-marker":
            context.strokeEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16))
            // Crisp vector digit 1
            let stem = CGMutablePath()
            stem.move(to: CGPoint(x: 10, y: 10))
            stem.addLine(to: CGPoint(x: 12, y: 8))
            stem.addLine(to: CGPoint(x: 12, y: 16))
            stem.move(to: CGPoint(x: 9.5, y: 16))
            stem.addLine(to: CGPoint(x: 14.5, y: 16))
            context.addPath(stem)
            context.strokePath()

        case "tool-rectangle":
            let rect = CGRect(x: 4, y: 4, width: 16, height: 16)
            let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(path)
            context.strokePath()

        case "tool-ellipse":
            context.strokeEllipse(in: CGRect(x: 3, y: 6, width: 18, height: 12))

        case "tool-redact":
            let shield = CGMutablePath()
            shield.move(to: CGPoint(x: 12, y: 3))
            shield.addLine(to: CGPoint(x: 20, y: 6))
            shield.addLine(to: CGPoint(x: 19, y: 13))
            shield.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 18.5, y: 17), control2: CGPoint(x: 15.5, y: 20))
            shield.addCurve(to: CGPoint(x: 5, y: 13), control1: CGPoint(x: 8.5, y: 20), control2: CGPoint(x: 5.5, y: 17))
            shield.addLine(to: CGPoint(x: 4, y: 6))
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
            context.stroke(CGRect(x: 5, y: 4, width: 14, height: 5.5))
            context.stroke(CGRect(x: 5, y: 14.5, width: 14, height: 5.5))
            context.setLineDash(phase: 0, lengths: [2, 2])
            context.setLineWidth(1.4)
            context.move(to: CGPoint(x: 5, y: 12))
            context.addLine(to: CGPoint(x: 19, y: 12))
            context.strokePath()

        case "tool-text":
            context.move(to: CGPoint(x: 5, y: 5))
            context.addLine(to: CGPoint(x: 19, y: 5))
            context.move(to: CGPoint(x: 12, y: 5))
            context.addLine(to: CGPoint(x: 12, y: 19))
            context.move(to: CGPoint(x: 9, y: 19))
            context.addLine(to: CGPoint(x: 15, y: 19))
            context.strokePath()

        case "tool-ocr":
            let path = CGMutablePath()
            // 4 scan corners
            path.move(to: CGPoint(x: 9, y: 4))
            path.addLine(to: CGPoint(x: 5, y: 4))
            path.addLine(to: CGPoint(x: 5, y: 8))

            path.move(to: CGPoint(x: 15, y: 4))
            path.addLine(to: CGPoint(x: 19, y: 4))
            path.addLine(to: CGPoint(x: 19, y: 8))

            path.move(to: CGPoint(x: 9, y: 20))
            path.addLine(to: CGPoint(x: 5, y: 20))
            path.addLine(to: CGPoint(x: 5, y: 16))

            path.move(to: CGPoint(x: 15, y: 20))
            path.addLine(to: CGPoint(x: 19, y: 20))
            path.addLine(to: CGPoint(x: 19, y: 16))

            // Scan lines inside
            path.move(to: CGPoint(x: 8, y: 9))
            path.addLine(to: CGPoint(x: 16, y: 9))

            path.move(to: CGPoint(x: 8, y: 13))
            path.addLine(to: CGPoint(x: 16, y: 13))

            path.move(to: CGPoint(x: 8, y: 17))
            path.addLine(to: CGPoint(x: 13, y: 17))

            context.addPath(path)
            context.strokePath()

        case "tool-eyedropper":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 5, y: 19))
            path.addLine(to: CGPoint(x: 8, y: 19))
            path.addLine(to: CGPoint(x: 10, y: 17))
            path.addLine(to: CGPoint(x: 17, y: 10))
            path.addCurve(to: CGPoint(x: 15, y: 7), control1: CGPoint(x: 18.5, y: 8.5), control2: CGPoint(x: 17, y: 6))
            path.addLine(to: CGPoint(x: 14, y: 8))
            path.addLine(to: CGPoint(x: 7, y: 15))
            path.addLine(to: CGPoint(x: 5, y: 17))
            path.closeSubpath()
            context.addPath(path)
            context.strokePath()
            context.fillEllipse(in: CGRect(x: 15.5, y: 5.5, width: 3.5, height: 3.5))

        case "style-backdrop", "background":
            let rect = CGRect(x: 3, y: 4, width: 18, height: 16)
            let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(path)
            context.strokePath()
            context.strokeEllipse(in: CGRect(x: 7, y: 7.5, width: 3, height: 3))
            let mountain = CGMutablePath()
            mountain.move(to: CGPoint(x: 3, y: 17))
            mountain.addLine(to: CGPoint(x: 8, y: 12))
            mountain.addLine(to: CGPoint(x: 11, y: 15))
            mountain.addLine(to: CGPoint(x: 14, y: 12))
            mountain.addLine(to: CGPoint(x: 21, y: 19))
            context.addPath(mountain)
            context.strokePath()

        case "style-canvas", "canvas":
            let inner = CGRect(x: 6.5, y: 6.5, width: 11, height: 11)
            let innerPath = CGPath(roundedRect: inner, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            context.addPath(innerPath)
            context.strokePath()
            // 4 corner expansion brackets
            context.move(to: CGPoint(x: 3, y: 6))
            context.addLine(to: CGPoint(x: 3, y: 3))
            context.addLine(to: CGPoint(x: 6, y: 3))

            context.move(to: CGPoint(x: 18, y: 3))
            context.addLine(to: CGPoint(x: 21, y: 3))
            context.addLine(to: CGPoint(x: 21, y: 6))

            context.move(to: CGPoint(x: 3, y: 18))
            context.addLine(to: CGPoint(x: 3, y: 21))
            context.addLine(to: CGPoint(x: 6, y: 21))

            context.move(to: CGPoint(x: 18, y: 21))
            context.addLine(to: CGPoint(x: 21, y: 21))
            context.addLine(to: CGPoint(x: 21, y: 18))
            context.strokePath()

        case "action-undo", "undo":
            // Left-pointing arrowhead at (4, 9)
            let head = CGMutablePath()
            head.move(to: CGPoint(x: 9, y: 4))
            head.addLine(to: CGPoint(x: 4, y: 9))
            head.addLine(to: CGPoint(x: 9, y: 14))
            context.addPath(head)
            context.strokePath()

            // Smooth arch curving over the top from (4, 9) to (14.5, 9) and down to (11, 20)
            let shaft = CGMutablePath()
            shaft.move(to: CGPoint(x: 4, y: 9))
            shaft.addLine(to: CGPoint(x: 14.5, y: 9))
            shaft.addCurve(to: CGPoint(x: 14.5, y: 20), control1: CGPoint(x: 21.5, y: 9), control2: CGPoint(x: 21.5, y: 20))
            shaft.addLine(to: CGPoint(x: 11, y: 20))
            context.addPath(shaft)
            context.strokePath()

        case "action-redo", "redo":
            // Right-pointing arrowhead at (20, 9)
            let head = CGMutablePath()
            head.move(to: CGPoint(x: 15, y: 4))
            head.addLine(to: CGPoint(x: 20, y: 9))
            head.addLine(to: CGPoint(x: 15, y: 14))
            context.addPath(head)
            context.strokePath()

            // Smooth arch curving over the top from (20, 9) to (9.5, 9) and down to (13, 20)
            let shaft = CGMutablePath()
            shaft.move(to: CGPoint(x: 20, y: 9))
            shaft.addLine(to: CGPoint(x: 9.5, y: 9))
            shaft.addCurve(to: CGPoint(x: 9.5, y: 20), control1: CGPoint(x: 2.5, y: 9), control2: CGPoint(x: 2.5, y: 20))
            shaft.addLine(to: CGPoint(x: 13, y: 20))
            context.addPath(shaft)
            context.strokePath()

        case "action-copy", "copy":
            let front = CGRect(x: 8, y: 8, width: 11, height: 11)
            let frontPath = CGPath(roundedRect: front, cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(frontPath)
            context.strokePath()

            let back = CGMutablePath()
            back.move(to: CGPoint(x: 15, y: 8))
            back.addLine(to: CGPoint(x: 15, y: 5))
            back.addLine(to: CGPoint(x: 5, y: 5))
            back.addLine(to: CGPoint(x: 5, y: 15))
            back.addLine(to: CGPoint(x: 8, y: 15))
            context.addPath(back)
            context.strokePath()

        case "action-save", "save":
            // Arrow pointing down into tray
            context.move(to: CGPoint(x: 12, y: 4))
            context.addLine(to: CGPoint(x: 12, y: 15))
            context.move(to: CGPoint(x: 8, y: 11))
            context.addLine(to: CGPoint(x: 12, y: 15))
            context.addLine(to: CGPoint(x: 16, y: 11))
            let tray = CGMutablePath()
            tray.move(to: CGPoint(x: 5, y: 17))
            tray.addLine(to: CGPoint(x: 5, y: 20))
            tray.addLine(to: CGPoint(x: 19, y: 20))
            tray.addLine(to: CGPoint(x: 19, y: 17))
            context.addPath(tray)
            context.strokePath()

        case "action-pin", "pin":
            let head = CGRect(x: 8, y: 4, width: 8, height: 6)
            let headPath = CGPath(roundedRect: head, cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(headPath)
            context.move(to: CGPoint(x: 5, y: 10))
            context.addLine(to: CGPoint(x: 19, y: 10))
            context.move(to: CGPoint(x: 12, y: 10))
            context.addLine(to: CGPoint(x: 12, y: 20))
            context.strokePath()

        case "action-discard", "discard", "action-close", "close":
            context.move(to: CGPoint(x: 6, y: 6))
            context.addLine(to: CGPoint(x: 18, y: 18))
            context.move(to: CGPoint(x: 18, y: 6))
            context.addLine(to: CGPoint(x: 6, y: 18))
            context.strokePath()

        case "style-color", "color", "palette":
            // Artist palette: outer ring, thumb hole, three paint dots.
            context.strokeEllipse(in: CGRect(x: 4, y: 5, width: 16, height: 15))
            context.strokeEllipse(in: CGRect(x: 14.5, y: 14.5, width: 3.5, height: 3.5))
            context.fillEllipse(in: CGRect(x: 7.2, y: 8.2, width: 3.2, height: 3.2))
            context.fillEllipse(in: CGRect(x: 11.4, y: 7.2, width: 3.2, height: 3.2))
            context.fillEllipse(in: CGRect(x: 8.2, y: 12.4, width: 3.2, height: 3.2))

        default:
            context.stroke(CGRect(x: 4, y: 4, width: 16, height: 16))
        }

        context.restoreGState()
    }
}
