import XCTest
import Cocoa
import Carbon
import Carbon.HIToolbox
@testable import MacsnapCore

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
        config.outputDirectory = "/tmp/macsnap-test-shots"
        config.filenamePattern = "shot-{date}"
        config.hotkeys["window"] = HotkeyBinding.parse("ctrl+opt+w")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try config.save(to: dir.appendingPathComponent("macsnap.conf"))
        let loaded = AppConfig.load(from: dir.appendingPathComponent("macsnap.conf"))
        XCTAssertEqual(loaded.outputDirectory, "/tmp/macsnap-test-shots")
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
}
