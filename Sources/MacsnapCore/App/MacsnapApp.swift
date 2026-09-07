import Foundation
import CoreGraphics
import Cocoa

@MainActor
public final class MacsnapApp: NSObject, NSApplicationDelegate {
    public static let version = "1.0.0"

    private let singleInstanceLock = SingleInstanceLock()
    private var overlayWindow: CaptureOverlayWindow?
    private var appConfig = AppConfig.load()

    public static func run() {
        let app = NSApplication.shared
        let delegate = MacsnapApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // No dock icon flash, lightning fast
        app.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Register signal handlers for clean SIGTERM dismissal
        signal(SIGTERM) { _ in
            exit(0)
        }
        signal(SIGINT) { _ in
            exit(0)
        }

        let args = ProcessInfo.processInfo.arguments
        Task { @MainActor in
            await self.startApp(args: args)
        }
    }

    private func startApp(args: [String]) async {
        // Parse CLI arguments
        var mode: CaptureKind = .region
        var quickOutput: QuickOutputMode = .none
        var fileToOpen: String? = nil
        var openClipboard: Bool = false
        var isFullscreenImmediate: Bool = false
        var isScrollMode: Bool = false
        var isPinMode: Bool = false

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--version", "-v":
                print("macsnap \(Self.version) (native macOS screenshot and annotation editor)")
                exit(0)
            case "--help", "-h":
                printHelp()
                exit(0)
            case "--capture-region", "region", "smart":
                mode = .region
            case "--capture-window", "windows":
                mode = .window
            case "--capture-fullscreen", "fullscreen":
                mode = .fullscreen
                isFullscreenImmediate = true
            case "--scroll":
                mode = .scroll
                isScrollMode = true
            case "--clipboard":
                openClipboard = true
            case "--file":
                if i + 1 < args.count {
                    i += 1
                    fileToOpen = args[i]
                }
            case "--copy":
                quickOutput = (quickOutput == .save || quickOutput == .both) ? .both : .copy
            case "--save":
                quickOutput = (quickOutput == .copy || quickOutput == .both) ? .both : .save
            case "--pin":
                if i + 1 < args.count {
                    i += 1
                    fileToOpen = args[i]
                    isPinMode = true
                }
            default:
                if !arg.hasPrefix("-") && fileToOpen == nil {
                    fileToOpen = arg
                }
            }
            i += 1
        }

        let isTakeover = (fileToOpen != nil || openClipboard)
        let lockResult = singleInstanceLock.acquire(isTakeover: isTakeover)

        switch lockResult {
        case .dismissedRunningInstance:
            // Hotkey toggle: successfully dismissed running overlay!
            exit(0)
        case .failed(let err):
            fputs("\(err)\n", stderr)
            exit(1)
        case .acquired:
            break
        }

        // Handle Pin mode directly
        if isPinMode, let path = fileToOpen {
            let url = URL(fileURLWithPath: path)
            guard let image = ScreenCaptureEngine.loadImage(from: url) else {
                fputs("Could not load image for pin: \(path)\n", stderr)
                exit(1)
            }
            let logURL = url.appendingPathExtension("json")
            let pinWin = PinnedWindow(imageURL: url, logURL: logURL, image: image)
            pinWin.makeKeyAndOrderFront(nil)
            return
        }

        // Handle opening existing image file
        if let path = fileToOpen {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let image = ScreenCaptureEngine.loadImage(from: url) else {
                fputs("Could not load image: \(path)\n", stderr)
                exit(1)
            }
            openEditorWithImage(image, sourceURL: url)
            return
        }

        // Handle opening clipboard image
        if openClipboard {
            guard let image = ScreenCaptureEngine.loadClipboardImage() else {
                fputs("No readable image on clipboard\n", stderr)
                exit(1)
            }
            openEditorWithImage(image, sourceURL: nil)
            return
        }

        // Check Screen Recording permissions
        if !ScreenCaptureEngine.hasScreenRecordingPermission() {
            fputs("[macsnap] Screen Recording permission is required.\n", stderr)
            fputs("[macsnap] Please grant Screen Recording permission in System Settings > Privacy & Security > Screen & System Audio Recording.\n", stderr)

            _ = ScreenCaptureEngine.requestScreenRecordingPermission()

            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "macsnap requires Screen Recording permission to capture screens and windows.\n\nPlease enable it in System Settings > Privacy & Security > Screen & System Audio Recording."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            exit(1)
        }

        // Capture screen
        guard let capture = await ScreenCaptureEngine.captureCurrentScreen(includeWindows: mode == .window) else {
            fputs("Failed to capture screen (check Screen Recording permissions)\n", stderr)
            exit(1)
        }

        // Immediate fullscreen quick output
        if isFullscreenImmediate && quickOutput != .none {
            if quickOutput == .copy || quickOutput == .both {
                _ = ScreenCaptureEngine.copyImageToClipboard(capture.image)
            }
            if quickOutput == .save || quickOutput == .both {
                let path = appConfig.generateFilename()
                let fileURL = URL(fileURLWithPath: path)
                _ = ScreenCaptureEngine.savePNG(image: capture.image, to: fileURL)
            }
            exit(0)
        }

        // Show overlay window
        let overlay = CaptureOverlayWindow(captureData: capture, appConfig: appConfig)
        overlay.overlayView.captureKind = mode
        overlay.overlayView.quickOutputMode = quickOutput
        if isScrollMode { overlay.overlayView.captureKind = .scroll }

        if isFullscreenImmediate {
            overlay.overlayView.selection = overlay.overlayView.bounds
            overlay.overlayView.phase = .edit
        }

        self.overlayWindow = overlay
        overlay.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openEditorWithImage(_ image: CGImage, sourceURL: URL?) {
        let dummyBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let data = ScreenCaptureData(
            screenBounds: dummyBounds,
            scaleFactor: 1.0,
            pixelSize: CGSize(width: image.width, height: image.height),
            image: image,
            windows: []
        )
        let overlay = CaptureOverlayWindow(captureData: data, appConfig: appConfig)
        overlay.overlayView.selection = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        overlay.overlayView.phase = .edit

        if let sourceURL = sourceURL {
            let logURL = sourceURL.appendingPathExtension("json")
            if let log = try? OperationLog.load(from: logURL) {
                overlay.overlayView.opLog = log
                overlay.overlayView.undo() // restore
                overlay.overlayView.redo()
            }
        }

        self.overlayWindow = overlay
        overlay.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func printHelp() {
        print("""
        Usage: macsnap [options] [image_path]

        Native macOS screenshot and annotation editor.

        Capture Modes:
          macsnap                     Freeform region selection (default)
          macsnap --capture-region    Region capture mode
          macsnap --capture-window    Window capture mode (hover & arrow navigation)
          macsnap --capture-fullscreen Fullscreen capture
          macsnap --scroll            Scrolling region capture
          macsnap region | windows | fullscreen | smart

        Quick Output (skips editor):
          --copy                      Copy PNG to clipboard after capture
          --save                      Save PNG to ~/Pictures/Screenshots
          --copy --save               Copy and save immediately

        Image Editing:
          macsnap <path>              Open existing image in annotation editor
          macsnap --file <path>       Open existing image in annotation editor
          macsnap --clipboard         Open image currently on clipboard
          macsnap --pin <path>        Open image in floating pinned mode

        Single Instance:
          Running macsnap while an overlay is active dismisses the overlay,
          allowing a single hotkey to toggle the capture tool.
        """)
    }
}
