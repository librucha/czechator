/// What to put on the pasteboard, decided outside the AppKit layer so it can be
/// tested.
///
/// The sink used to write the plain flavour only when `correctedPlainText` was
/// non-nil, which is exactly nil for a plain-text clipboard. Copying HTML
/// *source* as plain text (from an editor, a mail, a chat) therefore left the
/// clipboard holding only `public.html` — pasting back into the editor produced
/// nothing. The clipboard must never come out less usable than it went in.
public enum ClipboardWritePlan {

    public struct Entry: Sendable, Equatable {
        public let uti: String
        public let value: String

        public init(uti: String, value: String) {
            self.uti = uti
            self.value = value
        }
    }

    public static func entries(for result: PipelineResult) -> [Entry] {
        var entries: [Entry] = []
        if result.formatID == HTMLHandler.id {
            entries.append(Entry(uti: "public.html", value: result.correctedText))
        }
        // Always a plain flavour: for an HTML clipboard it is the corrected
        // plain representation when there was one, otherwise the corrected
        // source itself.
        entries.append(
            Entry(
                uti: "public.utf8-plain-text",
                value: result.correctedPlainText ?? result.correctedText))
        return entries
    }
}
