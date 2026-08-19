public enum ClipboardTypeChoice: Sendable, Equatable {
    case html
    case plain
    case unsupported(String)
    case none
}

/// NSPasteboard holds one item in several representations at once, each under
/// its own UTI. This picks the richest one the tool can actually rewrite.
public enum ClipboardTypes {

    public static func choose(_ types: [String]) -> ClipboardTypeChoice {
        if types.contains("public.html") { return .html }
        if types.contains("public.utf8-plain-text") || types.contains("public.plain-text") {
            return .plain
        }
        // Rewriting RTF would mean parsing it just to add accents — a poor
        // trade, so it is reported rather than mangled.
        if types.contains("public.rtf") { return .unsupported("RTF") }
        return .none
    }
}
