public struct Prompt: Sendable, Equatable {
    public let system: String
    public let user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

public enum PromptBuilder {

    /// Instructions in English, examples in Czech. Small instruct models follow
    /// English rules noticeably better, while the few-shot examples must be
    /// Czech because they are what actually demonstrates the task.
    ///
    /// MUST stay byte-identical between calls — Ollama caches the prefill for a
    /// stable prefix. Anything variable belongs in the user message.
    public static let defaultSystem = """
        You restore Czech diacritics.

        Rules:
        - Output ONLY the numbered list, with the same count and numbering as the input.
        - Change nothing except adding Czech diacritical marks.
        - Never translate, reword, reformat, or fix spelling, grammar or punctuation.
        - Preserve casing, whitespace, and all non-letter characters exactly.
        - The sequences \\n, \\r, \\t and \\\\ are literal two-character escapes. Keep them as-is.
        - Leave text that is not Czech unchanged.

        Example
        input:
        1. Prilis zlutoucky kun upel dabelske ody.
        2. Vcera jsem koupil novy pocitac.
        output:
        1. Příliš žluťoučký kůň úpěl ďábelské ódy.
        2. Včera jsem koupil nový počítač.
        """

    public static func build(items: [String], systemOverride: String?) -> Prompt {
        Prompt(system: systemOverride ?? defaultSystem, user: NumberedList.encode(items))
    }
}
