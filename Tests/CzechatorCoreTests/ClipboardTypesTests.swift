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
    #expect(ClipboardTypes.choose(["public.rtf", "public.html", "public.utf8-plain-text"]) == .html)
}

@Test func prefersPlainTextOverRTF() {
    #expect(ClipboardTypes.choose(["public.rtf", "public.utf8-plain-text"]) == .plain)
}

@Test func reportsImagesAndFilesAsHavingNoText() {
    #expect(ClipboardTypes.choose(["public.png"]) == .none)
    #expect(ClipboardTypes.choose(["public.file-url"]) == .none)
    #expect(ClipboardTypes.choose([]) == .none)
}
