import AppKit
import CzechatorCore

/// Reads the general pasteboard directly: NSPasteboard is not Sendable and is
/// main-thread bound, so there is nothing to inject. The part worth testing —
/// which representation to pick — lives in `ClipboardTypes`.
struct PasteboardSource: InputSource {

    init() {}

    func read() throws -> ClipboardInput {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types?.map(\.rawValue) ?? []

        switch ClipboardTypes.choose(types) {
        case .html:
            guard let html = pasteboard.string(forType: .html) else {
                throw ClipboardError.noTextRepresentation(availableTypes: types)
            }
            return ClipboardInput(
                text: html, uti: "public.html", plainText: pasteboard.string(forType: .string))
        case .plain:
            guard let plain = pasteboard.string(forType: .string) else {
                throw ClipboardError.noTextRepresentation(availableTypes: types)
            }
            return ClipboardInput(text: plain, uti: "public.utf8-plain-text", plainText: nil)
        case .unsupported(let name):
            throw ClipboardError.unsupportedFormat(name)
        case .none:
            throw ClipboardError.noTextRepresentation(availableTypes: types)
        }
    }
}
