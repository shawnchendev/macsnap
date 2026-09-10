import Foundation
import CoreGraphics
import Cocoa
import UniformTypeIdentifiers

private enum PinnedButtonIcon {
    case close, copy, link, edit

    var symbolName: String {
        switch self {
        case .close: return "xmark"
        case .copy: return "doc.on.doc"
        case .link: return "link"
        case .edit: return "pencil"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .close: return "Close"
        case .copy: return "Copy Image"
        case .link: return "Copy Link"
        case .edit: return "Edit"
        }
    }

    func image(size: CGFloat, color: NSColor = .white) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(config) else { return nil }

        // Create a tinted version using template rendering
        let tinted = NSImage(size: baseImage.size)
        tinted.lockFocus()
        // Draw the base image as a template, then apply color
        baseImage.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        // Apply color using sourceAtop to tint the non-transparent pixels
        color.set()
        let rect = NSRect(origin: .zero, size: baseImage.size)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
}

public final class PinnedWindow: NSPanel, NSDraggingSource {
    public let imageURL: URL
    public let logURL: URL
    var cgImage: CGImage
    var isHovered: Bool = false
    private var imageRatio: CGFloat = 1.0
    private var trackingArea: NSTrackingArea?

    public init(imageURL: URL, logURL: URL, image: CGImage) {
        self.imageURL = imageURL
        self.logURL = logURL
        self.cgImage = image
        self.imageRatio = CGFloat(image.width) / max(1.0, CGFloat(image.height))

        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let initialW = min(420.0, screenFrame.width * 0.33)
        let initialH = initialW / imageRatio
        let initialRect = CGRect(
            x: screenFrame.maxX - initialW - 24,
            y: screenFrame.minY + 24,
            width: initialW,
            height: initialH
        )

        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        let contentView = PinnedContentView(pinnedWindow: self)
        self.contentView = contentView

        setupTracking()
    }

    private func setupTracking() {
        if let ta = trackingArea {
            contentView?.removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(
            rect: contentView?.bounds ?? .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView?.addTrackingArea(ta)
        self.trackingArea = ta

        // Accept mouse moved events
        self.acceptsMouseMovedEvents = true
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        contentView?.needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        contentView?.needsDisplay = true
    }

    public override func mouseMoved(with event: NSEvent) {
        contentView?.mouseMoved(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        // Resize with wheel preserving aspect ratio
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.5 else { return }

        let factor: CGFloat = delta > 0 ? 1.05 : 0.95
        var frame = self.frame
        let newW = min(max(150.0, frame.width * factor), 900.0)
        let newH = newW / imageRatio

        frame.size = CGSize(width: newW, height: newH)
        self.setFrame(frame, display: true, animate: false)
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            self.close()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            _ = ScreenCaptureEngine.copyImageToClipboard(cgImage)
        } else {
            super.keyDown(with: event)
        }
    }

    public func editPinnedImage() {
        self.close()
        // Launch opensnap with --file
        let appPath = ProcessInfo.processInfo.arguments[0]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: appPath)
        process.arguments = ["--file", imageURL.path]
        try? process.run()
    }

    public func copyImagePath() {
        _ = ScreenCaptureEngine.copyTextToClipboard(imageURL.path)
    }

    public func copyImageData() {
        _ = ScreenCaptureEngine.copyImageToClipboard(cgImage)
    }

    // Drag-and-drop source
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}

final class PinnedContentView: NSView {
    private weak var pinnedWindow: PinnedWindow?
    private var hoveredButton: ButtonType?

    private typealias ButtonType = PinnedButtonIcon

    init(pinnedWindow: PinnedWindow) {
        self.pinnedWindow = pinnedWindow
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let window = pinnedWindow else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds
        let cornerRadius: CGFloat = 8.0
        let path = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        context.saveGState()

        // Card clipping
        context.addPath(path)
        context.clip()

        // Draw image
        context.draw(window.cgImage, in: bounds)

        context.restoreGState()

        // Border - adapts to light/dark mode
        let borderColor = NSColor.separatorColor.cgColor
        context.setStrokeColor(borderColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        // If hovered, draw control overlay bar at top
        if window.isHovered {
            drawControlBar(in: context, bounds: bounds)
        }
    }

    private func drawControlBar(in context: CGContext, bounds: CGRect) {
        let barHeight: CGFloat = 36.0
        let barRect = CGRect(x: 0, y: bounds.maxY - barHeight, width: bounds.width, height: barHeight)

        context.saveGState()

        // Background using system material - adapts to light/dark mode
        let barBgColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
        context.setFillColor(barBgColor)
        context.fill(barRect)

        // Subtle top border on the bar - adapts to light/dark mode
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 0, y: barRect.maxY))
        context.addLine(to: CGPoint(x: bounds.width, y: barRect.maxY))
        context.strokePath()

        let buttonSize: CGFloat = 22.0
        let iconSize: CGFloat = 14.0
        let buttonY = bounds.maxY - barHeight + (barHeight - buttonSize) / 2.0
        let rightPadding: CGFloat = 10.0
        let spacing: CGFloat = 8.0

        // Calculate button positions from right to left
        var currentX = bounds.maxX - rightPadding - buttonSize

        // Close button
        let closeRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
        drawButton(icon: .close, rect: closeRect, context: context, iconSize: iconSize, isHovered: hoveredButton == .close)

        currentX -= spacing + buttonSize

        // Copy button
        let copyRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
        drawButton(icon: .copy, rect: copyRect, context: context, iconSize: iconSize, isHovered: hoveredButton == .copy)

        currentX -= spacing + buttonSize

        // Link button (copies file path to clipboard)
        let linkRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
        drawButton(icon: .link, rect: linkRect, context: context, iconSize: iconSize, isHovered: hoveredButton == .link)

        // Edit button on the left (opens in full editor)
        let editRect = CGRect(x: 14, y: buttonY, width: buttonSize, height: buttonSize)
        drawButton(icon: .edit, rect: editRect, context: context, iconSize: iconSize, isHovered: hoveredButton == .edit)

        context.restoreGState()
    }

    private func drawButton(icon: PinnedButtonIcon, rect: CGRect, context: CGContext, iconSize: CGFloat, isHovered: Bool) {
        // Button background on hover - adapts to light/dark mode
        if isHovered {
            context.saveGState()
            let bgPath = CGPath(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerWidth: 6, cornerHeight: 6, transform: nil)
            context.addPath(bgPath)
            context.setFillColor(NSColor.selectedControlColor.withAlphaComponent(0.3).cgColor)
            context.fillPath()
            context.restoreGState()
        }

        // Draw system symbol icon - use controlTextColor which contrasts with controlBackgroundColor
        let iconColor: NSColor = .controlTextColor
        guard let image = icon.image(size: iconSize, color: iconColor) else { return }
        let iconRect = CGRect(
            x: rect.midX - iconSize / 2,
            y: rect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isHovered ? 1.0 : 0.75)
    }

    override func mouseMoved(with event: NSEvent) {
        guard pinnedWindow?.isHovered == true else {
            if hoveredButton != nil {
                hoveredButton = nil
                needsDisplay = true
            }
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        let bounds = self.bounds
        let barHeight: CGFloat = 36.0

        if loc.y >= bounds.maxY - barHeight {
            let buttonSize: CGFloat = 22.0
            let buttonY = bounds.maxY - barHeight + (barHeight - buttonSize) / 2.0
            let rightPadding: CGFloat = 10.0
            let spacing: CGFloat = 8.0

            var currentX = bounds.maxX - rightPadding - buttonSize

            let closeRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
            currentX -= spacing + buttonSize
            let copyRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
            currentX -= spacing + buttonSize
            let linkRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
            let editRect = CGRect(x: 14, y: buttonY, width: buttonSize, height: buttonSize)

            let newHovered: ButtonType?
            if closeRect.contains(loc) { newHovered = .close }
            else if copyRect.contains(loc) { newHovered = .copy }
            else if linkRect.contains(loc) { newHovered = .link }
            else if editRect.contains(loc) { newHovered = .edit }
            else { newHovered = nil }

            if newHovered != hoveredButton {
                hoveredButton = newHovered
                needsDisplay = true
            }
        } else if hoveredButton != nil {
            hoveredButton = nil
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredButton != nil {
            hoveredButton = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = pinnedWindow else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let bounds = self.bounds
        let barHeight: CGFloat = 36.0

        if loc.y >= bounds.maxY - barHeight {
            let buttonSize: CGFloat = 22.0
            let buttonY = bounds.maxY - barHeight + (barHeight - buttonSize) / 2.0
            let rightPadding: CGFloat = 10.0
            let spacing: CGFloat = 8.0

            var currentX = bounds.maxX - rightPadding - buttonSize

            let closeRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
            currentX -= spacing + buttonSize
            let copyRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
            currentX -= spacing + buttonSize
            let linkRect = CGRect(x: currentX, y: buttonY, width: buttonSize, height: buttonSize)
            let editRect = CGRect(x: 14, y: buttonY, width: buttonSize, height: buttonSize)

            if closeRect.contains(loc) {
                window.close()
                return
            }
            if copyRect.contains(loc) {
                window.copyImageData()
                return
            }
            if linkRect.contains(loc) {
                window.copyImagePath()
                return
            }
            if editRect.contains(loc) {
                window.editPinnedImage()
                return
            }
        }
        super.mouseDown(with: event)
    }
}
