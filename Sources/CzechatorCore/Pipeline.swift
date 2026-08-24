import Foundation

public struct PipelineResult: Sendable, Equatable {
    public let formatID: String
    public let originalText: String
    public let correctedText: String
    public let correctedPlainText: String?
    public let segmentCount: Int
    public let changedSegmentCount: Int

    public init(
        formatID: String, originalText: String, correctedText: String,
        correctedPlainText: String?, segmentCount: Int, changedSegmentCount: Int
    ) {
        self.formatID = formatID
        self.originalText = originalText
        self.correctedText = correctedText
        self.correctedPlainText = correctedPlainText
        self.segmentCount = segmentCount
        self.changedSegmentCount = changedSegmentCount
    }
}

/// Why the model could not be used, as a category rather than a message.
///
/// The tool's only input is the clipboard, and its errors surface in
/// Notification Center, which persists them. Passing a transport message or a
/// slice of the server response through would leak the user's text — and, for
/// a 401 body, potentially the API key itself.
public enum ProviderFailure: Sendable, Equatable {
    case unreachable
    case unauthorized
    case http(status: Int)
    case unparsableResponse
}

public enum PipelineError: Error, Equatable {
    case noText
    case unparsableStructure
    case inputTooLarge(bytes: Int, limit: Int)
    case providerFailed(ProviderFailure)
    case verificationFailed(failedSegments: Int)
}

extension ProviderFailure {
    /// Collapses any provider error into a category, deliberately discarding
    /// every payload.
    static func categorize(_ error: any Error) -> ProviderFailure {
        switch error {
        case HTTPError.status(let code, _) where code == 401 || code == 403:
            return .unauthorized
        case HTTPError.status(let code, _):
            return .http(status: code)
        case HTTPError.transport:
            return .unreachable
        default:
            return .unparsableResponse
        }
    }
}

/// Reports what actually went to the model and came back.
///
/// Without it a failed run tells the user only how many segments were rejected,
/// not what the model said — which is precisely what you need to know to fix a
/// prompt. Nothing is collected unless an observer is installed.
public struct PipelineObserver: Sendable {
    public var onExchange: @Sendable (_ sent: [String], _ received: [String]) -> Void
    public var onRejected: @Sendable (_ original: String, _ correction: String) -> Void

    public init(
        onExchange: @escaping @Sendable ([String], [String]) -> Void,
        onRejected: @escaping @Sendable (String, String) -> Void
    ) {
        self.onExchange = onExchange
        self.onRejected = onRejected
    }
}

public struct Pipeline: Sendable {

    private let registry: FormatRegistry
    private let provider: any LLMProvider
    private let limits: Limits
    private let promptOverride: String?
    private let letterCase: LetterCasePolicy
    private let corrections: CorrectionMode
    private let editBudget: EditBudget
    private let verification: Bool
    private let observer: PipelineObserver?

    public init(
        registry: FormatRegistry, provider: any LLMProvider,
        limits: Limits, promptOverride: String?,
        letterCase: LetterCasePolicy = .preserve,
        corrections: CorrectionMode = .strict,
        editBudget: EditBudget = .builtIn,
        verification: Bool = true,
        observer: PipelineObserver? = nil
    ) {
        self.registry = registry
        self.provider = provider
        self.limits = limits
        self.promptOverride = promptOverride
        self.letterCase = letterCase
        self.corrections = corrections
        self.editBudget = editBudget
        self.verification = verification
        self.observer = observer
    }

    public func run(_ input: ClipboardInput) async throws -> PipelineResult {
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PipelineError.noText
        }
        // Only representations that will actually be processed count towards
        // the limit; an identical plain flavour is skipped, so charging for it
        // would reject inputs the tool would have handled fine.
        let plainToProcess = input.plainText.flatMap { $0 == input.text ? nil : $0 }
        let bytes = input.text.utf8.count + (plainToProcess?.utf8.count ?? 0)
        guard bytes <= limits.maxInputBytes else {
            throw PipelineError.inputTooLarge(bytes: bytes, limit: limits.maxInputBytes)
        }

        // Shared across both passes: the plain representation of an HTML
        // clipboard repeats the same words, so it costs no extra model calls.
        //
        // Keyed by the exact segment text, not its folded form. Folding would
        // let one segment's correction stand in for a different segment that
        // merely folds the same — "byt" served from "být" — and the verifier
        // cannot catch that, because both fold identically.
        var cache: [String: String] = [:]

        // Refusing beats guessing: a document that opens like structure but
        // does not parse would have its keys corrected as if they were prose.
        guard !registry.looksStructuredButUnclaimed(input) else {
            throw PipelineError.unparsableStructure
        }

        let selected = registry.select(input)
        let main = try await correct(input.text, handler: selected.handler, cache: &cache)

        var correctedPlain: Corrected?
        if let plain = plainToProcess,
            !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let plainHandler = registry.handler(id: PlainTextHandler.id)
        {
            correctedPlain = try await correct(plain, handler: plainHandler, cache: &cache)
        }

        return PipelineResult(
            formatID: selected.id,
            originalText: input.text,
            correctedText: main.text,
            correctedPlainText: correctedPlain?.text,
            segmentCount: main.segmentCount,
            changedSegmentCount: main.changedCount)
    }

    private struct Corrected {
        let text: String
        let segmentCount: Int
        let changedCount: Int
    }

    private func correct(
        _ text: String,
        handler: any FormatHandler,
        cache: inout [String: String]
    ) async throws -> Corrected {
        let segments = try handler.segments(in: text)
        guard !segments.isEmpty else {
            return Corrected(text: text, segmentCount: 0, changedCount: 0)
        }

        // Computed once: `detect` walks the raw segment, and the retry branch
        // would otherwise repeat that walk for every segment on every round.
        let protectedIndices: [Int: Set<Int>] = Dictionary(
            uniqueKeysWithValues: segments.indices.map {
                ($0, handler.protectedIndices(in: segments[$0]))
            })

        var corrections = [String](repeating: "", count: segments.count)
        var pending: [Int] = []
        var restorationFailures: Set<Int> = []
        for (index, segment) in segments.enumerated() {
            if let hit = cache[segment.text] {
                corrections[index] = hit
            } else {
                pending.append(index)
            }
        }
        if !pending.isEmpty {
            try await fill(
                &corrections, indices: pending, segments: segments, cache: &cache,
                restorationFailures: &restorationFailures)
        }

        // Verification runs BEFORE escaping, on the unescaped pair, so the
        // alignment computed here is the one escaping then replays.
        var alignments: [Int: EditAlignment] = [:]

        if verification {
            var failing = failures(
                segments: segments, corrections: corrections,
                restorationFailures: restorationFailures,
                protectedIndices: protectedIndices, alignments: &alignments)
            if !failing.isEmpty {
                restorationFailures.removeAll()
                alignments.removeAll()
                try await fill(
                    &corrections, indices: failing, segments: segments, cache: &cache,
                    restorationFailures: &restorationFailures)
                failing = failures(
                    segments: segments, corrections: corrections,
                    restorationFailures: restorationFailures,
                    protectedIndices: protectedIndices, alignments: &alignments)
                guard failing.isEmpty else {
                    for index in failing {
                        observer?.onRejected(segments[index].text, corrections[index])
                    }
                    throw PipelineError.verificationFailed(failedSegments: failing.count)
                }
            }
        } else {
            // Escaping still needs the index map even when nothing is checked,
            // and in every mode: without it the recorded entity and escape
            // spellings are replayed at their ORIGINAL indices, so a correction
            // of a different length silently relocates them instead of failing.
            // What switching verification off gives up is checking the model,
            // not the guard against our own reassembly.
            for index in segments.indices where corrections[index] != segments[index].text {
                if let alignment = EditAlignment.compute(
                    Array(segments[index].text), Array(corrections[index]),
                    limit: DiacriticVerifier.toleranceLimit)
                {
                    alignments[index] = alignment
                    continue
                }
                // Past the alignment limit there is no index map to be had, and
                // nothing checked the correction's length either. Escaping a
                // segment that records a spelling would replay it at the old
                // index; refuse instead. A segment with nothing to protect is
                // escaped index-independently, so it is let through.
                guard protectedIndices[index]?.isEmpty ?? true else {
                    throw PipelineError.verificationFailed(failedSegments: 1)
                }
            }
        }

        // Unchanged segments go back as their original bytes, so escaping can
        // never introduce a difference where the model made none.
        var replacements: [String] = []
        replacements.reserveCapacity(segments.count)
        for (index, segment) in segments.enumerated() {
            if corrections[index] == segment.text {
                replacements.append(segment.raw)
                continue
            }
            guard
                let escaped = handler.escape(
                    corrections[index], like: segment, alignment: alignments[index])
            else {
                throw PipelineError.verificationFailed(failedSegments: 1)
            }
            replacements.append(escaped)
        }

        let output = try Reassembler.splice(
            text, segments: segments, replacements: replacements)
        guard
            DiacriticVerifier.gapsMatch(
                original: text, output: output, segments: segments, replacements: replacements)
        else {
            throw PipelineError.verificationFailed(failedSegments: 0)
        }

        let changed = zip(segments, corrections).reduce(0) { $1.0.text != $1.1 ? $0 + 1 : $0 }
        return Corrected(text: output, segmentCount: segments.count, changedCount: changed)
    }

    /// Segments that must be retried, and the index maps the survivors need.
    ///
    /// Two independent reasons to fail: the correction went past the budget, or
    /// it moved a protected index out from under an entity or a masked space.
    /// Both go through the retry branch rather than straight to an error.
    private func failures(
        segments: [Segment], corrections: [String],
        restorationFailures: Set<Int>,
        protectedIndices: [Int: Set<Int>],
        alignments: inout [Int: EditAlignment]
    ) -> [Int] {
        var failing = Set(
            DiacriticVerifier.failingIndices(
                segments: segments, corrections: corrections, policy: letterCase,
                mode: self.corrections, budget: editBudget))
        failing.formUnion(restorationFailures)

        guard self.corrections.isTolerant else { return failing.sorted() }

        for index in segments.indices where !failing.contains(index) {
            guard corrections[index] != segments[index].text else { continue }
            guard
                let alignment = EditAlignment.compute(
                    Array(segments[index].text), Array(corrections[index]),
                    limit: DiacriticVerifier.toleranceLimit)
            else { continue }
            let protected = protectedIndices[index] ?? []
            if protected.contains(where: { alignment.map[$0] == nil }) {
                failing.insert(index)
            } else {
                alignments[index] = alignment
            }
        }
        return failing.sorted()
    }

    /// Restores the segment's own leading and trailing whitespace.
    ///
    /// Segments are whitespace-trimmed at their edges by construction, so any
    /// edge whitespace the model returns is its own artifact — qwen3 appends two
    /// spaces to every line, the Markdown hard-break convention, which the
    /// verifier then rejects for the whole document. The one exception is
    /// whitespace that unescaping produced (a trailing `\n` inside a JSON
    /// string), which is why the original's edges are re-attached rather than
    /// simply trimmed away.
    ///
    /// Only the edges are touched; every other difference still faces the
    /// verifier unchanged.
    ///
    /// The realignment is unconditional, which means a model that *dropped* real
    /// edge content — the trailing `\n` of a JSON string — is indistinguishable
    /// from one that merely added spaces, and gets silently corrected instead of
    /// retried. The output is still forced to the truth, so nothing wrong can
    /// reach the clipboard; the verifier simply never sees that particular slip.
    static func alignEdgeWhitespace(_ corrected: String, like original: String) -> String {
        let leading = original.prefix { $0.isWhitespace }
        let trailing = original.reversed().prefix { $0.isWhitespace }.reversed()
        let core = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(leading) + core + String(trailing)
    }

    /// Forces the original's letter case back onto the correction.
    ///
    /// The model capitalizes sentence-initial words no matter how the prompt is
    /// worded — `proc se to muselo…` comes back as `Proc se to muselo…` — and
    /// the verifier then refuses the whole document. Case is never something a
    /// diacritic restoration may change, so it can simply be imposed rather than
    /// asked for.
    ///
    /// Only a character that is the *same letter* is touched: the comparison
    /// folds away both case and diacritics first. Anything else stays as the
    /// model wrote it and still faces the verifier.
    static func alignCase(
        _ corrected: String, like original: String,
        policy: LetterCasePolicy = .preserve, mode: CorrectionMode = .strict
    ) -> String {
        // A tolerant mode asked the model to fix capitalization, so forcing the
        // original back would undo the very thing that was requested. The
        // consequence is that `letterCase` does nothing outside strict mode,
        // and the settings window greys it out to say so.
        guard !mode.isTolerant, policy != .model, corrected.count == original.count else {
            return corrected
        }

        var out = ""
        out.reserveCapacity(corrected.count)
        for (index, (source, candidate)) in zip(original, corrected).enumerated() {
            if policy == .segmentStart, index == 0 {
                out.append(candidate)
                continue
            }
            let sameLetter =
                DiacriticFolding.fold(String(source)).lowercased()
                == DiacriticFolding.fold(String(candidate)).lowercased()
            guard sameLetter, source.isLetter, candidate.isLetter else {
                out.append(candidate)
                continue
            }
            if source.isLowercase, candidate.isUppercase {
                out += String(candidate).lowercased()
            } else if source.isUppercase, candidate.isLowercase {
                out += String(candidate).uppercased()
            } else {
                out.append(candidate)
            }
        }
        return out
    }

    private func fill(
        _ corrections: inout [String],
        indices: [Int],
        segments: [Segment],
        cache: inout [String: String],
        restorationFailures: inout Set<Int>
    ) async throws {
        let subset = indices.map { segments[$0] }

        for batch in SegmentBatcher.batches(subset, maxChars: limits.maxBatchChars) {
            // Fragile whitespace is hidden from the model and restored by
            // position afterwards; see FragileWhitespace.
            let masks = batch.map { FragileWhitespace.mask(subset[$0].text) }
            let items = masks.map(\.masked)
            let prompt = PromptBuilder.build(
                items: items, mode: self.corrections, systemOverride: promptOverride)

            let answer: String
            do {
                answer = try await provider.complete(prompt)
            } catch {
                throw PipelineError.providerFailed(.categorize(error))
            }

            var decoded: [String]
            do {
                decoded = try NumberedList.decode(answer, expectedCount: items.count)
            } catch {
                // A malformed list gets exactly one more attempt.
                let second: String
                do {
                    second = try await provider.complete(prompt)
                } catch {
                    throw PipelineError.providerFailed(.categorize(error))
                }
                do {
                    decoded = try NumberedList.decode(second, expectedCount: items.count)
                } catch {
                    throw PipelineError.providerFailed(.unparsableResponse)
                }
            }

            observer?.onExchange(items, decoded)

            for (offset, positionInSubset) in batch.enumerated() {
                let target = indices[positionInSubset]
                // Edge alignment first: the model appends trailing spaces, and
                // restoring by position has to see a string of the original
                // length or it gives up — which would drop every masked
                // character on exactly the inputs the masking exists for.
                let aligned = Self.alignEdgeWhitespace(
                    decoded[offset], like: masks[offset].masked)
                let maskAlignment =
                    self.corrections.isTolerant
                    ? EditAlignment.compute(
                        Array(masks[offset].masked), Array(aligned),
                        limit: DiacriticVerifier.toleranceLimit)
                    : nil
                guard let unmasked = masks[offset].restore(into: aligned, alignment: maskAlignment)
                else {
                    // The masked character did not survive. Recording the
                    // failure rather than storing the original keeps the retry
                    // branch honest: storing the original would look unchanged
                    // and sail through verification.
                    restorationFailures.insert(target)
                    corrections[target] = aligned
                    continue
                }
                let restored = Self.alignCase(
                    unmasked, like: segments[target].text,
                    policy: letterCase, mode: self.corrections)
                corrections[target] = restored
                cache[segments[target].text] = restored
            }
        }
    }
}
