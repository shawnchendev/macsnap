import Foundation
import CoreGraphics
import Cocoa

public struct WindowTarget: Equatable, Sendable {
    public var windowId: CGWindowID
    public var rect: CGRect
    public var title: String
    public var appName: String
    public var appSlug: String

    public init(windowId: CGWindowID, rect: CGRect, title: String, appName: String) {
        self.windowId = windowId
        self.rect = rect
        self.title = title
        self.appName = appName
        self.appSlug = AppConfig.slugifyApp(appName)
    }
}

public enum WindowDiscovery {
    /// Discovers visible standard application windows on screen.
    /// - Parameters:
    ///   - screenBounds: The screen's rect in Quartz global coordinates
    ///     (origin = top-left of primary display, y increases downward),
    ///     as computed by `ScreenCaptureEngine.captureCurrentScreen`.
    ///   - primaryScreenHeight: Height of the primary screen in points.
    ///     Kept for API compatibility; not needed for the conversion because both
    ///     `CGWindowListCopyWindowInfo` bounds and the flipped overlay view use a
    ///     top-left origin (verified: menu bar windows report Y=0).
    public static func enumerateWindows(screenBounds: CGRect, primaryScreenHeight: CGFloat) -> [WindowTarget] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var targets: [WindowTarget] = []
        for dict in list {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            guard let alpha = dict[kCGWindowAlpha as String] as? Double, alpha > 0.1 else {
                continue
            }
            guard let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            // Filter out tiny or invisible windows
            if cgRect.width < 60 || cgRect.height < 60 {
                continue
            }
            // Check intersection with active screen (cgRect is in CG screen space)
            if !cgRect.intersects(screenBounds) {
                continue
            }

            let id = (dict[kCGWindowNumber as String] as? CGWindowID) ?? 0
            let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (dict[kCGWindowName as String] as? String) ?? ""

            // Skip Dock, Window Server, macsnap itself
            if ownerName == "Dock" || ownerName == "Window Server" || ownerName == "macsnap" || ownerName == "omasnap" {
                continue
            }

            // Convert Quartz global rect (origin = top-left of primary screen) →
            // flipped view rect (origin = top-left of this screen).
            // screenBounds.origin is the Quartz origin of this screen (may be non-zero on multi-monitor).
            _ = primaryScreenHeight
            let viewRect = CGRect(
                x: cgRect.minX - screenBounds.origin.x,
                y: cgRect.minY - screenBounds.origin.y,
                width: cgRect.width,
                height: cgRect.height
            )

            targets.append(WindowTarget(windowId: id, rect: viewRect, title: title, appName: ownerName))
        }

        return targets
    }

    /// Finds the foremost window target containing the given point.
    public static func windowAt(point: CGPoint, in windows: [WindowTarget]) -> WindowTarget? {
        for target in windows {
            if target.rect.contains(point) {
                return target
            }
        }
        return nil
    }

    /// Index of the foremost window containing the point, or nil.
    public static func windowIndexAt(point: CGPoint, in windows: [WindowTarget]) -> Int? {
        for (i, target) in windows.enumerated() {
            if target.rect.contains(point) {
                return i
            }
        }
        return nil
    }

    /// Nearest window in an arrow-key direction from the current one,
    /// mirroring omasnap's `windowInDirection` (Super+Arrows there,
    /// Cmd+Arrows here). `keyCode` is a macOS arrow keyCode
    /// (123 left, 124 right, 125 down, 126 up); view coords are y-down,
    /// so down means +y. Returns the current index when nothing qualifies.
    public static func windowInDirection(from current: Int?, keyCode: UInt16, in windows: [WindowTarget]) -> Int? {
        guard !windows.isEmpty else { return nil }
        let origin: CGPoint
        if let c = current, c >= 0, c < windows.count {
            let r = windows[c].rect
            origin = CGPoint(x: r.midX, y: r.midY)
        } else {
            return nil
        }
        var best: Int? = nil
        var bestScore = CGFloat.greatestFiniteMagnitude
        for (i, target) in windows.enumerated() {
            if i == current { continue }
            let dx = target.rect.midX - origin.x
            let dy = target.rect.midY - origin.y
            var along: CGFloat = 0
            var across: CGFloat = 0
            switch keyCode {
            case 123 where dx < 0: along = -dx; across = abs(dy) // Left
            case 124 where dx > 0: along = dx; across = abs(dy)  // Right
            case 126 where dy < 0: along = -dy; across = abs(dx) // Up
            case 125 where dy > 0: along = dy; across = abs(dx)  // Down
            default: continue
            }
            let score = along + across * 2.0
            if score < bestScore {
                bestScore = score
                best = i
            }
        }
        return best ?? current
    }

    /// Finds the dominant app slug for a given selection rectangle.
    public static func dominantAppClass(in windows: [WindowTarget], selection: CGRect) -> String {
        var bestSlug = ""
        var maxArea: CGFloat = 0.0

        for target in windows {
            let intersection = target.rect.intersection(selection)
            if !intersection.isNull {
                let area = intersection.width * intersection.height
                if area > maxArea {
                    maxArea = area
                    bestSlug = target.appSlug
                }
            }
        }
        return bestSlug
    }
}
