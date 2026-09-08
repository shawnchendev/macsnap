import Cocoa
import Carbon
import Carbon.HIToolbox

/// A global-hotkey binding: hardware key code plus device-independent
/// modifiers. Serializes to human-friendly INI form such as `cmd+shift+5`
/// (US-layout key names) with a `key<code>` numeric fallback for anything
/// outside the table.
public struct HotkeyBinding: Equatable, Sendable {
    public var keyCode: UInt32
    /// NSEvent.ModifierFlags device-independent subset (command/shift/option/control).
    public var modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .shift, .option, .control])
    }

    // MARK: - Key names (US layout + named keys)

    private static let codeToName: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 24: "=", 27: "-", 50: "`",
        33: "[", 30: "]",
        48: "tab", 49: "space", 36: "return", 51: "delete", 53: "esc", 117: "del",
        123: "left", 124: "right", 125: "down", 126: "up",
        115: "home", 119: "end", 116: "pageup", 121: "pagedown",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7",
        100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12", 105: "f13",
        107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20",
    ]

    private static var nameToCode: [String: UInt32] {
        var table: [String: UInt32] = [:]
        for (code, name) in codeToName { table[name] = code }
        return table
    }

    public static func keyName(for keyCode: UInt32) -> String {
        codeToName[keyCode] ?? "key\(keyCode)"
    }

    // MARK: - Formatting

    private static func modifierTokens(_ modifiers: NSEvent.ModifierFlags) -> [String] {
        var tokens: [String] = []
        if modifiers.contains(.command) { tokens.append("cmd") }
        if modifiers.contains(.control) { tokens.append("ctrl") }
        if modifiers.contains(.option) { tokens.append("opt") }
        if modifiers.contains(.shift) { tokens.append("shift") }
        return tokens
    }

    /// Canonical INI form, e.g. `cmd+shift+5`.
    public var description: String {
        (Self.modifierTokens(modifiers) + [Self.keyName(for: keyCode)]).joined(separator: "+")
    }

    /// Menu/UI form with symbols, e.g. `⇧⌘5`.
    public var displayLabel: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        let name = Self.keyName(for: keyCode)
        s += name.count == 1 ? name.uppercased() : name
        return s
    }

    // MARK: - Parsing

    /// Parses `cmd+shift+5`, `ctrl+space`, `cmd+key123`, etc. Returns nil for
    /// empty input or an unrecognized key token.
    public static func parse(_ string: String) -> HotkeyBinding? {
        let tokens = string.lowercased().split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        guard tokens.count >= 2 else { return nil } // modifiers + key required
        var mods = NSEvent.ModifierFlags()
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command", "meta": mods.insert(.command)
            case "ctrl", "control", "ctl": mods.insert(.control)
            case "opt", "option", "alt": mods.insert(.option)
            case "shift", "shft": mods.insert(.shift)
            default: return nil
            }
        }
        let keyToken = tokens.last!
        let code: UInt32?
        if keyToken.hasPrefix("key"), let n = UInt32(keyToken.dropFirst(3)) {
            code = n
        } else {
            code = nameToCode[keyToken]
        }
        guard let keyCode = code else { return nil }
        return HotkeyBinding(keyCode: keyCode, modifiers: mods)
    }

    // MARK: - Carbon interop

    /// Carbon modifier flags for RegisterEventHotKey.
    public var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    public static func from(event: NSEvent) -> HotkeyBinding? {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !mods.isEmpty else { return nil }
        return HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: mods)
    }
}
