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
    public static func enumerateWindows(screenBounds: CGRect) -> [WindowTarget] {
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
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            // Filter out tiny or invisible windows
            if rect.width < 60 || rect.height < 60 {
                continue
            }
            // Check intersection with active screen
            if !rect.intersects(screenBounds) {
                continue
            }

            let id = (dict[kCGWindowNumber as String] as? CGWindowID) ?? 0
            let ownerName = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (dict[kCGWindowName as String] as? String) ?? ""

            // Skip Dock, Window Server, macsnap itself
            if ownerName == "Dock" || ownerName == "Window Server" || ownerName == "macsnap" || ownerName == "omasnap" {
                continue
            }

            targets.append(WindowTarget(windowId: id, rect: rect, title: title, appName: ownerName))
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
