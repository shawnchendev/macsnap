import Cocoa
import Carbon
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon RegisterEventHotKey (no Accessibility
/// permission needed, unlike event taps). One hotkey per capture action;
/// firing calls `onFire` on the main thread.
///
/// All registration and events happen on the main thread (Carbon dispatches
/// hot-key events through the main event loop).
public final class HotkeyManager: @unchecked Sendable {
    public enum Action: String, CaseIterable {
        case region
        case window
        case scroll
        case fullscreen

        public var captureArguments: [String] {
            switch self {
            case .region: return ["--capture-region"]
            case .window: return ["--capture-window"]
            case .scroll: return ["--scroll"]
            case .fullscreen: return ["--capture-fullscreen"]
            }
        }
    }

    public var onFire: ((Action) -> Void)?

    private var refs: [Action: EventHotKeyRef?] = [:]
    private var handlerInstalled = false
    static let hotkeySignature = OSType(0x4D63536E) // 'McSn'

    public init() {}

    /// Registers (or replaces) the hotkey for an action. Returns false when
    /// the combination is rejected (e.g. already taken).
    @discardableResult
    public func register(action: Action, binding: HotkeyBinding) -> Bool {
        unregister(action: action)
        installHandlerIfNeeded()
        let index = Int32(Action.allCases.firstIndex(of: action) ?? 0)
        let hid = EventHotKeyID(signature: Self.hotkeySignature, id: UInt32(bitPattern: index))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            hid,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { return false }
        refs[action] = ref
        return true
    }

    public func unregister(action: Action) {
        if let ref = refs[action] ?? nil {
            UnregisterEventHotKey(ref)
        }
        refs[action] = nil
    }

    public func unregisterAll() {
        for action in Action.allCases { unregister(action: action) }
    }

    public func isRegistered(action: Action) -> Bool {
        (refs[action] ?? nil) != nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        // Note: InstallApplicationEventHandler is a C macro (unimportable in
        // Swift); this is its exact expansion.
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1, &spec, selfPtr, nil
        )
    }

    fileprivate func fire(actionID: UInt32) {
        let index = Int(actionID)
        guard index >= 0, index < Action.allCases.count else { return }
        let action = Action.allCases[index]
        if Thread.isMainThread {
            onFire?(action)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onFire?(action) }
        }
    }
}

private func hotkeyEventHandler(
    next: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hid = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hid
    )
    guard status == noErr else { return status }
    if hid.signature == HotkeyManager.hotkeySignature,
       let manager = userData.map({ Unmanaged<HotkeyManager>.fromOpaque($0).takeUnretainedValue() }) {
        manager.fire(actionID: hid.id)
    }
    return noErr
}
