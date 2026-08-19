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

public enum PipelineError: Error, Equatable {
    case noText
    case inputTooLarge(bytes: Int, limit: Int)
    case providerFailed(String)
    case verificationFailed(failedSegments: Int)
}

public struct Pipeline: Sendable {

    private let registry: FormatRegistry
    private let provider: any LLMProvider
    private let limits: Limits
    private let promptOverride: String?

    public init(
        registry: FormatRegistry, provider: any LLMProvider,
        limits: Limits, promptOverride: String?
    ) {
        self.registry = registry
        self.provider = provider
        self.limits = limits
        self.promptOverride = promptOverride
    }

    public func run(_ input: ClipboardInput) async throws -> PipelineResult {
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PipelineError.noText
        }
        let bytes = input.text.utf8.count + (input.plainText?.utf8.count ?? 0)
        guard bytes <= limits.maxInputBytes else {
            throw PipelineError.inputTooLarge(bytes: bytes, limit: limits.maxInputBytes)
        }

        // Shared across both passes: the plain representation of an HTML
        // clipboard repeats the same words, so it costs no extra model calls.
        var cache: [String: String] = [:]

        let selected = registry.select(input)
        let main = try await correct(input.text, handler: selected.handler, cache: &cache)

        var correctedPlain: Corrected?
        if let plain = input.plainText,
            plain != input.text,
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

        var corrections = [String](repeating: "", count: segments.count)
        var pending: [Int] = []
        for (index, segment) in segments.enumerated() {
            if let hit = cache[DiacriticFolding.fold(segment.text)] {
                corrections[index] = hit
            } else {
                pending.append(index)
            }
        }
        if !pending.isEmpty {
            try await fill(&corrections, indices: pending, segments: segments, cache: &cache)
        }

        // Verification runs BEFORE escaping, on the unescaped pair. Handlers'
        // escape routines assume the correction preserves grapheme count; this
        // is the check that guarantees it, so the order must not be swapped.
        let failing = DiacriticVerifier.failingIndices(segments: segments, corrections: corrections)
        if !failing.isEmpty {
            try await fill(&corrections, indices: failing, segments: segments, cache: &cache)
            let stillFailing = DiacriticVerifier.failingIndices(
                segments: segments, corrections: corrections)
            guard stillFailing.isEmpty else {
                throw PipelineError.verificationFailed(failedSegments: stillFailing.count)
            }
        }

        // Unchanged segments go back as their original bytes, so escaping can
        // never introduce a difference where the model made none.
        let replacements = zip(segments, corrections).map { segment, corrected in
            corrected == segment.text ? segment.raw : handler.escape(corrected, like: segment)
        }
        let output = try Reassembler.splice(
            text, segments: segments, replacements: replacements)
        guard DiacriticVerifier.documentMatches(original: text, corrected: output) else {
            throw PipelineError.verificationFailed(failedSegments: 0)
        }

        let changed = zip(segments, corrections).reduce(0) { $1.0.text != $1.1 ? $0 + 1 : $0 }
        return Corrected(text: output, segmentCount: segments.count, changedCount: changed)
    }

    private func fill(
        _ corrections: inout [String],
        indices: [Int],
        segments: [Segment],
        cache: inout [String: String]
    ) async throws {
        let subset = indices.map { segments[$0] }

        for batch in SegmentBatcher.batches(subset, maxChars: limits.maxBatchChars) {
            let items = batch.map { subset[$0].text }
            let prompt = PromptBuilder.build(items: items, systemOverride: promptOverride)

            let answer: String
            do {
                answer = try await provider.complete(prompt)
            } catch {
                throw PipelineError.providerFailed(String(describing: error))
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
                    throw PipelineError.providerFailed(String(describing: error))
                }
                do {
                    decoded = try NumberedList.decode(second, expectedCount: items.count)
                } catch {
                    throw PipelineError.providerFailed(
                        "odpověď modelu neodpovídá číslovanému seznamu")
                }
            }

            for (offset, positionInSubset) in batch.enumerated() {
                let target = indices[positionInSubset]
                corrections[target] = decoded[offset]
                cache[DiacriticFolding.fold(segments[target].text)] = decoded[offset]
            }
        }
    }
}
