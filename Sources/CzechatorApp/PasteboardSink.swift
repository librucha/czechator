import AppKit
import CzechatorCore

struct PasteboardSink: OutputSink {

    init() {}

    func write(_ result: PipelineResult) throws {
        let pasteboard = NSPasteboard.general
        // clearContents() drops every representation, so writing back only the
        // plain flavour of an HTML clipboard would lose the formatting on paste.
        pasteboard.clearContents()
        if result.formatID == HTMLHandler.id {
            pasteboard.setString(result.correctedText, forType: .html)
            if let plain = result.correctedPlainText {
                pasteboard.setString(plain, forType: .string)
            }
        } else {
            pasteboard.setString(result.correctedText, forType: .string)
        }
    }
}
