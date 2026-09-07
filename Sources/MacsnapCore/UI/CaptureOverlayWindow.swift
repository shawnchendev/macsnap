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
}
