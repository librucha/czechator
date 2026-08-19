import AppKit
import CzechatorCore

struct PasteboardSink: OutputSink {

    init() {}

    func write(_ result: PipelineResult) throws {
        let pasteboard = NSPasteboard.general
        // clearContents() drops every representation, so everything the
        // clipboard should keep has to be written back explicitly.
        pasteboard.clearContents()
        for entry in ClipboardWritePlan.entries(for: result) {
            pasteboard.setString(entry.value, forType: .init(entry.uti))
        }
    }
}
