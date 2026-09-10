import Cocoa
import OpensnapCore

/// Resident menu-bar frontend for opensnap. Never captures itself — each menu
/// action launches the installed `opensnap` binary, which keeps the existing
/// single-shot capture flow (and its Screen Recording permission) untouched.
@MainActor
final class MenuBarDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var loginItem: NSMenuItem?
    private var captureMenuItems: [(action: HotkeyManager.Action, item: NSMenuItem, title: String)] = []
    private var lastCaptureLaunch = Date.distantPast
    private let hotkeys = HotkeyManager()
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if MenuBarSupport.claimMenubarLock() {
            // Another menu bar is already running.
            NSApp.terminate(nil)
            return
        }

        guard let button = makeStatusItem() else {
            NSApp.terminate(nil)
            return
        }
        button.toolTip = "opensnap \(OpensnapApp.version) — screenshot capture"
        showWelcomeIfNeeded()
        startHotkeys()
    }

    /// Registers saved global hotkeys; failures are logged (the Settings
    /// panel surfaces them interactively on save).
    private func startHotkeys() {
        hotkeys.onFire = { [weak self] action in
            self?.runCapture(arguments: action.captureArguments)
        }
        registerSavedHotkeys()
    }

    private func registerSavedHotkeys() {
        let saved = AppConfig.load().hotkeys
        for action in HotkeyManager.Action.allCases {
            if let binding = saved[action.rawValue] {
                if !hotkeys.register(action: action, binding: binding) {
                    NSLog("opensnap-menubar: could not grab saved hotkey %@ for %@", binding.description, action.rawValue)
                }
            }
        }
    }

    /// Applies freshly saved bindings: re-registers everything, returning
    /// display labels the system rejected.
    private func applyHotkeys(_ config: AppConfig) -> [String] {
        hotkeys.unregisterAll()
        var failed: [String] = []
        for action in HotkeyManager.Action.allCases {
            if let binding = config.hotkeys[action.rawValue] {
                if hotkeys.register(action: action, binding: binding) {
                    NSLog("opensnap-menubar: hotkey %@ -> %@", action.rawValue, binding.description)
                } else {
                    failed.append("\(action.rawValue) (\(binding.displayLabel))")
                }
            }
        }
        return failed
    }

    /// First launch ever: say hello visibly. An agent app (no Dock icon) that
    /// only adds a small menu-bar glyph otherwise looks like "nothing
    /// happened" — especially if the glyph lands in a crowded/overflow area.
    private func showWelcomeIfNeeded() {
        let stateDir = MenuBarSupport.appStateDir(home: FileManager.default.homeDirectoryForCurrentUser)
        guard MenuBarSupport.needsWelcome(stateDir: stateDir) else { return }
        MenuBarSupport.markWelcomed(stateDir: stateDir)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "opensnap is running in your menu bar"
        alert.informativeText = "Click the viewfinder icon at the top of your screen to capture (Region, Window, Scrolling Region, Fullscreen).\n\nDon’t see it? Open System Settings → Control Center and make sure menu-bar icons are shown."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func makeStatusItem() -> NSStatusBarButton? {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return nil }
        if let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "opensnap") {
            icon.isTemplate = true
            button.image = icon
        } else {
            button.title = "◉"
        }
        let menu = NSMenu()
        menu.delegate = self
        captureMenuItems = [
            (.region, makeCaptureItem(menu: menu, title: "Capture Region", action: #selector(captureRegion(_:))), "Capture Region"),
            (.window, makeCaptureItem(menu: menu, title: "Capture Window", action: #selector(captureWindow(_:))), "Capture Window"),
            (.scroll, makeCaptureItem(menu: menu, title: "Capture Scrolling Region", action: #selector(captureScroll(_:))), "Capture Scrolling Region"),
            (.fullscreen, makeCaptureItem(menu: menu, title: "Capture Fullscreen", action: #selector(captureFullscreen(_:))), "Capture Fullscreen"),
        ]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openScreenshots(_:)), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit opensnap menu bar", action: #selector(quit(_:)), keyEquivalent: "q")
            .target = self
        // Explicit click handling (instead of button.menu): deterministic
        // across macOS versions, and every step is logged for diagnosis.
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusMenu = menu
        statusItem = item
        NSLog("opensnap-menubar: status item installed with %d menu items", menu.items.count)
        refreshLoginItem()
        return button
    }

    private func makeCaptureItem(menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    /// Each item mirrors its global hotkey (real equivalent where
    /// representable, appended label otherwise).
    private func refreshCaptureMenuItems(bindings: [String: HotkeyBinding]) {
        for entry in captureMenuItems {
            MenuBarSupport.refreshCaptureMenuItem(
                entry.item, baseTitle: entry.title, binding: bindings[entry.action.rawValue]
            )
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let menu = statusMenu else { return }
        NSLog("opensnap-menubar: status item clicked, popping menu")
        statusItem?.button?.highlight(true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        statusItem?.button?.highlight(false)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        NSLog("opensnap-menubar: menu will open")
        refreshLoginItem()
        refreshCaptureMenuItems(bindings: AppConfig.load().hotkeys)
    }

    private func refreshLoginItem() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        loginItem?.state = MenuBarSupport.isLoginItemEnabled(home: home) ? .on : .off
    }

    // MARK: - Actions

    private func runCapture(arguments: [String]) {
        // A global hotkey and an open menu can fire the same action twice for
        // one keypress (menu equivalent + Carbon); ignore near-duplicates so
        // the second launch doesn't toggle-dismiss the first overlay.
        statusMenu?.cancelTracking()
        let now = Date()
        if now.timeIntervalSince(lastCaptureLaunch) < 1.0 {
            NSLog("opensnap-menubar: ignoring duplicate capture launch")
            return
        }
        lastCaptureLaunch = now
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let ownExec = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        guard let bin = MenuBarSupport.opensnapBinaryURL(ownExecutableURL: ownExec, pathEnv: pathEnv) else {
            let alert = NSAlert()
            alert.messageText = "opensnap binary not found"
            alert.informativeText = "Install it with `make install` so it sits next to the menu-bar app."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        NSLog("opensnap-menubar: launching %@ %@", bin.path, arguments.joined(separator: " "))
        MenuBarSupport.diagLog("launch \(bin.path) \(arguments.joined(separator: " "))")
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = arguments
        proc.environment = ProcessInfo.processInfo.environment
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.terminationHandler = { [weak self] process in
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            NSLog("opensnap-menubar: capture exited status=%d stderr=%@", process.terminationStatus, stderr)
            MenuBarSupport.diagLog("exit status=\(process.terminationStatus) stderr=\(stderr)")
            guard process.terminationStatus != 0 else { return }
            // First-run permission path: the system prompt already takes the
            // user to Settings — don't stack our own dialog on top of it.
            if MenuBarSupport.shouldSuppressCaptureFailureDialog(stderr: stderr, terminationStatus: process.terminationStatus) {
                return
            }
            Task { @MainActor in
                self?.showCaptureFailure(stderr: stderr)
            }
        }
        do {
            try proc.run()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not launch opensnap"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @MainActor
    private func showCaptureFailure(stderr: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Screenshot failed"
        let detail = stderr.isEmpty
            ? "opensnap exited without capturing. If this was launched from the app bundle, grant Screen Recording to “opensnap” in System Settings first."
            : stderr
        alert.informativeText = detail + "\n\nDetails: ~/.local/state/opensnap/menubar.log"
        alert.alertStyle = .warning
        if MenuBarSupport.shouldOfferSettingsButton(stderr: stderr) || stderr.isEmpty {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Dismiss")
        }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func captureRegion(_ sender: Any?) { runCapture(arguments: ["--capture-region"]) }
    @objc private func captureWindow(_ sender: Any?) { runCapture(arguments: ["--capture-window"]) }
    @objc private func captureScroll(_ sender: Any?) { runCapture(arguments: ["--scroll"]) }
    @objc private func captureFullscreen(_ sender: Any?) { runCapture(arguments: ["--capture-fullscreen"]) }

    @objc private func openScreenshots(_ sender: Any?) {
        NSWorkspace.shared.open(AppConfig.load().resolvedOutputDirectory())
    }

    @objc private func toggleLoginItem(_ sender: Any?) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let enabled = !MenuBarSupport.isLoginItemEnabled(home: home)
        let program = Bundle.main.executableURL?.path
            ?? CommandLine.arguments.first
            ?? ""
        do {
            try MenuBarSupport.setLoginItemEnabled(enabled, menubarProgram: program, home: home)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Open at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
        refreshLoginItem()
    }

    @objc private func openSettings(_ sender: Any?) {
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.onSave = { [weak self] config in
                guard let self else { return [] }
                return self.applyHotkeys(config)
            }
            controller.onRecordingChanged = { [weak self] recording in
                // While recording, live hotkeys must not fire (the combo
                // being pressed is the one under test). Restores after.
                if recording {
                    self?.hotkeys.unregisterAll()
                } else {
                    self?.registerSavedHotkeys()
                }
            }
            settingsController = controller
        }
        settingsController?.show()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MenuBarDelegate()
app.delegate = delegate
app.run()
