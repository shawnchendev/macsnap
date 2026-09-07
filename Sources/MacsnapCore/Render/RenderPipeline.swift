import Foundation
import CoreGraphics
import Cocoa

public enum RenderPipeline {
    /// Computes the canvas bounding rect taking annotations and frame padding into account
    public static func computeCanvasRect(
        baseSize: CGSize,
        annotations: [Annotation],
        boundaryMode: CanvasBoundaryMode,
        backdropStyle: BackdropStyle = .none
    ) -> CGRect {
        var canvasRect = CGRect(x: 0, y: 0, width: baseSize.width, height: baseSize.height)
        if boundaryMode == .framed || boundaryMode == .overflow {
            for ann in annotations {
                canvasRect = canvasRect.union(ann.bounds)
            }
            if boundaryMode == .framed && (canvasRect != CGRect(x: 0, y: 0, width: baseSize.width, height: baseSize.height) || (backdropStyle != .none && backdropStyle != .off)) {
                // Add padding frame
                canvasRect = canvasRect.insetBy(dx: -48, dy: -48)
            }
        }
        return canvasRect
    }

    /// Pure rendering function: renders flattened CGImage for export or preview
    public static func renderCapture(
        source: CGImage,
        selection: CGRect,
        annotations: [Annotation],
        backdropStyle: BackdropStyle = .none,
        imageShadow: Bool = true,
        boundaryMode: CanvasBoundaryMode = .framed,
        customBackdrop: CGImage? = nil,
        scale: CGFloat = 1.0
    ) -> CGImage? {
        let srcW = CGFloat(source.width)
        let srcH = CGFloat(source.height)

        var cropRect = selection.standardized
        if cropRect.width <= 0 || cropRect.height <= 0 {
            cropRect = CGRect(x: 0, y: 0, width: srcW / scale, height: srcH / scale)
        }

        // Clamp crop to source bounds to prevent nil
        let cropX = max(0, min(srcW - 1, cropRect.origin.x * scale))
        let cropY = max(0, min(srcH - 1, cropRect.origin.y * scale))
        let cropWidth = max(1, min(srcW - cropX, cropRect.size.width * scale))
        let cropHeight = max(1, min(srcH - cropY, cropRect.size.height * scale))

        let nativeCrop = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        guard let croppedSource = source.cropping(to: nativeCrop) else { return nil }

        let baseWidth = cropWidth / scale
        let baseHeight = cropHeight / scale

        // Calculate grown canvas
        let canvasRect = computeCanvasRect(
            baseSize: CGSize(width: baseWidth, height: baseHeight),
            annotations: annotations,
            boundaryMode: boundaryMode,
            backdropStyle: backdropStyle
        )

        let outWidth = Int(ceil(canvasRect.width * scale))
        let outHeight = Int(ceil(canvasRect.height * scale))
        guard outWidth > 0, outHeight > 0 else { return nil }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: outWidth,
                height: outHeight,
                bitsPerComponent: 8,
                bytesPerRow: outWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }

        // Flip context to top-left coordinate system (y = 0 at top)
        context.translateBy(x: 0, y: CGFloat(outHeight))
        context.scaleBy(x: 1.0, y: -1.0)

        // Scale context to export pixels
        context.scaleBy(x: scale, y: scale)
        // Translate so canvas origin is at (0, 0)
        context.translateBy(x: -canvasRect.minX, y: -canvasRect.minY)

        let fullCanvasLogical = canvasRect

        // 1. Paint background
        if backdropStyle != .none && backdropStyle != .off {
            BackdropRenderer.paintBackground(
                in: context,
                bounds: fullCanvasLogical,
                style: backdropStyle,
                customImage: customBackdrop
            )
        }

        let imageCardRect = CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight)

        // 2. Paint card shadow if enabled and canvas has grown
        if imageShadow && (backdropStyle != .none && backdropStyle != .off) {
            BackdropRenderer.paintCardShadow(in: context, cardRect: imageCardRect)
        }

        // 3. Prepare redacted base image
        let redactedImage = applyRedactions(to: croppedSource, annotations: annotations, selectionSize: CGSize(width: baseWidth, height: baseHeight), scale: scale)

        // Draw cropped screenshot card
        context.saveGState()
        context.translateBy(x: 0, y: imageCardRect.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(redactedImage, in: CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight))
        context.restoreGState()

        // 4. Paint spotlights (loupe)
        paintSpotlights(in: context, baseImage: redactedImage, annotations: annotations, baseSize: CGSize(width: baseWidth, height: baseHeight))

        // 5. Paint standard vector annotations
        for ann in annotations where ann.kind != .redaction && ann.kind != .spotlight {
            paintAnnotation(in: context, annotation: ann)
        }

        return context.makeImage()
    }

    /// Irreversibly destroys pixels in redaction regions
    public static func applyRedactions(
        to source: CGImage,
        annotations: [Annotation],
        selectionSize: CGSize,
        scale: CGFloat
    ) -> CGImage {
        let redactions = annotations.filter { $0.kind == .redaction }
        guard !redactions.isEmpty else { return source }

        let width = source.width
        let height = source.height
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return source }

        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixelData = context.data else { return source }
        let pixelBytes = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for red in redactions {
            let rect = red.bounds
            let x0 = max(0, min(width - 1, Int(rect.minX * scale)))
            let x1 = max(0, min(width - 1, Int(rect.maxX * scale)))
            let y0 = max(0, min(height - 1, Int(rect.minY * scale)))
            let y1 = max(0, min(height - 1, Int(rect.maxY * scale)))
            guard x1 >= x0, y1 >= y0 else { continue }

            if red.redactionStyle == .solid {
                // Pure opaque black
                for y in y0...y1 {
                    let rowOffset = y * width * 4
                    for x in x0...x1 {
                        let p = rowOffset + x * 4
                        pixelBytes[p + 0] = 0   // R
                        pixelBytes[p + 1] = 0   // G
                        pixelBytes[p + 2] = 0   // B
                        pixelBytes[p + 3] = 255 // A
                    }
                }
            } else {
                // Mosaic pixelation averaging actual underlying pixels
                let blockSize = max(8, Int(round(12.0 * scale)))
                for by in stride(from: y0, through: y1, by: blockSize) {
                    for bx in stride(from: x0, through: x1, by: blockSize) {
                        let bxEnd = min(bx + blockSize - 1, x1)
                        let byEnd = min(by + blockSize - 1, y1)

                        // Compute average color in block
                        var totalR = 0, totalG = 0, totalB = 0, count = 0
                        for py in by...byEnd {
                            let rOff = py * width * 4
                            for px in bx...bxEnd {
                                let p = rOff + px * 4
                                totalR += Int(pixelBytes[p + 0])
                                totalG += Int(pixelBytes[p + 1])
                                totalB += Int(pixelBytes[p + 2])
                                count += 1
                            }
                        }
                        if count > 0 {
                            let avgR = UInt8(totalR / count)
                            let avgG = UInt8(totalG / count)
                            let avgB = UInt8(totalB / count)
                            for py in by...byEnd {
                                let rOff = py * width * 4
                                for px in bx...bxEnd {
                                    let p = rOff + px * 4
                                    pixelBytes[p + 0] = avgR
                                    pixelBytes[p + 1] = avgG
                                    pixelBytes[p + 2] = avgB
                                    pixelBytes[p + 3] = 255
                                }
                            }
                        }
                    }
                }
            }
        }

        return context.makeImage() ?? source
    }

    /// Magnifies area under spotlight
    private static func paintSpotlights(
        in context: CGContext,
        baseImage: CGImage,
        annotations: [Annotation],
        baseSize: CGSize
    ) {
        let spotlights = annotations.filter { $0.kind == .spotlight }
        guard !spotlights.isEmpty else { return }

        for spot in spotlights {
            let rect = spot.bounds
            guard rect.width > 4, rect.height > 4 else { continue }

            context.saveGState()

            // Clip to shape
            let path = CGMutablePath()
            switch spot.spotlightShape {
            case .ellipse:
                path.addEllipse(in: rect)
            case .rectangle:
                path.addRect(rect)
            case .rounded:
                path.addRoundedRect(in: rect, cornerWidth: 8, cornerHeight: 8)
            }
            context.addPath(path)
            context.clip()

            // Draw magnified image
            let mag = max(1.2, spot.magnification)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let drawW = baseSize.width * mag
            let drawH = baseSize.height * mag
            let drawX = center.x - (center.x * mag)
            let drawY = center.y - (center.y * mag)

            context.saveGState()
            context.translateBy(x: drawX, y: drawY + drawH)
            context.scaleBy(x: 1.0, y: -1.0)
            context.draw(baseImage, in: CGRect(x: 0, y: 0, width: drawW, height: drawH))
            context.restoreGState()

            context.restoreGState()

            // Draw border ring
            context.saveGState()
            context.setStrokeColor(NSColor(hex: spot.colorHex)?.cgColor ?? NSColor.white.cgColor)
            context.setLineWidth(max(2.0, spot.size))
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// Paints individual annotation
    public static func paintAnnotation(in context: CGContext, annotation: Annotation) {
        context.saveGState()
        let color = NSColor(hex: annotation.colorHex) ?? NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.37, alpha: 1.0)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(annotation.size)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .arrow:
            drawArrow(in: context, from: annotation.start, to: annotation.end, width: annotation.size)

        case .line:
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()

        case .freehand:
            guard annotation.points.count > 1 else { break }
            context.move(to: annotation.points[0])
            for i in 1..<annotation.points.count {
                context.addLine(to: annotation.points[i])
            }
            context.strokePath()

        case .highlighter:
            context.saveGState()
            let highColor = color.withAlphaComponent(0.38)
            context.setStrokeColor(highColor.cgColor)
            context.setLineWidth(annotation.size * 3.5)
            context.setLineCap(.square)

            if annotation.points.count > 1 {
                context.move(to: annotation.points[0])
                for i in 1..<annotation.points.count {
                    context.addLine(to: annotation.points[i])
                }
            } else {
                context.move(to: annotation.start)
                context.addLine(to: annotation.end)
            }
            context.strokePath()
            context.restoreGState()

        case .marker:
            let radius = max(14.0, annotation.size * 3.5)
            let circleRect = CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: circleRect)

            let numStr = "\(annotation.number)"
            let fontSize = max(12.0, radius * 1.1)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
            let luminance = rgbColor.redComponent * 0.299 + rgbColor.greenComponent * 0.587 + rgbColor.blueComponent * 0.114
            let textColor = (luminance > 0.65) ? NSColor.black : NSColor.white

            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let str = NSAttributedString(string: numStr, attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: para
            ])
            let size = str.size()
            let strRect = CGRect(
                x: circleRect.midX - size.width / 2.0,
                y: circleRect.midY - size.height / 2.0,
                width: size.width,
                height: size.height
            )

            NSGraphicsContext.saveGraphicsState()
            let gctx = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = gctx
            str.draw(in: strRect)
            NSGraphicsContext.restoreGraphicsState()

        case .rectangle:
            let rect = annotation.bounds
            let path: CGPath
            if annotation.cornerRadius > 0 {
                path = CGPath(roundedRect: rect, cornerWidth: annotation.cornerRadius, cornerHeight: annotation.cornerRadius, transform: nil)
            } else {
                path = CGPath(rect: rect, transform: nil)
            }
            context.addPath(path)
            if annotation.filled {
                context.fillPath()
            } else {
                context.strokePath()
            }

        case .ellipse:
            let rect = annotation.bounds
            if annotation.filled {
                context.fillEllipse(in: rect)
            } else {
                context.strokeEllipse(in: rect)
            }

        case .text:
            drawTextLabel(in: context, annotation: annotation)

        case .redaction, .spotlight:
            break
        }

        context.restoreGState()
    }

    public static func drawArrow(in context: CGContext, from: CGPoint, to: CGPoint, width: CGFloat) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 2 else { return }

        // Shaft
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()

        // Head
        let headLength = max(14.0, width * 3.5)
        let angle = atan2(dy, dx)
        let arrowAngle: CGFloat = .pi / 6.0

        let p1 = CGPoint(
            x: to.x - headLength * cos(angle - arrowAngle),
            y: to.y - headLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: to.x - headLength * cos(angle + arrowAngle),
            y: to.y - headLength * sin(angle + arrowAngle)
        )

        let head = CGMutablePath()
        head.move(to: to)
        head.addLine(to: p1)
        head.addLine(to: p2)
        head.closeSubpath()
        context.addPath(head)
        context.fillPath()
    }

    private static func drawTextLabel(in context: CGContext, annotation: Annotation) {
        guard !annotation.text.isEmpty else { return }

        let fontSize = max(14.0, annotation.size * 4.0)
        let font = FontManager.shared.font(for: annotation.textFont, size: fontSize)
        let textColor = NSColor(hex: annotation.colorHex) ?? .black

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: para
        ]

        if annotation.textBackground == .plain {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.40)
            shadow.shadowOffset = NSSize(width: 0, height: -1.0)
            shadow.shadowBlurRadius = 2.0
            attributes[.shadow] = shadow
        }

        let attrStr = NSAttributedString(string: annotation.text, attributes: attributes)

        let padding: CGFloat = 8.0
        let textSize = attrStr.size()
        let pillRect = CGRect(
            x: annotation.start.x - padding,
            y: annotation.start.y - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        if annotation.textBackground == .pill {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor(white: 0.0, alpha: 0.22).cgColor)
            let pillColor = NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.96, alpha: 0.96)
            context.setFillColor(pillColor.cgColor)
            let path = CGPath(roundedRect: pillRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        } else if annotation.textBackground == .outline {
            NSGraphicsContext.saveGraphicsState()
            let gctx = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = gctx
            let outlineStr = NSAttributedString(string: annotation.text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.white,
                .strokeWidth: 4.0,
                .paragraphStyle: para
            ])
            outlineStr.draw(at: annotation.start)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        let gctx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = gctx
        attrStr.draw(at: annotation.start)
        NSGraphicsContext.restoreGraphicsState()
    }
}
