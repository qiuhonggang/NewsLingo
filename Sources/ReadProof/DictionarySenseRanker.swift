import Foundation
import NaturalLanguage

actor DictionarySenseRanker {
    static let shared = DictionarySenseRanker()

    private lazy var sentenceModel = NLEmbedding.sentenceEmbedding(for: .english)
    private lazy var wordModel = NLEmbedding.wordEmbedding(for: .english)

    private static let stopWords: Set<String> = [
        "about", "above", "after", "again", "also", "although", "always", "another", "any", "around",
        "because", "been", "before", "being", "both", "but", "can", "catch", "could", "did", "does", "done",
        "during", "each", "either", "etc", "every", "for", "from", "had", "has", "have", "having", "her",
        "here", "him", "his", "how", "its", "just", "make", "may", "more", "most", "much", "must", "not",
        "off", "one", "only", "other", "out", "over", "own", "per", "same", "should", "some", "someone",
        "run", "something", "sth", "such", "than", "that", "the", "their", "them", "then", "there", "these",
        "they", "thing", "this", "those", "through", "under", "until", "upon", "very", "was", "well",
        "were", "what", "when", "where", "whether", "which", "while", "who", "will", "with", "would", "you", "your"
    ]

    // A sentence needs multiple topic cues before one domain term can help a sense.
    private static let topicVocabulary: [Set<String>] = [
        ["ai", "algorithm", "application", "circuit", "compute", "computer", "computing", "data", "device",
         "digital", "electronic", "electronics", "microchip", "phone", "processor", "program", "semiconductor", "silicon", "software"],
        ["camera", "fashion", "photo", "photograph", "photographer", "photographic", "photography", "pose", "studio"],
        ["afternoon", "appointment", "available", "busy", "committed", "evening", "free", "meet", "meeting", "morning", "schedule"],
        ["accessible", "download", "install", "obtain", "obtainable", "release", "software"],
        ["battery", "cable", "capacitor", "current", "discharge", "electric", "electrical", "electricity", "power", "volt"],
        ["locomotive", "passenger", "rail", "railway", "station", "subway", "train", "transport"]
    ]

    func preferredSense(in definition: DictionaryDefinition?, context: DictionaryContext) -> Int? {
        guard let definition, definition.senses.count > 1, !Task.isCancelled else { return nil }
        let all = Array(definition.senses.indices)
        let samePartOfSpeech = all.filter {
            context.partOfSpeech != nil && definition.senses[$0].partOfSpeech == context.partOfSpeech
        }
        let candidates = samePartOfSpeech.isEmpty ? all : all.filter {
            definition.senses[$0].partOfSpeech == nil || samePartOfSpeech.contains($0)
        }
        guard candidates.count > 1 else { return candidates.first }
        let sentence = context.maskedSentence.replacing(#/(?i)\bfor free\b/#, with: "at no cost")
        let cues = Self.keywords(in: sentence, excluding: context.excludedTerms)
        guard !cues.isEmpty else { return nil }

        let topics = Self.topicVocabulary.filter { cues.intersection($0).count >= 2 }
        let contextVector = normalized(sentenceModel?.vector(for: sentence))
        var cachedWords: [String: [Double]] = [:]
        func vectors(_ words: Set<String>) -> [[Double]] {
            words.sorted().compactMap { word in
                if let cached = cachedWords[word] { return cached.isEmpty ? nil : cached }
                let vector = normalized(wordModel?.vector(for: word))
                cachedWords[word] = vector ?? []
                return vector
            }
        }
        let cueVectors = vectors(cues)
        var scores: [(index: Int, score: Double)] = []
        for index in candidates {
            guard !Task.isCancelled else { return nil }
            let sense = definition.senses[index]
            func sampleScore(_ text: String, words: Set<String>, overlapWeight: Double) -> Double {
                let overlap = Double(min(2, cues.intersection(words).count))
                let wordScore = relatedness(from: cueVectors, to: vectors(words))
                let sentenceScore = similarity(contextVector, normalized(sentenceModel?.vector(for: String(text.prefix(300)))))
                return 0.36 * sentenceScore + 0.49 * wordScore + overlapWeight * overlap
            }
            let glossText = sense.clues.first ?? ""
            let glossWords = Self.keywords(in: glossText, excluding: context.excludedTerms)
            let gloss = sampleScore(glossText, words: glossWords, overlapWeight: 0.14)
            var example = 0.0
            var exampleWords = Set<String>()
            for text in sense.clues.dropFirst().prefix(5) {
                let words = Self.keywords(in: text, excluding: context.excludedTerms)
                example = max(example, sampleScore(text, words: words, overlapWeight: 0.08))
                exampleWords.formUnion(words)
            }
            let topicScore = topics.map { topic in
                if !glossWords.isDisjoint(with: topic) { return 0.18 }
                return exampleWords.isDisjoint(with: topic) ? 0.0 : 0.12
            }.max() ?? 0
            let score = gloss + 0.40 * max(0, example - gloss) + topicScore
            scores.append((index, score))
        }

        scores.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        guard let best = scores.first, best.score >= 0.29,
              best.score - scores[1].score >= 0.05 else { return nil }
        return best.index
    }

    private static func keywords(in text: String, excluding excluded: Set<String>) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var words = Set<String>()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, range in
            let word = (tag?.rawValue ?? String(text[range])).lowercased()
            if (word.count >= 3 || word == "ai"), word.allSatisfy({ $0.isASCII && $0.isLetter }),
               !excluded.contains(word), !stopWords.contains(word) {
                words.insert(word)
            }
            return words.count < 16
        }
        return words
    }

    private func relatedness(from cues: [[Double]], to words: [[Double]]) -> Double {
        let scores = cues.map { cue in words.map { similarity(cue, $0) }.max() ?? 0 }
        let best = scores.sorted(by: >).prefix(2)
        return best.isEmpty ? 0 : best.reduce(0, +) / Double(best.count)
    }

    private func normalized(_ vector: [Double]?) -> [Double]? {
        guard let vector else { return nil }
        let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return length > 0 ? vector.map { $0 / length } : nil
    }

    private func similarity(_ lhs: [Double]?, _ rhs: [Double]?) -> Double {
        guard let lhs, let rhs, lhs.count == rhs.count else { return 0 }
        return max(0, zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 })
    }
}
