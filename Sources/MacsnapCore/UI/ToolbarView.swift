import Foundation
import CoreGraphics
import Cocoa

public struct ToolbarItem: Sendable {
    public var action: String
    public var shortcut: String
    public var tooltip: String
    public var isTool: Bool
    public var colorHex: String?

    public init(action: String, shortcut: String, tooltip: String, isTool: Bool = true, colorHex: String? = nil) {
        self.action = action
        self.shortcut = shortcut
        self.tooltip = tooltip
        self.isTool = isTool
        self.colorHex = colorHex
    }
}

public final class ToolbarView: @unchecked Sendable {
    public private(set) var items: [ToolbarItem] = []
    public var activeToolAction: String = "tool-select"
    public var activeColorHex: String = "#ff375f"
    public var customColorHex: String = "#ff375f"
    public var paletteColors: [String] = PaletteConfig.defaultColors
    public var hoveredAction: String? = nil
    public var safeAreaTop: CGFloat? = nil

    // Color shelf (popover panel below the bar, opened by style-color).
    public var colorShelfOpen: Bool = false
    public var colorShelfHover: ColorShelfHot?
    public static let colorNames = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Black", "White"]

    public enum ColorShelfHot: Equatable, Sendable {
        case preset(Int)
        case custom
        case eyedropper
    }

    public func effectiveSafeAreaTop() -> CGFloat {
        if let explicit = safeAreaTop {
            return explicit
        }
        if let screen = NSScreen.main {
            let inset = screen.safeAreaInsets.top
            if inset > 0 {
                return inset
            }
            if screen.auxiliaryTopLeftArea != nil {
                return 32.0
            }
        }
        return 0.0
    }

    public init() {
        setupItems()
    }

    private func setupItems() {
        var list: [ToolbarItem] = []

        // 1. History
        list.append(ToolbarItem(action: "action-undo", shortcut: "⌘Z", tooltip: "Undo", isTool: false))
        list.append(ToolbarItem(action: "action-redo", shortcut: "⇧⌘Z", tooltip: "Redo", isTool: false))
        list.append(ToolbarItem(action: "divider-1", shortcut: "", tooltip: "", isTool: false))

        // 2. Style & Canvas
        list.append(ToolbarItem(action: "style-backdrop", shortcut: "B", tooltip: "Backdrop Style", isTool: false))
        list.append(ToolbarItem(action: "style-canvas", shortcut: "G", tooltip: "Canvas Growth", isTool: false))
        list.append(ToolbarItem(action: "divider-2", shortcut: "", tooltip: "", isTool: false))

        // 3. Tools
        list.append(ToolbarItem(action: "tool-select", shortcut: "V", tooltip: "Select / Move"))
        list.append(ToolbarItem(action: "tool-arrow", shortcut: "A", tooltip: "Arrow"))
        list.append(ToolbarItem(action: "tool-line", shortcut: "L", tooltip: "Straight Line"))
        list.append(ToolbarItem(action: "tool-freehand", shortcut: "F", tooltip: "Freehand"))
        list.append(ToolbarItem(action: "tool-highlighter", shortcut: "H", tooltip: "Highlighter"))
        list.append(ToolbarItem(action: "tool-spotlight", shortcut: "S", tooltip: "Spotlight / Loupe"))
        list.append(ToolbarItem(action: "tool-marker", shortcut: "C", tooltip: "Step Counter"))
        list.append(ToolbarItem(action: "tool-rectangle", shortcut: "R", tooltip: "Rectangle"))
        list.append(ToolbarItem(action: "tool-ellipse", shortcut: "E", tooltip: "Ellipse"))
        list.append(ToolbarItem(action: "tool-redact", shortcut: "D", tooltip: "Redact"))
        list.append(ToolbarItem(action: "tool-cut", shortcut: "X", tooltip: "Cut Band"))
        list.append(ToolbarItem(action: "tool-text", shortcut: "T", tooltip: "Text Label"))
        list.append(ToolbarItem(action: "tool-ocr", shortcut: "O", tooltip: "OCR Recognition"))
        list.append(ToolbarItem(action: "divider-3", shortcut: "", tooltip: "", isTool: false))

        // 4. Colors: single picker button opening the color shelf below.
        list.append(ToolbarItem(action: "style-color", shortcut: "", tooltip: "Colors"))
        list.append(ToolbarItem(action: "divider-4", shortcut: "", tooltip: "", isTool: false))

        // 5. Output Actions
        list.append(ToolbarItem(action: "action-copy", shortcut: "⌘C", tooltip: "Copy PNG", isTool: false))
        list.append(ToolbarItem(action: "action-save", shortcut: "⌘S", tooltip: "Save PNG", isTool: false))
        list.append(ToolbarItem(action: "action-pin", shortcut: "P", tooltip: "Pin Capture", isTool: false))
        list.append(ToolbarItem(action: "action-finish", shortcut: "⏎", tooltip: "Done (Copy & Save)", isTool: false))
        list.append(ToolbarItem(action: "action-discard", shortcut: "Esc", tooltip: "Discard", isTool: false))

        self.items = list
    }

    public func toolbarRect(screenBounds: CGRect) -> CGRect {
        let itemW: CGFloat = 28.0
        let itemSpacing: CGFloat = 4.0
        let paddingH: CGFloat = 12.0
        let height: CGFloat = 42.0

        var totalW: CGFloat = paddingH * 2
        for item in items {
            if item.action.hasPrefix("divider") {
                totalW += 8.0
            } else if item.action.hasPrefix("color") {
                totalW += 22.0 + itemSpacing
            } else if item.action == "action-finish" {
                totalW += 44.0 + itemSpacing
            } else {
                totalW += itemW + itemSpacing
            }
        }

        let originX = screenBounds.midX - totalW / 2.0
        let topInset = effectiveSafeAreaTop()
        let originY = topInset > 0 ? (topInset + 12.0) : 16.0
        return CGRect(x: originX, y: originY, width: totalW, height: height)
    }

    public func itemRects(screenBounds: CGRect) -> [(item: ToolbarItem, rect: CGRect)] {
        let barRect = toolbarRect(screenBounds: screenBounds)
        var currentX = barRect.minX + 12.0
        let centerY = barRect.midY

        var result: [(ToolbarItem, CGRect)] = []
        for item in items {
            if item.action.hasPrefix("divider") {
                let rect = CGRect(x: currentX + 3, y: centerY - 10, width: 1, height: 20)
                result.append((item, rect))
                currentX += 8.0
            } else if item.action.hasPrefix("color") {
                let size: CGFloat = 20.0
                let rect = CGRect(x: currentX, y: centerY - size / 2.0, width: size, height: size)
                result.append((item, rect))
                currentX += size + 4.0
            } else if item.action == "action-finish" {
                let w: CGFloat = 44.0
                let h: CGFloat = 28.0
                let rect = CGRect(x: currentX, y: centerY - h / 2.0, width: w, height: h)
                result.append((item, rect))
                currentX += w + 4.0
            } else {
                let size: CGFloat = 28.0
                let rect = CGRect(x: currentX, y: centerY - size / 2.0, width: size, height: size)
                result.append((item, rect))
                currentX += size + 4.0
            }
        }
        return result
    }

    public func draw(in context: CGContext, screenBounds: CGRect) {
        let barRect = toolbarRect(screenBounds: screenBounds)

        context.saveGState()

        // Drop shadow for the bar
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor(white: 0, alpha: 0.38).cgColor)

        // Dark translucent bar
        let path = CGPath(roundedRect: barRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor)
        context.fillPath()

        // Border
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        context.restoreGState()

        let itemPairs = itemRects(screenBounds: screenBounds)
        for (item, rect) in itemPairs {
            if item.action.hasPrefix("divider") {
                context.saveGState()
                context.setFillColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
                context.fill(rect)
                context.restoreGState()
                continue
            }

            let isHovered = (hoveredAction == item.action)
            let isSelected = (item.isTool && item.action == activeToolAction)
                || (item.action == "style-color" && colorShelfOpen)

            if item.action.hasPrefix("color") {
                // Color swatch
                if let hex = item.colorHex, let color = NSColor(hex: hex) {
                    context.saveGState()
                    let circlePath = CGPath(ellipseIn: rect, transform: nil)
                    context.addPath(circlePath)
                    context.setFillColor(color.cgColor)
                    context.fillPath()

                    if activeColorHex.lowercased() == hex.lowercased() {
                        context.setStrokeColor(NSColor.white.cgColor)
                        context.setLineWidth(2.5)
                        context.strokeEllipse(in: rect.insetBy(dx: -2, dy: -2))
                    } else if isHovered {
                        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.6).cgColor)
                        context.setLineWidth(1.5)
                        context.strokeEllipse(in: rect.insetBy(dx: -1, dy: -1))
                    }
                    context.restoreGState()
                }
            } else if item.action == "action-finish" {
                // Enter / Finish button
                context.saveGState()
                let btnPath = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                context.addPath(btnPath)
                let btnColor = isHovered ? NSColor.systemGreen.blended(withFraction: 0.2, of: .white)! : NSColor.systemGreen
                context.setFillColor(btnColor.cgColor)
                context.fillPath()

                let font = NSFont.systemFont(ofSize: 11, weight: .bold)
                let str = NSAttributedString(string: "Done", attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white
                ])
                let size = str.size()
                str.draw(at: CGPoint(x: rect.midX - size.width / 2.0, y: rect.midY - size.height / 2.0))
                context.restoreGState()
            } else {
                // Icon button
                context.saveGState()
                if isSelected {
                    let selPath = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                    context.addPath(selPath)
                    context.setFillColor(NSColor(white: 1.0, alpha: 0.22).cgColor)
                    context.fillPath()
                } else if isHovered {
                    let hovPath = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                    context.addPath(hovPath)
                    if item.action == "action-discard" {
                        context.setFillColor(NSColor.systemRed.withAlphaComponent(0.28).cgColor)
                    } else {
                        context.setFillColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
                    }
                    context.fillPath()
                }

                let iconColor: NSColor
                if item.action == "action-discard" && isHovered {
                    iconColor = NSColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
                } else if isSelected {
                    iconColor = NSColor.white
                } else if isHovered {
                    iconColor = NSColor(white: 0.95, alpha: 1.0)
                } else {
                    iconColor = NSColor(white: 0.75, alpha: 1.0)
                }
                VectorIcons.drawIcon(action: item.action, in: context, bounds: rect, color: iconColor)
                context.restoreGState()
            }
        }

        // Draw hover tooltip badge
        if let hoveredAct = hoveredAction,
           let pair = itemPairs.first(where: { $0.item.action == hoveredAct }),
           !pair.item.action.hasPrefix("divider") {
            drawTooltip(for: pair.item, itemRect: pair.rect, barRect: barRect, in: context, screenBounds: screenBounds)
        }

        // Color shelf panel below the bar.
        if colorShelfOpen {
            drawColorShelf(in: context, screenBounds: screenBounds)
        }
    }

    private func drawTooltip(
        for item: ToolbarItem,
        itemRect: CGRect,
        barRect: CGRect,
        in context: CGContext,
        screenBounds: CGRect
    ) {
        context.saveGState()

        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let shortcutFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)

        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: item.tooltip, attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.white
        ]))

        if !item.shortcut.isEmpty {
            attr.append(NSAttributedString(string: "  ·  ", attributes: [
                .font: titleFont,
                .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
            ]))
            attr.append(NSAttributedString(string: item.shortcut, attributes: [
                .font: shortcutFont,
                .foregroundColor: NSColor(white: 0.82, alpha: 1.0)
            ]))
        }

        let textSize = attr.size()
        let padH: CGFloat = 10.0
        let padV: CGFloat = 5.0
        let tooltipW = ceil(textSize.width + padH * 2.0)
        let tooltipH = ceil(textSize.height + padV * 2.0)

        let tooltipY = barRect.maxY + 8.0
        var tooltipX = itemRect.midX - tooltipW / 2.0
        tooltipX = max(12.0, min(screenBounds.maxX - tooltipW - 12.0, tooltipX))

        let tooltipRect = CGRect(x: tooltipX, y: tooltipY, width: tooltipW, height: tooltipH)

        // Drop shadow for the tooltip
        context.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: NSColor(white: 0, alpha: 0.40).cgColor)

        // Tooltip container path with caret pointing up at itemRect.midX
        let caretW: CGFloat = 8.0
        let caretH: CGFloat = 5.0
        let caretX = min(max(itemRect.midX, tooltipRect.minX + 8.0), tooltipRect.maxX - 8.0)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: tooltipRect.minX + 6, y: tooltipRect.minY))
        if caretX - caretW / 2.0 > tooltipRect.minX + 6 {
            path.addLine(to: CGPoint(x: caretX - caretW / 2.0, y: tooltipRect.minY))
        }
        path.addLine(to: CGPoint(x: caretX, y: tooltipRect.minY - caretH))
        path.addLine(to: CGPoint(x: caretX + caretW / 2.0, y: tooltipRect.minY))
        path.addLine(to: CGPoint(x: tooltipRect.maxX - 6, y: tooltipRect.minY))
        path.addArc(tangent1End: CGPoint(x: tooltipRect.maxX, y: tooltipRect.minY),
                    tangent2End: CGPoint(x: tooltipRect.maxX, y: tooltipRect.minY + 6), radius: 6)
        path.addLine(to: CGPoint(x: tooltipRect.maxX, y: tooltipRect.maxY - 6))
        path.addArc(tangent1End: CGPoint(x: tooltipRect.maxX, y: tooltipRect.maxY),
                    tangent2End: CGPoint(x: tooltipRect.maxX - 6, y: tooltipRect.maxY), radius: 6)
        path.addLine(to: CGPoint(x: tooltipRect.minX + 6, y: tooltipRect.maxY))
        path.addArc(tangent1End: CGPoint(x: tooltipRect.minX, y: tooltipRect.maxY),
                    tangent2End: CGPoint(x: tooltipRect.minX, y: tooltipRect.maxY - 6), radius: 6)
        path.addLine(to: CGPoint(x: tooltipRect.minX, y: tooltipRect.minY + 6))
        path.addArc(tangent1End: CGPoint(x: tooltipRect.minX, y: tooltipRect.minY),
                    tangent2End: CGPoint(x: tooltipRect.minX + 6, y: tooltipRect.minY), radius: 6)
        path.closeSubpath()

        // Background fill
        context.addPath(path)
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor)
        context.fillPath()

        // Subtle border
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(path)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        // Text drawing
        let textPoint = CGPoint(
            x: tooltipRect.minX + padH,
            y: tooltipRect.midY - textSize.height / 2.0
        )
        attr.draw(at: textPoint)

        context.restoreGState()
    }

    public func action(at point: CGPoint, screenBounds: CGRect) -> String? {
        let pairs = itemRects(screenBounds: screenBounds)
        for (item, rect) in pairs {
            if !item.action.hasPrefix("divider") && rect.contains(point) {
                return item.action
            }
        }
        return nil
    }

    // MARK: - Color shelf

    public struct ColorShelfLayout: Sendable {
        public var panel: CGRect
        public var presets: [CGRect]
        public var custom: CGRect
        public var eyedropper: CGRect
    }

    /// Panel below the bar anchored under the Colors button (clamped on
    /// screen): 8 presets, custom swatch, eyedropper.
    public func colorShelfLayout(screenBounds: CGRect) -> ColorShelfLayout {
        let barRect = toolbarRect(screenBounds: screenBounds)
        let anchorX: CGFloat
        if let btn = itemRects(screenBounds: screenBounds).first(where: { $0.item.action == "style-color" }) {
            anchorX = btn.rect.midX
        } else {
            anchorX = barRect.midX
        }
        let swatch: CGFloat = 26.0
        let gap: CGFloat = 10.0
        let pad: CGFloat = 12.0
        let dividerZone: CGFloat = gap * 2
        let panelW = pad * 2 + 8 * swatch + 7 * gap + dividerZone + swatch + gap + swatch
        let panelH = pad * 2 + swatch
        var panelX = anchorX - panelW / 2.0
        panelX = min(max(panelX, 12.0), max(12.0, screenBounds.maxX - panelW - 12.0))
        let panel = CGRect(x: panelX, y: barRect.maxY + 8.0, width: panelW, height: panelH)

        var x = panel.minX + pad
        let y = panel.minY + pad
        var presets: [CGRect] = []
        for i in 0..<8 {
            presets.append(CGRect(x: x, y: y, width: swatch, height: swatch))
            x += swatch
            if i < 7 { x += gap }
        }
        x += dividerZone // breathing room with the divider line centered in it
        let custom = CGRect(x: x, y: y, width: swatch, height: swatch)
        x += swatch + gap
        let eyedropper = CGRect(x: x, y: y, width: swatch, height: swatch)
        return ColorShelfLayout(panel: panel, presets: presets, custom: custom, eyedropper: eyedropper)
    }

    public func colorShelfHit(at point: CGPoint, screenBounds: CGRect) -> ColorShelfHot? {
        guard colorShelfOpen else { return nil }
        let layout = colorShelfLayout(screenBounds: screenBounds)
        for (i, rect) in layout.presets.enumerated() {
            if rect.insetBy(dx: -4, dy: -4).contains(point) { return .preset(i) }
        }
        if layout.custom.insetBy(dx: -4, dy: -4).contains(point) { return .custom }
        if layout.eyedropper.insetBy(dx: -4, dy: -4).contains(point) { return .eyedropper }
        return nil
    }

    public func colorName(at index: Int) -> String {
        let hex = index < paletteColors.count ? paletteColors[index] : ""
        let name = index < Self.colorNames.count ? Self.colorNames[index] : "Color \(index + 1)"
        return "\(name) (\(hex))"
    }

    private func drawColorShelf(in context: CGContext, screenBounds: CGRect) {
        let layout = colorShelfLayout(screenBounds: screenBounds)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor(white: 0, alpha: 0.38).cgColor)
        let panelPath = CGPath(roundedRect: layout.panel, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(panelPath)
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(panelPath)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()

        // Divider between presets and custom/eyedropper (centered in its 20pt zone).
        let divX = layout.custom.minX - 10.0
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: divX, y: layout.panel.minY + 10))
        context.addLine(to: CGPoint(x: divX, y: layout.panel.maxY - 10))
        context.strokePath()

        for (i, rect) in layout.presets.enumerated() {
            let hex = i < paletteColors.count ? paletteColors[i] : "#ffffff"
            drawSwatch(in: context, rect: rect,
                       hex: hex,
                       ring: activeColorHex.lowercased() == hex.lowercased(),
                       hovered: colorShelfHover == .preset(i))
        }
        drawSwatch(in: context, rect: layout.custom,
                   hex: customColorHex,
                   ring: activeColorHex.lowercased() == customColorHex.lowercased(),
                   hovered: colorShelfHover == .custom)

        // Eyedropper button.
        context.saveGState()
        if colorShelfHover == .eyedropper {
            let hovPath = CGPath(roundedRect: layout.eyedropper.insetBy(dx: -3, dy: -3), cornerWidth: 7, cornerHeight: 7, transform: nil)
            context.addPath(hovPath)
            context.setFillColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
            context.fillPath()
        }
        VectorIcons.drawIcon(action: "tool-eyedropper", in: context, bounds: layout.eyedropper, color: NSColor(white: 0.85, alpha: 1.0))
        context.restoreGState()

        // Hover tooltip.
        if let hot = colorShelfHover {
            let tip: ToolbarItem
            switch hot {
            case .preset(let i):
                tip = ToolbarItem(action: "shelf-preset", shortcut: "\(i + 1)", tooltip: colorName(at: i), isTool: false)
            case .custom:
                tip = ToolbarItem(action: "shelf-custom", shortcut: "", tooltip: "Custom (\(customColorHex))", isTool: false)
            case .eyedropper:
                tip = ToolbarItem(action: "shelf-eyedropper", shortcut: "I", tooltip: "Eyedropper", isTool: false)
            }
            let barRect = toolbarRect(screenBounds: screenBounds)
            drawTooltip(for: tip, itemRect: layout.panel, barRect: barRect, in: context, screenBounds: screenBounds)
        }
        context.restoreGState()
    }

    private func drawSwatch(in context: CGContext, rect: CGRect, hex: String, ring: Bool, hovered: Bool) {
        guard let color = NSColor(hex: hex) else { return }
        context.saveGState()
        let circlePath = CGPath(ellipseIn: rect, transform: nil)
        context.addPath(circlePath)
        context.setFillColor(color.cgColor)
        context.fillPath()
        if ring {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2.5)
            context.strokeEllipse(in: rect.insetBy(dx: -2, dy: -2))
        } else if hovered {
            context.setStrokeColor(NSColor(white: 1.0, alpha: 0.6).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect.insetBy(dx: -1, dy: -1))
        }
        context.restoreGState()
    }
}
