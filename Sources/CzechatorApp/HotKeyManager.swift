import AppKit
import Carbon.HIToolbox
import CzechatorCore

/// Registers a system-wide hotkey through Carbon's `RegisterEventHotKey`.
///
/// Needs no Accessibility permission, which is why this stays the default
/// trigger: the app works on first launch without any TCC dialog. Its cost is
/// that the combination is held unconditionally — see `DoubleTapMonitor` for
/// the alternative that steals nothing.
@MainActor
final class HotKeyManager: Trigger {

    enum HotKeyError: Error, Equatable {
        case unsupportedKey(String)
        case registrationFailed(OSStatus)
    }

    private let spec: ShortcutSpec
    private var reference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    init(spec: ShortcutSpec) { self.spec = spec }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    func start(_ action: @escaping @MainActor () -> Void) throws {
        stop()
        guard let code = Self.keyCodes[spec.key] else {
            throw HotKeyError.unsupportedKey(spec.key)
        }
        self.action = action

        var carbonModifiers: UInt32 = 0
        if spec.modifiers.contains(.cmd) { carbonModifiers |= UInt32(cmdKey) }
        if spec.modifiers.contains(.ctrl) { carbonModifiers |= UInt32(controlKey) }
        if spec.modifiers.contains(.alt) { carbonModifiers |= UInt32(optionKey) }
        if spec.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hotkey events on the main run loop.
            MainActor.assumeIsolated { manager.action?() }
            return noErr
        }

        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference)
        guard installed == noErr else {
            stop()
            throw HotKeyError.registrationFailed(installed)
        }

        // "CZCH"
        let identifier = EventHotKeyID(signature: OSType(0x435A_4348), id: 1)
        let registered = RegisterEventHotKey(
            UInt32(code),
            carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference)
        guard registered == noErr else {
            // A failed register must leave nothing behind: the event handler is
            // already installed at this point, and the usual cause is another
            // application holding the shortcut, which the user will want to fix
            // and retry.
            stop()
            throw HotKeyError.registrationFailed(registered)
        }
    }

    func stop() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if let handlerReference { RemoveEventHandler(handlerReference) }
        handlerReference = nil
        action = nil
    }
}
