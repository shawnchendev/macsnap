import Foundation
import CoreGraphics
import Cocoa
import UniformTypeIdentifiers
import ScreenCaptureKit

public struct ScreenCaptureData: @unchecked Sendable {
    public var screenBounds: CGRect
    public var scaleFactor: CGFloat
    public var pixelSize: CGSize
    public var image: CGImage
    public var windows: [WindowTarget]

    public init(screenBounds: CGRect, scaleFactor: CGFloat, pixelSize: CGSize, image: CGImage, windows: [WindowTarget]) {
        self.screenBounds = screenBounds
        self.scaleFactor = scaleFactor
        self.pixelSize = pixelSize
        self.image = image
        self.windows = windows
    }
}

public enum ScreenCaptureEngine {
    /// Checks if Screen Recording permission is currently granted
    public static func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    /// Prompts system dialog for Screen Recording permission if not yet granted
    public static func requestScreenRecordingPermission() -> Bool {
        if #available(macOS 10.15, *) {
            if CGPreflightScreenCaptureAccess() {
                return true
            }
            return CGRequestScreenCaptureAccess()
        }
        return true
    }

    /// Captures the screen currently containing the mouse pointer using ScreenCaptureKit.
    public static func captureCurrentScreen(includeWindows: Bool = true) async -> ScreenCaptureData? {
        let mousePoint = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        var targetScreen = screens[0]
        for screen in screens {
            if screen.frame.contains(mousePoint) {
                targetScreen = screen
                break
            }
        }

        let primaryHeight = screens[0].frame.height
        let cgScreenRect = CGRect(
            x: targetScreen.frame.origin.x,
            y: primaryHeight - (targetScreen.frame.origin.y + targetScreen.frame.height),
            width: targetScreen.frame.width,
            height: targetScreen.frame.height
        )

        guard let image = try? await captureWithSCK(screen: targetScreen) else {
            return nil
        }

        let scale = targetScreen.backingScaleFactor
        let pixelSize = CGSize(width: image.width, height: image.height)

        var windows: [WindowTarget] = []
        if includeWindows {
            windows = WindowDiscovery.enumerateWindows(screenBounds: cgScreenRect)
        }

        return ScreenCaptureData(
            screenBounds: targetScreen.frame,
            scaleFactor: scale,
            pixelSize: pixelSize,
            image: image,
            windows: windows
        )
    }

    private static func captureWithSCK(screen: NSScreen) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screenDisplayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0

        guard let display = content.displays.first(where: { $0.displayID == screenDisplayID }) ?? content.displays.first else {
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
        config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
        config.showsCursor = false
        config.scalesToFit = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Loads image data currently on the general clipboard
    public static func loadClipboardImage() -> CGImage? {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage
        }
        return nil
    }

    /// Copies image to system clipboard as PNG
    public static func copyImageToClipboard(_ image: CGImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let data = encodePNG(image: image) else { return false }
        return pasteboard.setData(data, forType: .png)
    }

    /// Copies plain text to system clipboard
    public static func copyTextToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Encodes a CGImage to PNG Data
    public static func encodePNG(image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Saves a CGImage as a PNG file
    public static func savePNG(image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return false }

        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Loads an image from file URL
    public static func loadImage(from url: URL) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }
}
