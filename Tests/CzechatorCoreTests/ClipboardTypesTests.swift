import Foundation
import Testing

@testable import CzechatorCore

@Test func prefersHTMLWhenAvailable() {
    #expect(ClipboardTypes.choose(["public.html", "public.utf8-plain-text"]) == .html)
}

@Test func clipboardTypesFallBackToPlainText() {
    #expect(ClipboardTypes.choose(["public.utf8-plain-text"]) == .plain)
    #expect(ClipboardTypes.choose(["public.utf8-plain-text", "public.file-url"]) == .plain)
}

@Test func reportsRTFOnlyClipboardsAsUnsupported() {
    #expect(ClipboardTypes.choose(["public.rtf"]) == .unsupported("RTF"))
}

@Test func prefersHTMLEvenWhenRTFIsPresent() {
    #expect(
        ClipboardTypes.choose(["public.rtf", "public.html", "public.utf8-plain-text"]) == .html)
}

@Test func prefersPlainTextOverRTF() {
    #expect(ClipboardTypes.choose(["public.rtf", "public.utf8-plain-text"]) == .plain)
}

@Test func reportsImagesAndFilesAsHavingNoText() {
    #expect(ClipboardTypes.choose(["public.png"]) == .none)
    #expect(ClipboardTypes.choose(["public.file-url"]) == .none)
    #expect(ClipboardTypes.choose([]) == .none)
}

private func result(format: String, text: String, plain: String?) -> PipelineResult {
    PipelineResult(
        formatID: format, originalText: text, correctedText: text,
        correctedPlainText: plain, segmentCount: 1, changedSegmentCount: 1)
}

@Test func plainClipboardGetsExactlyOnePlainEntry() {
    let entries = ClipboardWritePlan.entries(for: result(format: "plain", text: "ahoj", plain: nil))
    #expect(entries == [.init(uti: "public.utf8-plain-text", value: "ahoj")])
}

@Test func htmlClipboardKeepsBothFlavours() {
    let entries = ClipboardWritePlan.entries(
        for: result(format: "html", text: "<p>ahoj</p>", plain: "ahoj"))
    #expect(entries.map(\.uti) == ["public.html", "public.utf8-plain-text"])
    #expect(entries[1].value == "ahoj")
}

@Test func htmlSourceCopiedAsPlainTextStillGetsAPlainFlavour() {
    // The clipboard must never come back less usable than it went in.
    let entries = ClipboardWritePlan.entries(
        for: result(format: "html", text: "<p>ahoj</p>", plain: nil))
    #expect(entries.map(\.uti) == ["public.html", "public.utf8-plain-text"])
    #expect(entries[1].value == "<p>ahoj</p>")
}
