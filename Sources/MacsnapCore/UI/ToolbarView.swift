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
    public var paletteColors: [String] = PaletteConfig.defaultColors
    public var hoveredAction: String? = nil

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
        list.append(ToolbarItem(action: "style-backdrop", shortcut: "B", tooltip: "Cycle backdrop style (Shift+B toggles shadow)", isTool: false))
        list.append(ToolbarItem(action: "style-canvas", shortcut: "G", tooltip: "Cycle canvas growth: Framed / Overflow / Image", isTool: false))
        list.append(ToolbarItem(action: "divider-2", shortcut: "", tooltip: "", isTool: false))

        // 3. Tools
        list.append(ToolbarItem(action: "tool-select", shortcut: "V", tooltip: "Select, move & scale layers (V)"))
        list.append(ToolbarItem(action: "tool-arrow", shortcut: "A", tooltip: "Arrow (A)"))
        list.append(ToolbarItem(action: "tool-line", shortcut: "L", tooltip: "Straight line (L)"))
        list.append(ToolbarItem(action: "tool-freehand", shortcut: "F", tooltip: "Freehand stroke (F)"))
        list.append(ToolbarItem(action: "tool-highlighter", shortcut: "H", tooltip: "Highlighter: text snap or normal (H)"))
        list.append(ToolbarItem(action: "tool-spotlight", shortcut: "S", tooltip: "Spotlight / Loupe magnifier (S)"))
        list.append(ToolbarItem(action: "tool-marker", shortcut: "C", tooltip: "Numbered step counter (C)"))
        list.append(ToolbarItem(action: "tool-rectangle", shortcut: "R", tooltip: "Rectangle (R, Alt+wheel rounds corners)"))
        list.append(ToolbarItem(action: "tool-ellipse", shortcut: "E", tooltip: "Ellipse (E)"))
        list.append(ToolbarItem(action: "tool-redact", shortcut: "D", tooltip: "Redact: pixelate or solid (D)"))
        list.append(ToolbarItem(action: "tool-cut", shortcut: "X", tooltip: "Cut out horizontal/vertical band (X)"))
        list.append(ToolbarItem(action: "tool-text", shortcut: "T", tooltip: "Text label: pill, outline, plain (T, Shift+T font)"))
        list.append(ToolbarItem(action: "tool-ocr", shortcut: "O", tooltip: "Recognize & copy text (O)"))
        list.append(ToolbarItem(action: "tool-eyedropper", shortcut: "I", tooltip: "Eyedropper color picker (I)"))
        list.append(ToolbarItem(action: "divider-3", shortcut: "", tooltip: "", isTool: false))

        // 4. Palette colors (1 to 8)
        for (i, c) in paletteColors.enumerated() {
            list.append(ToolbarItem(action: "color-\(i+1)", shortcut: "\(i+1)", tooltip: "Color \(i+1)", isTool: false, colorHex: c))
        }
        list.append(ToolbarItem(action: "divider-4", shortcut: "", tooltip: "", isTool: false))

        // 5. Output Actions
        list.append(ToolbarItem(action: "action-copy", shortcut: "⌘C", tooltip: "Copy PNG to clipboard only (⌘C)", isTool: false))
        list.append(ToolbarItem(action: "action-save", shortcut: "⌘S", tooltip: "Save PNG only (⌘S)", isTool: false))
        list.append(ToolbarItem(action: "action-pin", shortcut: "P", tooltip: "Pin capture on screen (P)", isTool: false))
        list.append(ToolbarItem(action: "action-finish", shortcut: "⏎", tooltip: "Copy and Save (Enter)", isTool: false))

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
        let originY = 16.0
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
                    context.setFillColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
                    context.fillPath()
                }

                let iconColor = isSelected ? NSColor.white : (isHovered ? NSColor(white: 0.95, alpha: 1.0) : NSColor(white: 0.75, alpha: 1.0))
                VectorIcons.drawIcon(action: item.action, in: context, bounds: rect, color: iconColor)
                context.restoreGState()
            }
        }
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
}
