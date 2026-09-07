import Foundation
import CoreGraphics

public enum ScrollInjector {
    /// Injects a smooth scroll notch at position
    public static func injectScroll(deltaY: Int32, at position: CGPoint) {
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        )
        scrollEvent?.location = position
        scrollEvent?.post(tap: .cghidEventTap)
    }
}
