import Foundation
import CoreGraphics
import Cocoa

public final class CaptureOverlayWindow: NSWindow {
    public let overlayView: CaptureOverlayView

    public init(captureData: ScreenCaptureData, appConfig: AppConfig = AppConfig.load()) {
        self.overlayView = CaptureOverlayView(captureData: captureData, appConfig: appConfig)

        let screenFrame = NSScreen.main?.frame ?? CGRect(origin: .zero, size: captureData.screenBounds.size)
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        self.contentView = overlayView
    }

    public override var canBecomeKey: Bool {
        return true
    }

    public override var canBecomeMain: Bool {
        return true
    }

    /// Shows the overlay and guarantees keyboard input reaches it: the view is
    /// made first responder (key events otherwise go to whatever responder is
    /// current, silently breaking Esc and all shortcuts).
    public func showOverlay() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(overlayView)
    }

    // MARK: - Keyboard forwarding safety net

    private var forwardingKey = false

    public override func keyDown(with event: NSEvent) {
        // Reached only when the overlay view isn't first responder. Forward
        // once so Esc/shortcuts keep working; the flag prevents a loop when
        // the view itself declines the key via super.
        if !forwardingKey && firstResponder !== overlayView {
            forwardingKey = true
            overlayView.keyDown(with: event)
            forwardingKey = false
            return
        }
        super.keyDown(with: event)
    }

    public override func cancelOperation(_ sender: Any?) {
        // Esc arriving via the key-binding path (not keyDown).
        overlayView.handleEscape()
    }
}
