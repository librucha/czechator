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
    ///
    /// It also introduced the mirror problem: a genuinely capitalized sentence
    /// start now sometimes comes back lowercased. The verifier rejects that too,
    /// so it costs a refusal rather than a corruption.
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

    /// Instructions in English, examples in Czech, for the same reason
    /// `defaultSystem` is: small instruct models follow English rules better,
    /// but only Czech examples demonstrate the task.
    ///
    /// A separate constant rather than `defaultSystem` plus a clause: Ollama
    /// caches the prefill for a stable prefix, and three fixed strings keep
    /// that intact where a composed one would not.
    public static let minorFixesSystem = """
        You restore Czech diacritics and fix small typing mistakes.

        Rules:
        - Output ONLY the numbered list, with the same count and numbering as the input.
        - You MAY add Czech accents: a->á, e->é/ě, i->í, o->ó, u->ú/ů, y->ý,
          c->č, d->ď, n->ň, r->ř, s->š, t->ť, z->ž.
        - You MAY fix an obvious typing mistake: a swapped, missing or doubled letter,
          a misplaced space, a missing comma or period, a wrong i/y or s/z.
        - You MAY fix capitalization at the start of a sentence.
        - NEVER replace a word with a different word, a synonym or a translation.
        - NEVER reorder, reword, reformat, shorten or explain anything.
        - Change as little as possible. If a word is already correct, leave it alone.
        - Preserve all other non-letter characters exactly.
        - The sequences \\n, \\r, \\t and \\\\ are literal two-character escapes. Keep them as-is.
        - Leave text that is not Czech unchanged.

        Example
        input:
        1. Prilis zlutoucky kun upel dabelske ody.
        2. kdy zjsem sel domu bylo uz pozde
        3. This is English, leave it alone.
        output:
        1. Příliš žluťoučký kůň úpěl ďábelské ódy.
        2. Když jsem šel domů, bylo už pozdě.
        3. This is English, leave it alone.
        """

    public static let proofreadSystem = """
        You are a Czech proofreader.

        Rules:
        - Output ONLY the numbered list, with the same count and numbering as the input.
        - Restore Czech accents, fix typing mistakes, spelling, punctuation,
          capitalization and grammatical agreement.
        - NEVER replace a word with a synonym, and never translate.
        - NEVER reorder sentences, reword for style, shorten, expand or explain.
        - Change as little as possible. If a sentence is already correct, repeat it verbatim.
        - The sequences \\n, \\r, \\t and \\\\ are literal two-character escapes. Keep them as-is.
        - Leave text that is not Czech unchanged.

        Example
        input:
        1. Prilis zlutoucky kun upel dabelske ody.
        2. kdy zjsem sel domu bilo uz pozde a dvere bili zamcene
        3. This is English, leave it alone.
        output:
        1. Příliš žluťoučký kůň úpěl ďábelské ódy.
        2. Když jsem šel domů, bylo už pozdě a dveře byly zamčené.
        3. This is English, leave it alone.
        """

    public static func system(for mode: CorrectionMode) -> String {
        switch mode {
        case .strict: return defaultSystem
        case .minorFixes: return minorFixesSystem
        case .proofread: return proofreadSystem
        }
    }

    public static func build(
        items: [String], mode: CorrectionMode = .strict, systemOverride: String?
    ) -> Prompt {
        Prompt(system: systemOverride ?? system(for: mode), user: NumberedList.encode(items))
    }
}
