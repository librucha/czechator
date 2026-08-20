/// A modifier key the double-tap trigger can watch, with the side it is on.
///
/// The side matters: a trigger on plain "command" would fire during every quick
/// `⌘C ⌘V`, which is why the raw key code — not the modifier flag — is what
/// identifies it.
public enum ModifierKey: String, Sendable, Codable, Equatable, CaseIterable {
    case rightCommand
    case leftCommand
    case rightOption
    case leftOption

    /// Virtual key codes from Carbon's `Events.h`, which `NSEvent.keyCode`
    /// reports for modifier changes.
    public var keyCode: Int {
        switch self {
        case .rightCommand: return 54
        case .leftCommand: return 55
        case .rightOption: return 61
        case .leftOption: return 58
        }
    }

    public static func from(keyCode: Int) -> ModifierKey? {
        allCases.first { $0.keyCode == keyCode }
    }

    public var label: String {
        switch self {
        case .rightCommand: return "pravý ⌘"
        case .leftCommand: return "levý ⌘"
        case .rightOption: return "pravý ⌥"
        case .leftOption: return "levý ⌥"
        }
    }
}
