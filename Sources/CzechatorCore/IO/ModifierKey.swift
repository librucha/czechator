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

    /// Virtual key codes as `NSEvent.keyCode` reports them for modifier
    /// changes.
    ///
    /// Written out rather than imported: these come from Carbon's `Events.h`,
    /// which this module must not depend on if the core is to stay portable.
    /// Checked against the macOS 26.5 SDK — `kVK_RightCommand` 0x36,
    /// `kVK_Command` 0x37, `kVK_Option` 0x3A, `kVK_RightOption` 0x3D. Note that
    /// the unqualified names are the left-hand keys.
    public var keyCode: Int {
        switch self {
        case .rightCommand: return 0x36
        case .leftCommand: return 0x37
        case .rightOption: return 0x3D
        case .leftOption: return 0x3A
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
