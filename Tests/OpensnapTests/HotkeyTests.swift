import XCTest
import Cocoa
import Carbon
import Carbon.HIToolbox
@testable import OpensnapCore

final class HotkeyTests: XCTestCase {
    func testParseFormatRoundTrip() {
        for text in ["cmd+shift+5", "ctrl+space", "cmd+f12", "opt+left", "cmd+ctrl+opt+shift+x"] {
            guard let binding = HotkeyBinding.parse(text) else {
                XCTFail("could not parse \(text)")
                continue
            }
            XCTAssertEqual(binding.description, text, "round-trip for \(text)")
        }
    }

    func testParseKeyCodes() {
        // US layout spot checks.
        XCTAssertEqual(HotkeyBinding.parse("cmd+r")?.keyCode, 15)
        XCTAssertEqual(HotkeyBinding.parse("cmd+5")?.keyCode, 23)
        XCTAssertEqual(HotkeyBinding.parse("cmd+space")?.keyCode, 49)
        XCTAssertEqual(HotkeyBinding.parse("cmd+f12")?.keyCode, 111)
        XCTAssertEqual(HotkeyBinding.parse("cmd+key200")?.keyCode, 200)
    }

    func testParseModifiers() {
        let binding = HotkeyBinding.parse("cmd+ctrl+opt+shift+a")!
        XCTAssertTrue(binding.modifiers.contains(.command))
        XCTAssertTrue(binding.modifiers.contains(.control))
        XCTAssertTrue(binding.modifiers.contains(.option))
        XCTAssertTrue(binding.modifiers.contains(.shift))
        XCTAssertEqual(binding.displayLabel, "⌃⌥⇧⌘A")
    }

    func testParseRejects() {
        XCTAssertNil(HotkeyBinding.parse(""))
        XCTAssertNil(HotkeyBinding.parse("cmd")) // modifiers only
        XCTAssertNil(HotkeyBinding.parse("5")) // key only
        XCTAssertNil(HotkeyBinding.parse("cmd+nosuchkey"))
        XCTAssertNil(HotkeyBinding.parse("win+r")) // unknown modifier
    }

    func testCarbonModifiers() {
        let binding = HotkeyBinding.parse("cmd+shift+r")!
        XCTAssertEqual(binding.carbonModifiers & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(binding.carbonModifiers & UInt32(shiftKey), UInt32(shiftKey))
        XCTAssertEqual(binding.carbonModifiers & UInt32(optionKey), 0)
    }

    func testConfigRendersHotkeys() {
        var config = AppConfig()
        config.hotkeys["region"] = HotkeyBinding.parse("cmd+shift+5")!
        let ini = config.renderINI()
        XCTAssertTrue(ini.contains("[hotkeys]"))
        XCTAssertTrue(ini.contains("region = cmd+shift+5"))
        XCTAssertTrue(ini.contains("# window = "))
    }

    func testConfigSaveLoadRoundTrip() throws {
        var config = AppConfig()
        config.outputDirectory = "/tmp/opensnap-test-shots"
        config.filenamePattern = "shot-{date}"
        config.hotkeys["window"] = HotkeyBinding.parse("ctrl+opt+w")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try config.save(to: dir.appendingPathComponent("opensnap.conf"))
        let loaded = AppConfig.load(from: dir.appendingPathComponent("opensnap.conf"))
        XCTAssertEqual(loaded.outputDirectory, "/tmp/opensnap-test-shots")
        XCTAssertEqual(loaded.filenamePattern, "shot-{date}")
        XCTAssertEqual(loaded.hotkeys["window"], HotkeyBinding.parse("ctrl+opt+w"))
    }

    func testLiveCarbonRegistration() {
        // Proves the Carbon hotkey path works on this OS: registers an
        // obscure combo and immediately unregisters it.
        let manager = HotkeyManager()
        let binding = HotkeyBinding.parse("ctrl+opt+shift+f19")!
        XCTAssertTrue(manager.register(action: .region, binding: binding))
        XCTAssertTrue(manager.isRegistered(action: .region))
        manager.unregister(action: .region)
        XCTAssertFalse(manager.isRegistered(action: .region))
    }

    func testMenuKeyEquivalentLetters() {
        let eq = MenuBarSupport.menuKeyEquivalent(for: HotkeyBinding.parse("cmd+shift+5")!)!
        XCTAssertEqual(eq.key, "5")
        XCTAssertEqual(eq.mask, [.command, .shift])
    }

    func testMenuKeyEquivalentSpecialKeys() {
        XCTAssertEqual(MenuBarSupport.menuKeyEquivalent(for: HotkeyBinding.parse("cmd+f12")!)?.key, "\u{F70F}")
        XCTAssertEqual(MenuBarSupport.menuKeyEquivalent(for: HotkeyBinding.parse("cmd+space")!)?.key, " ")
        XCTAssertEqual(MenuBarSupport.menuKeyEquivalent(for: HotkeyBinding.parse("cmd+left")!)?.key, "\u{F702}")
        XCTAssertNil(MenuBarSupport.menuKeyEquivalent(for: HotkeyBinding.parse("cmd+key200")!))
    }

    func testRefreshCaptureMenuItem() {
        let item = NSMenuItem(title: "Capture Region", action: nil, keyEquivalent: "")
        // Assigned + representable: native equivalent, base title.
        MenuBarSupport.refreshCaptureMenuItem(
            item, baseTitle: "Capture Region", binding: HotkeyBinding.parse("cmd+shift+5"))
        XCTAssertEqual(item.title, "Capture Region")
        XCTAssertEqual(item.keyEquivalent, "5")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
        // Assigned but exotic: appended label, no equivalent.
        MenuBarSupport.refreshCaptureMenuItem(
            item, baseTitle: "Capture Region", binding: HotkeyBinding.parse("cmd+key200"))
        XCTAssertTrue(item.title.hasPrefix("Capture Region  "))
        XCTAssertTrue(item.title.contains("⌘"))
        XCTAssertEqual(item.keyEquivalent, "")
        // Unassigned: plain base title (idempotent, no label buildup).
        MenuBarSupport.refreshCaptureMenuItem(item, baseTitle: "Capture Region", binding: nil)
        MenuBarSupport.refreshCaptureMenuItem(item, baseTitle: "Capture Region", binding: nil)
        XCTAssertEqual(item.title, "Capture Region")
        XCTAssertEqual(item.keyEquivalent, "")
    }

    // MARK: - Recorder arming suspends live hotkeys

    private static func mouseClick() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    private static func keyPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], characters: String = "") -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    private func firstRecorder(in view: NSView) -> HotkeyRecorderButton? {
        if let button = view as? HotkeyRecorderButton { return button }
        for sub in view.subviews {
            if let found = firstRecorder(in: sub) { return found }
        }
        return nil
    }

    @MainActor
    func testRecorderEscCancels() {
        let button = HotkeyRecorderButton()
        var changes: [Bool] = []
        button.onRecordingChange = { changes.append($0) }
        button.binding = HotkeyBinding.parse("cmd+r")
        button.mouseDown(with: Self.mouseClick())
        XCTAssertTrue(button.isRecording)
        button.keyDown(with: Self.keyPress(keyCode: 53)) // Esc
        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(button.binding, HotkeyBinding.parse("cmd+r"), "Esc keeps the previous binding")
        XCTAssertEqual(changes, [true, false])
    }

    @MainActor
    func testRecorderCapturesCombo() {
        let button = HotkeyRecorderButton()
        button.mouseDown(with: Self.mouseClick())
        button.keyDown(with: Self.keyPress(keyCode: 15, modifiers: [.command], characters: "r"))
        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(button.binding?.description, "cmd+r")
    }

    @MainActor
    func testRecorderRequiresModifier() {
        let button = HotkeyRecorderButton()
        button.mouseDown(with: Self.mouseClick())
        button.keyDown(with: Self.keyPress(keyCode: 15, characters: "r"))
        XCTAssertTrue(button.isRecording, "bare keys must not commit")
        XCTAssertNil(button.binding)
    }

    @MainActor
    func testRecorderDeleteClears() {
        let button = HotkeyRecorderButton()
        button.binding = HotkeyBinding.parse("cmd+r")
        button.mouseDown(with: Self.mouseClick())
        button.keyDown(with: Self.keyPress(keyCode: 51)) // Delete
        XCTAssertFalse(button.isRecording)
        XCTAssertNil(button.binding)
    }

    @MainActor
    func testControllerSuspendsHotkeysWhileRecording() {
        let controller = SettingsWindowController()
        var states: [Bool] = []
        controller.onRecordingChanged = { states.append($0) }
        guard let content = controller.window?.contentView,
              let recorder = firstRecorder(in: content) else {
            XCTFail("no recorder button found")
            return
        }
        recorder.mouseDown(with: Self.mouseClick())
        recorder.keyDown(with: Self.keyPress(keyCode: 53)) // Esc
        XCTAssertEqual(states, [true, false])
    }
}
