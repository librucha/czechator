import Foundation

public enum ShortcutModifier: String, Sendable, CaseIterable {
    case cmd, ctrl, alt, shift
}

public enum ShortcutParseError: Error, Equatable {
    case empty
    case unknownToken(String)
    case noKey
    case multipleKeys
    case noModifier
}

public struct ShortcutSpec: Sendable, Equatable {
    public let modifiers: Set<ShortcutModifier>
    public let key: String

    public init(modifiers: Set<ShortcutModifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public static func parse(_ text: String) throws -> ShortcutSpec {
        let tokens = text.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { throw ShortcutParseError.empty }

        var modifiers: Set<ShortcutModifier> = []
        var keys: [String] = []
        for token in tokens {
            switch token {
            case "cmd", "command", "⌘": modifiers.insert(.cmd)
            case "ctrl", "control", "⌃": modifiers.insert(.ctrl)
            case "alt", "option", "opt", "⌥": modifiers.insert(.alt)
            case "shift", "⇧": modifiers.insert(.shift)
            default:
                guard token.count == 1 else { throw ShortcutParseError.unknownToken(token) }
                keys.append(token)
            }
        }
        guard !keys.isEmpty else { throw ShortcutParseError.noKey }
        guard keys.count == 1 else { throw ShortcutParseError.multipleKeys }
        // Without a modifier the hotkey would swallow that letter system-wide.
        guard !modifiers.isEmpty else { throw ShortcutParseError.noModifier }
        return ShortcutSpec(modifiers: modifiers, key: keys[0])
    }

    /// Cmd plus a single letter is almost always already taken by every app —
    /// Cmd+B is bold everywhere. The settings window warns about these.
    public var isCommonSystemShortcut: Bool {
        modifiers == [.cmd] && key.count == 1 && key.first?.isLetter == true
    }
}
