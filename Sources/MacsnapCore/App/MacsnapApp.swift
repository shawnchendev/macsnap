import Foundation
import CoreGraphics
import Cocoa

@MainActor
public final class MacsnapApp: NSObject, NSApplicationDelegate {
    public static let version = "0.0.1"

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

        // Check Screen Recording permissions. The system prompt (triggered by
        // the request call below) is the only dialog — no custom alert.
        if !ScreenCaptureEngine.hasScreenRecordingPermission() {
            fputs("[macsnap] Screen Recording permission is required.\n", stderr)
            fputs("[macsnap] Please grant Screen Recording permission in System Settings > Privacy & Security > Screen & System Audio Recording.\n", stderr)

            _ = ScreenCaptureEngine.requestScreenRecordingPermission()
            exit(1)
        }

        // Capture screen. Windows are always discovered (except instant
        // fullscreen quick output) so switching to the Window tab later works.
        // Mirrors omasnap, which skips window discovery only for instant output.
        let instantFullscreenOutput = isFullscreenImmediate && quickOutput != .none
        guard let capture = await ScreenCaptureEngine.captureCurrentScreen(includeWindows: !instantFullscreenOutput) else {
            // NB: preflight can pass while capture still fails when the TCC
            // entry pins an older build's code signature (see README
            // "Permissions & rebuilding"): the toggle looks ON but the current
            // binary no longer matches it.
            fputs("Failed to capture screen.\n", stderr)
            fputs("If Screen Recording already looks enabled for macsnap, remove it with minus and re-add it (each rebuild changes an ad-hoc signature).\n", stderr)
            fputs("Durable fix: sign with an Apple Development certificate — see README.\n", stderr)
            exit(1)
        }

        // Immediate fullscreen quick output
        if instantFullscreenOutput {
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
        overlay.showOverlay()
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
        overlay.showOverlay()
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
