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
    /// Tuned against qwen3:4b-instruct on a ten-sample suite. The generic
    /// "preserve casing" wording let the model capitalize sentence-initial
    /// words (`posilam` → `Posílám`); spelling the rule out with an example
    /// took the suite from 5/10 exact and 8/10 verified to 6/10 and 9/10.
    public static let defaultSystem = """
        You restore Czech diacritics. You are a mechanical transformer, not an editor.

        Rules:
        - Output ONLY the numbered list, with the same count and numbering as the input.
        - The ONLY change you may make is replacing a letter with its accented form:
          a->á, e->é/ě, i->í, o->ó, u->ú/ů, y->ý, c->č, d->ď, n->ň, r->ř, s->š, t->ť, z->ž.
        - NEVER change letter case. A word starting lowercase stays lowercase, even at
          the start of a sentence. "posilam" becomes "posílám", never "Posílám".
        - NEVER replace a word with a different word, even a synonym or a correction.
        - Never translate, reword, reformat, or fix spelling, grammar or punctuation.
        - Preserve whitespace and all non-letter characters exactly.
        - The sequences \\n, \\r, \\t and \\\\ are literal two-character escapes. Keep them as-is.
        - Leave text that is not Czech unchanged.

        Example
        input:
        1. Prilis zlutoucky kun upel dabelske ody.
        2. posilam vam slibene podklady, termin je pristi utery.
        3. This is English, leave it alone.
        output:
        1. Příliš žluťoučký kůň úpěl ďábelské ódy.
        2. posílám vám slíbené podklady, termín je příští úterý.
        3. This is English, leave it alone.
        """

    public static func build(items: [String], systemOverride: String?) -> Prompt {
        Prompt(system: systemOverride ?? defaultSystem, user: NumberedList.encode(items))
    }
}
