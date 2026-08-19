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

        func flushText(upTo end: String.Index) {
            guard textStart < end else { return }
            if stack.contains(where: { options.skipElements.contains($0) }) { return }
            nodes.append(
                MarkupTextNode(
                    range: textStart..<end, elementPath: stack, isAttributeValue: false))
        }

        while index < text.endIndex {
            guard text[index] == "<" else {
                index = text.index(after: index)
                continue
            }

            if text[index...].hasPrefix("<!--") {
                flushText(upTo: index)
                index = advance(text, from: index, past: "-->")
                textStart = index
                continue
            }

            if text[index...].hasPrefix("<![CDATA[") {
                flushText(upTo: index)
                let contentStart = text.index(index, offsetBy: 9)
                let end = advance(text, from: contentStart, past: "]]>")
                if !options.skipCDATA,
                    !stack.contains(where: { options.skipElements.contains($0) })
                {
                    let contentEnd = text.index(end, offsetBy: -3, limitedBy: contentStart)
                        ?? contentStart
                    if contentStart < contentEnd {
                        nodes.append(
                            MarkupTextNode(
                                range: contentStart..<contentEnd, elementPath: stack,
                                isAttributeValue: false))
                    }
                }
                index = end
                textStart = index
                continue
            }

            if text[index...].hasPrefix("<?") {
                flushText(upTo: index)
                index = advance(text, from: index, past: "?>")
                textStart = index
                continue
            }

            if text[index...].hasPrefix("<!") {
                flushText(upTo: index)
                index = advance(text, from: index, past: ">")
                textStart = index
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

    private static func advance(
        _ text: String, from index: String.Index, past terminator: String
    ) -> String.Index {
        guard let found = text.range(of: terminator, range: index..<text.endIndex) else {
            return text.endIndex
        }
        return found.upperBound
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
