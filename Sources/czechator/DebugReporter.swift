import CzechatorCore
import Foundation

/// Prints what went to the model and what came back, on stderr so it never
/// contaminates the corrected text on stdout.
enum DebugReporter {

    static func observer() -> PipelineObserver {
        PipelineObserver(
            onExchange: { sent, received in
                write("\n── dávka (\(sent.count) položek) ──")
                for (index, item) in sent.enumerated() {
                    let answer = index < received.count ? received[index] : "(chybí)"
                    write("  \(index + 1). posláno: \(visible(item))")
                    write("     vráceno: \(visible(answer))")
                    if item != answer, DiacriticFolding.fold(item) == DiacriticFolding.fold(answer)
                    {
                        write("     → jen diakritika, v pořádku")
                    }
                }
            },
            onRejected: { original, correction in
                write("\n── ZAMÍTNUTO ──")
                write("  originál: \(visible(original))")
                write("  model:    \(visible(correction))")
                write("  rozdíl:   \(difference(original, correction))")
            })
    }

    /// The first place the folded forms diverge, which is the change the model
    /// made beyond adding accents — the reason the document was refused.
    private static func difference(_ original: String, _ correction: String) -> String {
        let left = Array(DiacriticFolding.fold(original))
        let right = Array(DiacriticFolding.fold(correction))
        var index = 0
        while index < left.count, index < right.count, left[index] == right[index] { index += 1 }

        if index == left.count && index == right.count { return "žádný (neshoda jinde)" }
        let context = 12
        let from = Swift.max(0, index - context)
        func window(_ characters: [Character]) -> String {
            let to = Swift.min(characters.count, index + context)
            return from < to ? String(characters[from..<to]) : "(konec)"
        }
        return "na pozici \(index): „\(window(left))" + "\" vs „\(window(right))\""
    }

    /// Makes the characters that usually cause a rejection visible.
    private static func visible(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\n": out += "⏎"
            case "\t": out += "⇥"
            case "\u{00A0}": out += "␣nbsp"
            case "\u{202F}": out += "␣nnbsp"
            case "\u{00AD}": out += "␣shy"
            case "\u{200B}": out += "␣zwsp"
            case "\u{FEFF}": out += "␣bom"
            default: out.append(character)
            }
        }
        return out
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
