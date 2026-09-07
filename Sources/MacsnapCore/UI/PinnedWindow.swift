import Foundation
import CoreGraphics
import Cocoa
import UniformTypeIdentifiers

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
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        contentView?.needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        contentView?.needsDisplay = true
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
        // Launch macsnap with --file
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

        // Border
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.25).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        // If hovered, draw control overlay bar at top
        if window.isHovered {
            drawControlBar(in: context, bounds: bounds)
        }
    }

    private func drawControlBar(in context: CGContext, bounds: CGRect) {
        let barHeight: CGFloat = 30.0
        let barRect = CGRect(x: 0, y: bounds.maxY - barHeight, width: bounds.width, height: barHeight)

        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.85).cgColor)
        context.fill(barRect)

        // Close (X) button
        let closeRect = CGRect(x: bounds.maxX - 26, y: bounds.maxY - 24, width: 18, height: 18)
        VectorIcons.drawIcon(action: "action-close", in: context, bounds: closeRect, color: .white)

        // Copy button
        let copyRect = CGRect(x: bounds.maxX - 52, y: bounds.maxY - 24, width: 18, height: 18)
        VectorIcons.drawIcon(action: "action-copy", in: context, bounds: copyRect, color: .white)

        // Link button
        let linkRect = CGRect(x: bounds.maxX - 78, y: bounds.maxY - 24, width: 18, height: 18)
        let linkStr = NSAttributedString(string: "🔗", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        linkStr.draw(at: CGPoint(x: linkRect.minX, y: linkRect.minY))

        // Edit button
        let editRect = CGRect(x: 10, y: bounds.maxY - 24, width: 44, height: 18)
        let editStr = NSAttributedString(string: "Edit", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ])
        editStr.draw(at: CGPoint(x: editRect.minX, y: editRect.minY))

        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = pinnedWindow else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let bounds = self.bounds

        if loc.y >= bounds.maxY - 30 {
            // Check buttons
            if loc.x >= bounds.maxX - 28 {
                window.close()
                return
            }
            if loc.x >= bounds.maxX - 54 && loc.x < bounds.maxX - 28 {
                window.copyImageData()
                return
            }
            if loc.x >= bounds.maxX - 80 && loc.x < bounds.maxX - 54 {
                window.copyImagePath()
                return
            }
            if loc.x <= 54 {
                window.editPinnedImage()
                return
            }
        }
        super.mouseDown(with: event)
    }
}
