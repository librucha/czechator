/// Rules shared by every handler.
public struct CommonRules: Sendable, Codable, Equatable {
    public var minLength: Int
    public var requireLetters: Bool
    /// Regular expressions whose matches are excluded from every segment.
    public var skipPatterns: [String]

    public static let builtIn = CommonRules(
        minLength: 2,
        requireLetters: true,
        skipPatterns: [#"https?://\S+"#, #"\S+@\S+\.\S+"#]
    )

    public init(minLength: Int, requireLetters: Bool, skipPatterns: [String]) {
        self.minLength = minLength
        self.requireLetters = requireLetters
        self.skipPatterns = skipPatterns
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CommonRules.builtIn
        minLength = try c.decodeIfPresent(Int.self, forKey: .minLength) ?? d.minLength
        requireLetters = try c.decodeIfPresent(Bool.self, forKey: .requireLetters) ?? d.requireLetters
        skipPatterns = try c.decodeIfPresent([String].self, forKey: .skipPatterns) ?? d.skipPatterns
    }
}

public struct HTMLRules: Sendable, Codable, Equatable {
    public var skipElements: [String]
    public var skipAttributes: Bool
    public var skipComments: Bool

    public static let builtIn = HTMLRules(
        skipElements: ["script", "style", "code", "pre", "kbd", "samp", "var"],
        skipAttributes: true,
        skipComments: true
    )

    public init(skipElements: [String], skipAttributes: Bool, skipComments: Bool) {
        self.skipElements = skipElements
        self.skipAttributes = skipAttributes
        self.skipComments = skipComments
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HTMLRules.builtIn
        skipElements = try c.decodeIfPresent([String].self, forKey: .skipElements) ?? d.skipElements
        skipAttributes = try c.decodeIfPresent(Bool.self, forKey: .skipAttributes) ?? d.skipAttributes
        skipComments = try c.decodeIfPresent(Bool.self, forKey: .skipComments) ?? d.skipComments
    }
}

public struct XMLRules: Sendable, Codable, Equatable {
    public var skipElements: [String]
    public var skipAttributes: Bool
    public var skipComments: Bool
    public var skipProcessingInstructions: Bool
    public var skipCDATA: Bool

    public static let builtIn = XMLRules(
        skipElements: [],
        skipAttributes: true,
        skipComments: true,
        skipProcessingInstructions: true,
        skipCDATA: false
    )

    public init(skipElements: [String], skipAttributes: Bool, skipComments: Bool,
                skipProcessingInstructions: Bool, skipCDATA: Bool) {
        self.skipElements = skipElements
        self.skipAttributes = skipAttributes
        self.skipComments = skipComments
        self.skipProcessingInstructions = skipProcessingInstructions
        self.skipCDATA = skipCDATA
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = XMLRules.builtIn
        skipElements = try c.decodeIfPresent([String].self, forKey: .skipElements) ?? d.skipElements
        skipAttributes = try c.decodeIfPresent(Bool.self, forKey: .skipAttributes) ?? d.skipAttributes
        skipComments = try c.decodeIfPresent(Bool.self, forKey: .skipComments) ?? d.skipComments
        skipProcessingInstructions = try c.decodeIfPresent(Bool.self, forKey: .skipProcessingInstructions)
            ?? d.skipProcessingInstructions
        skipCDATA = try c.decodeIfPresent(Bool.self, forKey: .skipCDATA) ?? d.skipCDATA
    }
}

public struct JSONRules: Sendable, Codable, Equatable {
    public var skipKeys: Bool
    public var skipValuesForKeys: [String]

    public static let builtIn = JSONRules(
        skipKeys: true,
        skipValuesForKeys: ["id", "uuid", "url", "href", "path", "type", "kind"]
    )

    public init(skipKeys: Bool, skipValuesForKeys: [String]) {
        self.skipKeys = skipKeys
        self.skipValuesForKeys = skipValuesForKeys
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = JSONRules.builtIn
        skipKeys = try c.decodeIfPresent(Bool.self, forKey: .skipKeys) ?? d.skipKeys
        skipValuesForKeys = try c.decodeIfPresent([String].self, forKey: .skipValuesForKeys)
            ?? d.skipValuesForKeys
    }
}

public struct PlainRules: Sendable, Codable, Equatable {
    public var skipPatterns: [String]

    public static let builtIn = PlainRules(skipPatterns: [
        #"`[^`]+`"#,
        #"^```[\s\S]*?^```"#,
    ])

    public init(skipPatterns: [String]) { self.skipPatterns = skipPatterns }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skipPatterns = try c.decodeIfPresent([String].self, forKey: .skipPatterns)
            ?? PlainRules.builtIn.skipPatterns
    }
}

public struct SegmentationRules: Sendable, Codable, Equatable {
    public var common: CommonRules
    public var html: HTMLRules
    public var xml: XMLRules
    public var json: JSONRules
    public var plain: PlainRules

    public static let builtIn = SegmentationRules(
        common: .builtIn, html: .builtIn, xml: .builtIn, json: .builtIn, plain: .builtIn
    )

    public init(common: CommonRules, html: HTMLRules, xml: XMLRules,
                json: JSONRules, plain: PlainRules) {
        self.common = common
        self.html = html
        self.xml = xml
        self.json = json
        self.plain = plain
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        common = try c.decodeIfPresent(CommonRules.self, forKey: .common) ?? .builtIn
        html = try c.decodeIfPresent(HTMLRules.self, forKey: .html) ?? .builtIn
        xml = try c.decodeIfPresent(XMLRules.self, forKey: .xml) ?? .builtIn
        json = try c.decodeIfPresent(JSONRules.self, forKey: .json) ?? .builtIn
        plain = try c.decodeIfPresent(PlainRules.self, forKey: .plain) ?? .builtIn
    }
}
