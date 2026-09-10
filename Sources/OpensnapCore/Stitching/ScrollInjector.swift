import Foundation
import CoreGraphics

public enum ScrollInjector {
    /// Injects a scroll event at a screen point (Quartz global coords,
    /// top-left origin). Positive `deltaY` scrolls up, negative scrolls down;
    /// positive `deltaX` scrolls right, negative scrolls left.
    /// Note: posting to the HID tap silently does nothing unless the app is
    /// trusted for Accessibility — callers must detect lack of progress and
    /// fall back to manual scrolling.
    public static func injectScroll(deltaY: Int32, deltaX: Int32 = 0, at position: CGPoint) {
        let wheelCount: UInt32 = deltaX == 0 ? 1 : 2
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: wheelCount,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )
        scrollEvent?.location = position
        scrollEvent?.post(tap: .cghidEventTap)
    }

    /// Injects a smooth scroll notch at position (vertical only).
    public static func injectScroll(deltaY: Int32, at position: CGPoint) {
        injectScroll(deltaY: deltaY, deltaX: 0, at: position)
    }
}
