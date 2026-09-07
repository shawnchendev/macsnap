import Foundation
import CoreGraphics
import Cocoa

public enum BackdropRenderer {
    public static func paintBackground(
        in context: CGContext,
        bounds: CGRect,
        style: BackdropStyle,
        customImage: CGImage? = nil
    ) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        switch style {
        case .none, .off:
            // Transparent background
            break
        case .slate:
            drawLinearGradient(
                in: context,
                bounds: bounds,
                colors: [
                    NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.23, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0).cgColor
                ]
            )
        case .aurora:
            drawLinearGradient(
                in: context,
                bounds: bounds,
                colors: [
                    NSColor(calibratedRed: 0.02, green: 0.59, blue: 0.41, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 1.0).cgColor
                ]
            )
        case .sunset:
            drawLinearGradient(
                in: context,
                bounds: bounds,
                colors: [
                    NSColor(calibratedRed: 0.96, green: 0.25, blue: 0.37, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.92, green: 0.35, blue: 0.05, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.49, green: 0.18, blue: 0.07, alpha: 1.0).cgColor
                ]
            )
        case .lagoon:
            drawLinearGradient(
                in: context,
                bounds: bounds,
                colors: [
                    NSColor(calibratedRed: 0.02, green: 0.71, blue: 0.83, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.06, green: 0.73, blue: 0.51, alpha: 1.0).cgColor
                ]
            )
        case .violet:
            drawLinearGradient(
                in: context,
                bounds: bounds,
                colors: [
                    NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.96, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.93, green: 0.28, blue: 0.60, alpha: 1.0).cgColor,
                    NSColor(calibratedRed: 0.30, green: 0.11, blue: 0.58, alpha: 1.0).cgColor
                ]
            )
        case .custom:
            if let customImage = customImage {
                drawCoverFit(image: customImage, in: context, bounds: bounds)
            }
        }
    }

    private static func drawLinearGradient(in context: CGContext, bounds: CGRect, colors: [CGColor]) {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else { return }

        let startPoint = CGPoint(x: bounds.minX, y: bounds.maxY)
        let endPoint = CGPoint(x: bounds.maxX, y: bounds.minY)
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
    }

    private static func drawCoverFit(image: CGImage, in context: CGContext, bounds: CGRect) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        guard imgW > 0, imgH > 0 else { return }

        let scale = max(bounds.width / imgW, bounds.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = bounds.midX - drawW / 2.0
        let drawY = bounds.midY - drawH / 2.0

        context.saveGState()
        context.clip(to: bounds)
        context.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        context.restoreGState()
    }

    /// Paints soft key + ambient drop shadow for the captured card
    public static func paintCardShadow(in context: CGContext, cardRect: CGRect) {
        context.saveGState()

        // Ambient shadow
        context.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 16,
            color: NSColor(white: 0.0, alpha: 0.18).cgColor
        )
        let path = CGPath(roundedRect: cardRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor(white: 0.0, alpha: 0.01).cgColor)
        context.fillPath()

        // Key shadow
        context.setShadow(
            offset: CGSize(width: 0, height: -12),
            blur: 32,
            color: NSColor(white: 0.0, alpha: 0.28).cgColor
        )
        context.addPath(path)
        context.fillPath()

        context.restoreGState()
    }
}
