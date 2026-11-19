import CoreServices
import Foundation
import NaturalLanguage

enum DictionaryPartOfSpeech: String, Sendable {
    case noun = "n."
    case verb = "v."
    case adjective = "adj."
    case adverb = "adv."
    case pronoun = "pron."
    case preposition = "prep."
    case conjunction = "conj."
    case determiner = "det."
    case interjection = "interj."

    init?(tag: NLTag?) {
        switch tag {
        case .noun: self = .noun
        case .verb: self = .verb
        case .adjective: self = .adjective
        case .adverb: self = .adverb
        case .pronoun: self = .pronoun
        case .preposition: self = .preposition
        case .conjunction: self = .conjunction
        case .determiner: self = .determiner
        case .interjection: self = .interjection
        default: return nil
        }
    }

    init?(heading: String) {
        switch heading.split(separator: " ").last {
        case "noun": self = .noun
        case "verb": self = .verb
        case "adjective": self = .adjective
        case "adverb": self = .adverb
        case "pronoun": self = .pronoun
        case "preposition": self = .preposition
        case "conjunction": self = .conjunction
        case "determiner": self = .determiner
        case "interjection", "exclamation": self = .interjection
        default: return nil
        }
    }
}

struct DictionarySense: Sendable {
    let heading: String?
    let partOfSpeech: DictionaryPartOfSpeech?
    let grammar: String?
    let meanings: [DictionaryMeaning]
    let examples: [DictionaryExample]
    let clues: [String]
}

struct DictionaryMeaning: Sendable {
    let usage: String?
    let text: String
    let annotation: String?
}

struct DictionaryExample: Sendable {
    let text: String
    let translation: String?
}

struct DictionaryDefinition: Sendable {
    struct Note: Sendable {
        let title: String
        let lines: [String]
    }

    let pronunciation: String?
    let senses: [DictionarySense]
    let notes: [Note]

    private static let senseMarker = #/[①-⑳㉑-㉟㊱-㊿]/#
    private static let wordNetHeading = #/^[0-9]+\. (n\.|v\.|adj\.|adv\.) /#
    private static let wordNetExamples = #/;\s+((?:"[^"]*"\s*;?\s*)+)$/#
    private static let systemHeader = #/^[^|\n]+\s*\|\s*([^|\n]+)\|\s*/#
    private static let letteredHeading = #/[A-Z]\.\s+((?:[a-z][a-z'-]*\s+){0,2}?(?:adjective|adverb|noun|verb|pronoun|preposition|conjunction|determiner|exclamation|interjection))\b/#
    private static let initialHeading = #/^((?:(?:intransitive|transitive|auxiliary|modal|phrasal|plural)\s+)?(?:adjective|adverb|noun|verb|pronoun|preposition|conjunction|determiner|exclamation|interjection))\b/#
    private static let noteHeading = #/(?:PHRASAL VERBS|IDIOMS|DERIVATIVES|COMPOUNDS|ORIGIN)(?=\s)/#

    static func wordNet(_ raw: String) -> Self {
        let senses = raw.components(separatedBy: "\n\n").compactMap { entry -> DictionarySense? in
            guard let marker = entry.prefixMatch(of: wordNetHeading) else { return nil }
            let text = String(entry[marker.range.upperBound...]).dictionaryTrimmed
            let heading = String(marker.1)
            let suffix = text.firstMatch(of: wordNetExamples)
            let meaning = suffix.map { String(text[..<$0.range.lowerBound]) } ?? text
            let examples = suffix?.1.matches(of: #/"([^"]*)"/#).map { DictionaryExample(text: String($0.1), translation: nil) } ?? []
            return DictionarySense(heading: heading, partOfSpeech: DictionaryPartOfSpeech(rawValue: heading), grammar: nil,
                                   meanings: [DictionaryMeaning(usage: nil, text: meaning, annotation: nil)], examples: examples,
                                   clues: [meaning] + examples.map(\.text))
        }
        return Self(pronunciation: nil, senses: senses, notes: [])
    }

    static func system(_ raw: String) -> Self {
        let raw = raw.dictionaryTrimmed
        let header = raw.prefixMatch(of: systemHeader)
        let pronunciation = header.map { String($0.1).dictionaryTrimmed }
        let contents = String(raw[(header?.range.upperBound ?? raw.startIndex)...])
        let noteHeaders = contents.matches(of: noteHeading).filter { contents.hasHeadingBoundary(at: $0.range.lowerBound) }
        let main = String(contents[..<(noteHeaders.first?.range.lowerBound ?? contents.endIndex)]).dictionaryTrimmed
        let notes = noteHeaders.indices.map { index in
            let marker = noteHeaders[index]
            let end = index + 1 < noteHeaders.count ? noteHeaders[index + 1].range.lowerBound : contents.endIndex
            let lines = contents[marker.range.upperBound..<end]
                .split(whereSeparator: { $0 == "▸" || $0.isNewline })
                .map { String($0).dictionaryTrimmed }.filter { !$0.isEmpty }
            return Note(title: String(marker.output), lines: lines)
        }

        let sections = main.matches(of: letteredHeading).filter { main.hasHeadingBoundary(at: $0.range.lowerBound) }
        var senses: [DictionarySense] = []
        let introductory = String(main[..<(sections.first?.range.lowerBound ?? main.endIndex)]).dictionaryTrimmed
        if !introductory.isEmpty {
            let heading = introductory.prefixMatch(of: initialHeading)
            let text = String(introductory[(heading?.range.upperBound ?? introductory.startIndex)...])
            senses += systemSection(text, heading: heading.map { String($0.1) })
        }
        for index in sections.indices {
            let marker = sections[index]
            let end = index + 1 < sections.count ? sections[index + 1].range.lowerBound : main.endIndex
            senses += systemSection(String(main[marker.range.upperBound..<end]), heading: String(marker.1))
        }
        return Self(pronunciation: pronunciation,
                    senses: senses.isEmpty && notes.isEmpty ? [systemSense(raw, heading: nil, grammar: nil)] : senses,
                    notes: notes)
    }

    private static func systemSection(_ text: String, heading: String?) -> [DictionarySense] {
        let markers = text.matches(of: senseMarker).map(\.range)
        guard let first = markers.first else {
            return text.dictionaryTrimmed.isEmpty ? [] : [systemSense(text, heading: heading, grammar: nil)]
        }
        let prefix = String(text[..<first.lowerBound]).dictionaryTrimmed
        let hasDefinition = prefix.containsHan || prefix.contains("▸")
        let grammar = prefix.isEmpty || hasDefinition ? nil : prefix
        var senses = hasDefinition ? [systemSense(prefix, heading: heading, grammar: nil)] : []
        for index in markers.indices {
            let end = index + 1 < markers.count ? markers[index + 1].lowerBound : text.endIndex
            let chunk = String(text[markers[index].upperBound..<end]).dictionaryTrimmed
            if !chunk.isEmpty { senses.append(systemSense(chunk, heading: heading, grammar: grammar)) }
        }
        return senses
    }

    private static func systemSense(_ text: String, heading: String?, grammar: String?) -> DictionarySense {
        let chunks = text.components(separatedBy: "▸").map(\.dictionaryTrimmed)
        let meanings = systemMeanings(chunks[0])
        let examples = chunks.dropFirst().filter { !$0.isEmpty }.map { chunk in
            let (before, translated) = splitBilingual(chunk)
            let original = before?.replacing(#/;$/#, with: "").dictionaryTrimmed
            return DictionaryExample(text: original ?? translated, translation: before == nil ? nil : translated)
        }
        var clues = chunks.map { splitBilingual($0).0 ?? $0 }.filter { !$0.isEmpty }
        let qualifiers = text.matches(of: #/[\(‹«]([A-Za-z][A-Za-z ,.'’/–-]+)[\)›»]/#)
            .map { String($0.1) }
        if !qualifiers.isEmpty {
            clues.insert(qualifiers.joined(separator: " "), at: 0)
        }
        return DictionarySense(heading: heading, partOfSpeech: heading.flatMap(DictionaryPartOfSpeech.init(heading:)),
                               grammar: grammar, meanings: meanings, examples: examples, clues: clues)
    }

    private static func systemMeanings(_ text: String) -> [DictionaryMeaning] {
        guard !text.isEmpty else { return [] }
        guard text.containsHan else { return [DictionaryMeaning(usage: nil, text: text, annotation: nil)] }
        var rows: [String] = []
        let chunks = text.components(separatedBy: ";")
        var pending = chunks[0]
        for chunk in chunks.dropFirst() {
            if pending.containsHan, chunk.containsHan, balancedBrackets(in: pending) {
                rows.append(pending)
                pending = chunk
            } else {
                pending += ";" + chunk
            }
        }
        rows.append(pending)
        return rows.map { row in
            let (usage, meaning) = splitBilingual(row)
            if let lastHan = meaning.lastIndex(where: \.isDictionaryHan),
               let space = meaning[meaning.index(after: lastHan)...].firstIndex(where: \.isWhitespace) {
                let detail = String(meaning[space...]).dictionaryTrimmed
                if !detail.isEmpty {
                    return DictionaryMeaning(usage: usage, text: String(meaning[..<space]), annotation: detail)
                }
            }
            return DictionaryMeaning(usage: usage, text: meaning, annotation: nil)
        }
    }

    private static func splitBilingual(_ text: String) -> (String?, String) {
        guard var boundary = text.firstIndex(where: \.isDictionaryHan) else { return (nil, text) }
        while boundary > text.startIndex, "[(（【「『〈《…".contains(text[text.index(before: boundary)]) {
            boundary = text.index(before: boundary)
        }
        // A translated phrase can start with a quantity immediately followed by Chinese.
        if let number = text[..<boundary].firstMatch(of: #/(?:^|\s)([0-9][0-9,.]*(?:[%％°]|:[0-9]{2})?)$/#) {
            boundary = number.1.startIndex
        }
        let prefix = String(text[..<boundary]).dictionaryTrimmed
        return (prefix.isEmpty ? nil : prefix, String(text[boundary...]).dictionaryTrimmed)
    }

    private static func balancedBrackets(in text: String) -> Bool {
        var depth = 0
        for character in text {
            if "([（［‹«".contains(character) { depth += 1 }
            if ")]）］›»".contains(character) { depth -= 1 }
        }
        return depth <= 0
    }
}

struct DictionaryContext: Sendable {
    let maskedSentence: String
    let excludedTerms: Set<String>
    let partOfSpeech: DictionaryPartOfSpeech?

    init?(text: String, selection: Range<String.Index>, word: String, lemma: String, tag: NLTag?) {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        guard let sentence = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .first(where: { $0.contains(selection.lowerBound) && selection.upperBound <= $0.upperBound }) else { return nil }
        let left = text[sentence.lowerBound..<selection.lowerBound].suffix(220)
        let right = text[selection.upperBound..<sentence.upperBound].prefix(220)
        maskedSentence = "\(left) \(right)"
        excludedTerms = Set(ArticleText.words(word + " " + lemma).map { $0.lowercased() })
        partOfSpeech = DictionaryPartOfSpeech(tag: tag)
    }
}

enum SystemDictionary {
    struct Entry {
        let english: DictionaryDefinition?
        let englishSource: String
        let chinese: DictionaryDefinition?
        let phrase: String?
        let context: DictionaryContext?
    }

    static let offlineSource = "Open English WordNet 2025+"

    static func lookup(_ word: String, in text: String? = nil, at selection: NSRange? = nil) -> Entry {
        var lemma = word
        var phrase: String?
        var lookupContext: DictionaryContext?
        if let text, let selection, let selected = Range(selection, in: text) {
            let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
            tagger.string = text
            tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
            let isWord = !word.contains(where: \.isWhitespace)
            if isWord {
                lemma = tagger.tag(at: selected.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? word
                let normalized = (text as NSString).replacingCharacters(in: selection, with: lemma)
                let match = DCSGetTermRangeInString(nil, normalized as CFString, selection.location)
                if match.location >= 0, match.length <= 70, match.length > (lemma as NSString).length,
                   match.location <= selection.location, match.location + match.length <= (normalized as NSString).length {
                    phrase = (normalized as NSString).substring(with: NSRange(location: match.location, length: match.length))
                }
            }
            let lexicalClass = isWord && phrase == nil ? tagger.tag(at: selected.lowerBound, unit: .word, scheme: .lexicalClass).0 : nil
            lookupContext = DictionaryContext(text: text, selection: selected, word: word, lemma: lemma, tag: lexicalClass)
        }

        let phraseEntry = phrase.flatMap(systemDefinition)
        let local = phraseEntry ?? systemDefinition(lemma) ?? (lemma != word ? systemDefinition(word) : nil)
        let hasChinese = local?.unicodeScalars.contains(where: \.isDictionaryHan) ?? false
        let system = local.map(DictionaryDefinition.system)
        if !hasChinese, let system, system.senses.count > 1 {
            return Entry(english: system, englishSource: "macOS 词典", chinese: nil, phrase: phrase, context: lookupContext)
        }

        let crossReference = phraseEntry?.split(separator: "=", maxSplits: 1).dropFirst().first.map { String($0).dictionaryTrimmed }
        let english = [phrase, crossReference, lemma, word].compactMap { $0 }
            .lazy.compactMap { WordNet.shared.definition(for: $0) }.first.map(DictionaryDefinition.wordNet)
        let offline = english.flatMap { $0.senses.isEmpty ? nil : $0 }
        return Entry(english: offline ?? (hasChinese ? nil : system),
                     englishSource: offline == nil ? "macOS 词典" : offlineSource,
                     chinese: hasChinese ? system : nil, phrase: phrase, context: lookupContext)
    }

    private static func systemDefinition(_ term: String) -> String? {
        guard let definition = DCSCopyTextDefinition(nil, term as CFString, CFRange(location: 0, length: (term as NSString).length))?
            .takeRetainedValue() as String?,
              let first = definition.dictionaryTrimmed.unicodeScalars.first, !first.isDictionaryHan else { return nil }
        return definition
    }
}

private extension String {
    var dictionaryTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var containsHan: Bool { contains(where: \.isDictionaryHan) }

    func hasHeadingBoundary(at index: Index) -> Bool {
        guard index > startIndex else { return true }
        let previous = self[self.index(before: index)]
        return !previous.isASCII || (!previous.isLetter && !previous.isNumber)
    }
}

private extension Character {
    var isDictionaryHan: Bool { unicodeScalars.contains(where: \.isDictionaryHan) }
}

private extension Unicode.Scalar {
    var isDictionaryHan: Bool { (0x3400...0x9FFF).contains(Int(value)) }
}
