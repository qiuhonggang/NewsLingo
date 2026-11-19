import Foundation
import NaturalLanguage
import SQLite3

final class WordNet {
    static let shared = WordNet()
    private var database: OpaquePointer?

    private init() {
        guard let url = Bundle.main.url(forResource: "WordNet", withExtension: "sqlite3") else { return }
        if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            sqlite3_close(database)
            database = nil
        }
    }

    deinit { sqlite3_close(database) }

    func definition(for word: String) -> String? {
        let term = word.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: " ", with: "_")
        if let exact = entry(term) { return exact }
        if let irregular = query(
            "SELECT lexicon.entry FROM inflections JOIN lexicon ON lexicon.term = inflections.lemma WHERE form = ? ORDER BY inflections.lemma LIMIT 1",
            term
        ) { return irregular }
        guard !term.contains("_") else { return nil }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        if let lemma = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased(),
           let normalized = entry(lemma) { return normalized }
        return nil
    }

    private func entry(_ term: String) -> String? {
        query("SELECT entry FROM lexicon WHERE term = ?", term)
    }

    private func query(_ sql: String, _ key: String) -> String? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW, let result = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: result)
    }
}
