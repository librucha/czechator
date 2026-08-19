public enum ClipboardError: Error, Equatable {
    case empty
    case noTextRepresentation(availableTypes: [String])
    case unsupportedFormat(String)
}

/// Where the text to correct comes from. MVP ships only a clipboard source;
/// a later version adds a selection source that fakes Cmd+C into the frontmost
/// application.
public protocol InputSource: Sendable {
    func read() throws -> ClipboardInput
}
