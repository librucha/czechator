import Foundation

public struct MarkupTextNode: Sendable, Equatable {
    public let range: Range<String.Index>
    /// Lowercased element names, outermost first.
    public let elementPath: [String]
    public let isAttributeValue: Bool

    public init(range: Range<String.Index>, elementPath: [String], isAttributeValue: Bool) {
        self.range = range
        self.elementPath = elementPath
        self.isAttributeValue = isAttributeValue
    }
}

public struct MarkupScanOptions: Sendable {
    public var skipElements: Set<String>
    public var skipComments: Bool
    public var skipProcessingInstructions: Bool
    public var skipCDATA: Bool
    public var includeAttributeValues: Bool
    /// Elements that never have a closing tag (HTML only).
    public var voidElements: Set<String>

    public init(
        skipElements: Set<String>, skipComments: Bool,
        skipProcessingInstructions: Bool, skipCDATA: Bool,
        includeAttributeValues: Bool, voidElements: Set<String>
    ) {
        self.skipElements = skipElements
        self.skipComments = skipComments
        self.skipProcessingInstructions = skipProcessingInstructions
        self.skipCDATA = skipCDATA
        self.includeAttributeValues = includeAttributeValues
        self.voidElements = voidElements
    }

    public static let htmlVoidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]
}

/// Shared scanner for XML and HTML. Deliberately forgiving: malformed markup
/// yields fewer text nodes rather than an error, because the verifier is the
/// real safety net.
public enum MarkupScanner {

    public static func looksLikeMarkup(_ text: String) -> Bool {
        guard let open = text.firstIndex(of: "<") else { return false }
        let after = text.index(after: open)
        guard after < text.endIndex else { return false }
        let next = text[after]
        guard next.isLetter || next == "/" || next == "?" || next == "!" else { return false }
        return text[after...].contains(">")
    }

    public static func scan(_ text: String, options: MarkupScanOptions) -> [MarkupTextNode] {
        var nodes: [MarkupTextNode] = []
        var stack: [String] = []
        var index = text.startIndex
        var textStart = text.startIndex

        /// Emits a node unless an enclosing element is on the skip list.
        func emit(_ range: Range<String.Index>) {
            guard range.lowerBound < range.upperBound else { return }
            if stack.contains(where: { options.skipElements.contains($0) }) { return }
            nodes.append(
                MarkupTextNode(range: range, elementPath: stack, isAttributeValue: false))
        }

        func flushText(upTo end: String.Index) {
            guard textStart < end else { return }
            emit(textStart..<end)
        }

        /// Handles one delimited construct: emits its body when the matching
        /// skip flag is off, then resumes after the terminator.
        func consume(
            openingWidth: Int, terminator: String, skipped: Bool, from opening: String.Index
        ) {
            flushText(upTo: opening)
            let contentStart = text.index(opening, offsetBy: openingWidth)
            let bounds = span(text, from: contentStart, terminatedBy: terminator)
            if !skipped { emit(contentStart..<bounds.contentEnd) }
            index = bounds.resume
            textStart = index
        }

        while index < text.endIndex {
            guard text[index] == "<" else {
                index = text.index(after: index)
                continue
            }

            if text[index...].hasPrefix("<!--") {
                consume(
                    openingWidth: 4, terminator: "-->", skipped: options.skipComments, from: index)
                continue
            }

            if text[index...].hasPrefix("<![CDATA[") {
                consume(
                    openingWidth: 9, terminator: "]]>", skipped: options.skipCDATA, from: index)
                continue
            }

            if text[index...].hasPrefix("<?") {
                consume(
                    openingWidth: 2, terminator: "?>",
                    skipped: options.skipProcessingInstructions, from: index)
                continue
            }

            if text[index...].hasPrefix("<!") {
                // Doctype and other declarations are never correctable text.
                consume(openingWidth: 2, terminator: ">", skipped: true, from: index)
                continue
            }

            guard let tagEnd = text[index...].firstIndex(of: ">") else { break }
            flushText(upTo: index)

            let inner = text[text.index(after: index)..<tagEnd]
            if inner.hasPrefix("/") {
                let name = elementName(of: inner.dropFirst())
                if let position = stack.lastIndex(of: name) {
                    stack.removeSubrange(position...)
                }
            } else {
                let name = elementName(of: inner)
                if options.includeAttributeValues,
                    !stack.contains(where: { options.skipElements.contains($0) }),
                    !options.skipElements.contains(name)
                {
                    nodes += attributeValues(tagInner: inner, path: stack + [name])
                }
                let selfClosing = inner.hasSuffix("/") || options.voidElements.contains(name)
                if !selfClosing { stack.append(name) }
            }

            index = text.index(after: tagEnd)
            textStart = index
        }
        flushText(upTo: text.endIndex)
        return nodes
    }

    private static func elementName(of inner: Substring) -> String {
        String(inner.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":" })
            .lowercased()
    }

    /// Locates a construct's body and where scanning resumes after it.
    ///
    /// An unterminated construct runs to the end of the document; the body then
    /// ends at `endIndex` too. Computing the body end by subtracting the
    /// terminator's length would silently eat the last characters of real text.
    private static func span(
        _ text: String, from start: String.Index, terminatedBy terminator: String
    ) -> (contentEnd: String.Index, resume: String.Index) {
        guard let found = text.range(of: terminator, range: start..<text.endIndex) else {
            return (text.endIndex, text.endIndex)
        }
        return (found.lowerBound, found.upperBound)
    }

    /// Scans `name="value"` pairs inside an already-delimited tag body.
    /// The returned ranges index into the same storage as the whole document,
    /// because a Substring shares its parent's indices.
    private static func attributeValues(
        tagInner: Substring, path: [String]
    ) -> [MarkupTextNode] {
        var nodes: [MarkupTextNode] = []
        var index = tagInner.startIndex
        while index < tagInner.endIndex {
            guard tagInner[index] == "\"" || tagInner[index] == "'" else {
                index = tagInner.index(after: index)
                continue
            }
            let quote = tagInner[index]
            let start = tagInner.index(after: index)
            guard let end = tagInner[start...].firstIndex(of: quote) else { break }
            if start < end {
                nodes.append(
                    MarkupTextNode(range: start..<end, elementPath: path, isAttributeValue: true))
            }
            index = tagInner.index(after: end)
        }
        return nodes
    }
}
