import CoreMedia
import Foundation
import NaturalLanguage
import SoapcapCore
import Speech

/// Cuts a transcriber result into `Segment`s the way `yap` does (its
/// AttributedString helpers, CC0): split where speech pauses for longer than
/// `gap`, then into sentences, then into pieces of about `maxLength`
/// characters. SoapcapCore's echo de-duplication was tuned on segments of
/// this size, so the numbers are yap's defaults.
public enum Segmenter {
    public static let gap: TimeInterval = 1.5
    public static let maxLength = 40

    /// Segments are numbered from `firstID`, in order.
    public static func segments(in text: AttributedString, speaker: String, firstID: Int = 1,
                                gap: TimeInterval = gap, maxLength: Int = maxLength) -> [Segment] {
        var out: [Segment] = []
        for chunk in text.splitAtTimeGaps(threshold: gap) {
            for piece in chunk.timedSentences(maxLength: maxLength) {
                let words = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !words.isEmpty else { continue }
                out.append(Segment(speaker: speaker, start: milliseconds(piece.range.start.seconds),
                                   end: milliseconds(piece.range.end.seconds),
                                   id: firstID + out.count, text: words))
            }
        }
        return out
    }

    private static func milliseconds(_ t: TimeInterval) -> Double { (t * 1000).rounded() / 1000 }
}

extension AttributedString {
    private func isBlank(_ range: Range<AttributedString.Index>) -> Bool {
        String(self[range].characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pieces of this string, cut wherever two consecutive timed runs are
    /// more than `threshold` seconds apart.
    func splitAtTimeGaps(threshold: TimeInterval) -> [AttributedString] {
        var cuts: [AttributedString.Index] = []
        var previousEnd: TimeInterval?
        for run in runs {
            guard let time = run.audioTimeRange, !isBlank(run.range) else { continue }
            if let previousEnd, time.start.seconds - previousEnd > threshold { cuts.append(run.range.lowerBound) }
            previousEnd = time.end.seconds
        }
        var pieces: [AttributedString] = []
        var start = startIndex
        for cut in cuts + [endIndex] where start < cut {
            pieces.append(AttributedString(self[start..<cut]))
            start = cut
        }
        return pieces
    }

    /// Sentences with the time they span; a sentence longer than `maxLength`
    /// characters is broken at word boundaries into pieces of about that length. Untimed text is dropped.
    func timedSentences(maxLength: Int) -> [(text: String, range: CMTimeRange)] {
        let string = String(characters)
        func tokens(_ unit: NLTokenUnit, in range: Range<String.Index>) -> [Range<AttributedString.Index>] {
            let tokenizer = NLTokenizer(unit: unit)
            tokenizer.string = string
            return tokenizer.tokens(for: range).compactMap { r in
                guard let a = AttributedString.Index(r.lowerBound, within: self),
                      let b = AttributedString.Index(r.upperBound, within: self) else { return nil }
                return a..<b
            }
        }
        let stringSentences: [Range<String.Index>] = {
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = string
            return tokenizer.tokens(for: string.startIndex..<string.endIndex)
        }()

        var ranges: [Range<AttributedString.Index>] = []
        for stringRange in stringSentences {
            guard let a = AttributedString.Index(stringRange.lowerBound, within: self),
                  let b = AttributedString.Index(stringRange.upperBound, within: self) else { continue }
            let sentence = a..<b
            var words = tokens(.word, in: stringRange)
            guard self[sentence].characters.count > maxLength, !words.isEmpty else {
                ranges.append(sentence); continue
            }
            // Stretch the first and last word to take the sentence's edges
            // (leading quote, closing punctuation) with them.
            words[0] = sentence.lowerBound..<words[0].upperBound
            words[words.count - 1] = words[words.count - 1].lowerBound..<sentence.upperBound
            var parts: [Range<AttributedString.Index>] = []
            for word in words {
                if let last = parts.last,
                   self[last].characters.count + self[word].characters.count <= maxLength {
                    parts[parts.count - 1] = last.lowerBound..<word.upperBound
                } else {
                    parts.append(word)
                }
            }
            ranges += parts
        }

        return ranges.compactMap { range in
            let times = self[range].runs.filter { !isBlank($0.range) }.compactMap(\.audioTimeRange)
            guard let first = times.first, let last = times.last else { return nil }
            return (String(self[range].characters), CMTimeRange(start: first.start, end: last.end))
        }
    }
}
