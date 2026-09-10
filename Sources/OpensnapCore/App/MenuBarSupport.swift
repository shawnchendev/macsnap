import Foundation
import Cocoa
import ServiceManagement

/// Pure helpers behind the resident menu-bar app (see the `OpensnapMenuBar`
/// target). The menu bar itself never captures — it just launches the
/// installed `opensnap` binary, so Screen Recording permission stays with the
/// binary the user already approved.
public enum MenuBarSupport {
    public static let launchAgentLabel = "com.opensnap.menubar"

    /// Locates the `opensnap` capture binary: next to our own executable first
    /// (both are installed into the same `bin` dir by `make install`), then
    /// each entry of `PATH`.
    public static func opensnapBinaryURL(ownExecutableURL: URL?, pathEnv: String) -> URL? {
        let fm = FileManager.default
        if let own = ownExecutableURL {
            let sibling = own.deletingLastPathComponent().appendingPathComponent("opensnap")
            if fm.isExecutableFile(atPath: sibling.path) {
                return sibling
            }
        }
        for dir in pathEnv.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("opensnap")
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public static func launchAgentURL(home: URL) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    public static func launchAgentPlist(program: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
    }

    public static func isLoginItemEnabled(home: URL) -> Bool {
        if isAppBundle {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: launchAgentURL(home: home).path)
    }

    /// True when running inside a .app bundle (double-clickable app) rather
    /// than as a bare CLI binary. Bundled apps manage login items through
    /// SMAppService; bare binaries use a LaunchAgent plist instead.
    public static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Writes/removes the LaunchAgent plist (bare-binary distribution), or
    /// registers/unregisters with SMAppService (bundled .app). The plist
    /// takes effect at next login; SMAppService applies immediately but
    /// requires the app to live in /Applications.
    public static func setLoginItemEnabled(_ enabled: Bool, menubarProgram: String, home: URL) throws {
        if isAppBundle {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return
        }
        let url = launchAgentURL(home: home)
        if enabled {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try launchAgentPlist(program: menubarProgram).write(to: url, atomically: true, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func menubarLockURL() -> URL {
        URL(fileURLWithPath: "/tmp/opensnap-\(getuid())/menubar.lock")
    }

    public static func diagLogURL(home: URL) -> URL {
        home.appendingPathComponent(".local/state/opensnap/menubar.log")
    }

    /// Best-effort diagnostic log. NSLog alone is unreliable here: processes
    /// launched from Finder/the menu have no stderr and their NSLog lines do
    /// not reach the unified log, so failures would otherwise be invisible.
    public static func diagLog(_ line: String, home: URL? = nil) {
        let base = home ?? FileManager.default.homeDirectoryForCurrentUser
        let url = diagLogURL(home: base)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Rotate past ~200KB to bound growth.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > 200 * 1024 {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(stamp)] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public static func appStateDir(home: URL) -> URL {
        home.appendingPathComponent(".local/state/opensnap")
    }

    /// One-time welcome sentinel (persistent across reboots, unlike /tmp).
    public static func needsWelcome(stateDir: URL) -> Bool {
        !FileManager.default.fileExists(atPath: stateDir.appendingPathComponent(".menubar-welcomed").path)
    }

    public static func markWelcomed(stateDir: URL) {
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: stateDir.appendingPathComponent(".menubar-welcomed").path,
            contents: Data()
        )
    }

    /// Whether a capture failure message warrants an "Open System Settings"
    /// button (i.e. it smells like a Screen Recording permission problem).
    public static func shouldOfferSettingsButton(stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("screen recording") || lower.contains("permission")
    }

    /// Dedicated exit code the capture binary uses when it has just shown
    /// the system Screen Recording prompt (first-run path).
    public static let permissionPromptExitCode: Int32 = 3

    /// Machine-readable marker emitted on stderr alongside the
    /// permission-prompt exit, so log readers can identify the path even if
    /// the exit code is lost.
    public static let permissionPromptMarker = "System permission prompt shown"

    /// True when the capture binary already showed the system Screen
    /// Recording prompt. The system dialog takes the user to Settings, so
    /// the menu bar must not stack its own "Screenshot failed" alert on top.
    /// Other failures (e.g. stale TCC signature with capture failing despite
    /// preflight passing) still deserve our dialog.
    public static func shouldSuppressCaptureFailureDialog(stderr: String, terminationStatus: Int32) -> Bool {
        if terminationStatus == permissionPromptExitCode { return true }
        return stderr.contains(permissionPromptMarker)
    }

    // MARK: - Menu shortcut display

    /// Native key equivalent for a binding, or nil when not representable
    /// (e.g. the `key<code>` numeric fallback). Note these only fire while
    /// the menu is open — the global hotkeys are the Carbon registrations.
    public static func menuKeyEquivalent(for binding: HotkeyBinding) -> (key: String, mask: NSEvent.ModifierFlags)? {
        let name = HotkeyBinding.keyName(for: binding.keyCode)
        if name.count == 1 {
            return (name.lowercased(), binding.modifiers)
        }
        let special: String?
        switch name {
        case "space": special = " "
        case "tab": special = "\t"
        case "return": special = "\r"
        case "delete": special = "\u{8}"
        case "del": special = "\u{7F}"
        case "esc": special = "\u{1B}"
        case "up": special = "\u{F700}"
        case "down": special = "\u{F701}"
        case "left": special = "\u{F702}"
        case "right": special = "\u{F703}"
        case "home": special = "\u{F729}"
        case "end": special = "\u{F72B}"
        case "pageup": special = "\u{F72C}"
        case "pagedown": special = "\u{F72D}"
        default:
            if name.hasPrefix("f"), let n = Int(name.dropFirst()), (1...20).contains(n) {
                let scalarValue = n <= 12 ? 0xF704 + (n - 1) : 0xF710 + (n - 13)
                special = String(UnicodeScalar(scalarValue)!)
            } else {
                special = nil
            }
        }
        guard let key = special else { return nil }
        return (key, binding.modifiers)
    }

    /// Points a capture menu item at its hotkey: native right-aligned
    /// equivalent when representable, appended label otherwise, plain base
    /// title when unassigned. Idempotent (safe to call on every menu open).
    public static func refreshCaptureMenuItem(_ item: NSMenuItem, baseTitle: String, binding: HotkeyBinding?) {
        if let binding = binding, let (key, mask) = menuKeyEquivalent(for: binding) {
            item.title = baseTitle
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = mask
        } else if let binding = binding {
            item.title = "\(baseTitle)  \(binding.displayLabel)"
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        } else {
            item.title = baseTitle
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }
    /// Claims the menu-bar singleton lock. Returns true when another live
    /// menu-bar process already holds it (caller should exit). Stale locks
    /// from crashed processes are reclaimed via pid liveness.
    @discardableResult
    public static func claimMenubarLock() -> Bool {
        let url = menubarLockURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let pidStr = try? String(contentsOf: url, encoding: .utf8),
           let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid != getpid(), kill(pid, 0) == 0 {
            return true
        }
        try? "\(getpid())\n".write(to: url, atomically: true, encoding: .utf8)
        return false
    }
}
