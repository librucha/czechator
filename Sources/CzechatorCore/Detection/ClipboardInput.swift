/// What the core receives from an `InputSource`.
///
/// `text` is the richest representation the source could offer (HTML when
/// available), `plainText` is the plain fallback that must be rewritten
/// alongside it so the pasteboard keeps both flavours in sync.
public struct ClipboardInput: Sendable, Equatable {
    public let text: String
    public let uti: String?
    public let plainText: String?

    public init(text: String, uti: String? = nil, plainText: String? = nil) {
        self.text = text
        self.uti = uti
        self.plainText = plainText
    }
}
