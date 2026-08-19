/// Plain text and Markdown. Each line is its own candidate, which keeps
/// newlines outside segments and gives the batcher a natural granularity.
public struct PlainTextHandler: FormatHandler {

    public static let id = "plain"

    /// Constant low value: this is the fallback every other handler outbids.
    public static func confidence(for input: ClipboardInput) -> Double { 0.1 }

    /// A key at the start of a line, as written by TOML, INI, YAML and
    /// .properties — formats this tool does not parse but that people do paste.
    /// Handing such a key to the model gets it renamed, and `fold` cannot tell,
    /// because `fold("název") == fold("nazev")`.
    ///
    /// Deliberately **not** part of `SegmentationRules`: the configurable
    /// patterns are materialized to disk on first run, so a config written by an
    /// older build would keep overriding this one and leave that installation
    /// unprotected forever. Skip rules that exist for taste are configurable;
    /// rules that exist to prevent corruption are not.
    private static let protectedKeyPattern = #"^[ \t]*[A-Za-z_][A-Za-z0-9_.\-]*[ \t]*[:=]"#

    private let builder: SegmentBuilder

    public init(rules: SegmentationRules) throws {
        builder = try SegmentBuilder(
            common: rules.common,
            extraSkipPatterns: rules.plain.skipPatterns + [Self.protectedKeyPattern])
    }

    public func segments(in text: String) throws -> [Segment] {
        let prepared = builder.prepared(for: text)
        var result: [Segment] = []
        var lineStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            // `isNewline`, not `== "\n"`: Swift treats CRLF as a single
            // grapheme that equals neither "\n" nor "\r", so a Windows
            // document would otherwise come out as one giant candidate.
            if text[index].isNewline {
                result += prepared.build(candidate: lineStart..<index, kind: .plain) { String($0) }
                lineStart = text.index(after: index)
            }
            index = text.index(after: index)
        }
        result += prepared.build(candidate: lineStart..<text.endIndex, kind: .plain) { String($0) }
        return result
    }

    public func escape(_ corrected: String, like original: Segment) -> String { corrected }
}
