import AppKit
import CryptoKit
import NaturalLanguage
import PDFKit

struct Question: Codable, Hashable {
    let kind: String
    let prompt: String
    let choices: [String]
    let answer: Int
    let evidence: String
    let explanation: String
}

struct Attempt: Codable, Identifiable {
    static let passingPercentage = 80

    var id = UUID()
    let date: Date
    let answers: [Int]
    let correct: Int
    let total: Int
    var percentage: Int { total == 0 ? 0 : Int((Double(correct) * 100 / Double(total)).rounded()) }
    var isPassing: Bool { percentage >= Self.passingPercentage }
}

struct BilingualSentence: Codable, Hashable {
    let en: String
    let zh: String
}

struct BilingualParagraph: Codable, Hashable {
    let en: String
    let zh: String
    let sentences: [BilingualSentence]
}

struct Article: Codable, Identifiable {
    let id: String
    let title: String
    let paragraphs: [String]
    let sourceName: String?
    let sourceURL: URL?
    let published: String?
    let level: String?
    var questions: [Question]
    var isGuided: Bool
    var added: Date
    var isSample = false
    // Existing library files encode reading completion as a value of 1.
    var progress = 0.0
    var position = 0
    var secondsByDay: [String: Int] = [:]
    var lookedUp: [String: Int] = [:]
    var attempts: [Attempt] = []
    var bilingual: [BilingualParagraph]?
    var titleZh: String?
    var sourceArticleTitle: String?
    // Preserve translations cached by older releases in existing libraries.
    var translations: [String: String] = [:]
    var displaySource: String? { isSample ? "内置练习" : sourceName }
    var words: Int { ArticleText.words(paragraphs.joined(separator: " ")).count }
    var readingSeconds: Int { secondsByDay.values.reduce(0, +) }
    var hasCompletedReading: Bool { progress >= 1 }
    var hasPassedAssessment: Bool { attempts.contains(where: \.isPassing) }
    var reviewDate: Date? {
        attempts.last.flatMap { Calendar.current.date(byAdding: .day, value: $0.isPassing ? 3 : 1, to: $0.date) }
    }

    mutating func markReadingComplete() {
        progress = 1
    }

    init(title: String, paragraphs: [String], sourceName: String? = nil, sourceURL: URL? = nil,
         published: String? = nil, level: String? = nil, questions: [Question], isGuided: Bool) {
        self.title = title
        self.paragraphs = paragraphs
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.published = published
        self.level = level
        self.questions = questions
        self.isGuided = isGuided
        added = Date()
        let fingerprint = paragraphs.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        id = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum ArticleText {
    static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let wordPattern = try! NSRegularExpression(pattern: #"[A-Za-z]+(?:[’'-][A-Za-z]+)*"#)

    static func words(_ text: String) -> [String] {
        let original = text as NSString
        return wordPattern.matches(in: text, range: NSRange(location: 0, length: original.length))
            .map { original.substring(with: $0.range) }
    }

    static func sentences(_ paragraph: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.english)
        tokenizer.string = paragraph
        return tokenizer.tokens(for: paragraph.startIndex..<paragraph.endIndex)
            .map { paragraph[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func roundedMinutes(_ seconds: Int) -> String {
        if seconds <= 0 { return "0 分钟" }
        if seconds < 60 { return "不足 1 分钟" }
        return "\(seconds / 60) 分钟"
    }

    static func fallbackQuiz(paragraphs: [String]) -> [Question] {
        let sentences = paragraphs.flatMap(sentences)
        let stop = Set("about after again along among around because before being between could during first found however might other should since their there these those through under until where which while whose would years often people still something another".split(separator: " ").map(String.init))
        var seen = Set<String>()
        let textRanges = sentences.map { sentence in
            wordPattern.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence))
                .compactMap { match -> NSRange? in
                    let token = (sentence as NSString).substring(with: match.range)
                    return token.count >= 5 && token.first?.isLowercase == true && !stop.contains(token.lowercased()) ? match.range : nil
                }
        }
        let pool = zip(sentences, textRanges).flatMap { sentence, ranges in ranges.map { (sentence as NSString).substring(with: $0) } }
        var questions: [Question] = []
        let eligible = sentences.indices.filter { !textRanges[$0].isEmpty && words(sentences[$0]).count >= 7 }
        for (order, index) in eligible.enumerated() {
            guard questions.count < 5 else { break }
            let sentence = sentences[index]
            let ranges = textRanges[index]
            let range = ranges[(order * 3 + ranges.count / 2) % ranges.count]
            let word = (sentence as NSString).substring(with: range)
            guard seen.insert(word.lowercased()).inserted else { continue }
            let inSentence = Set(words(sentence).map { $0.lowercased() })
            let distractors = Set(pool).filter { !inSentence.contains($0.lowercased()) }
                .sorted { (abs($0.count - word.count), $0) < (abs($1.count - word.count), $1) }
            guard distractors.count >= 3 else { continue }
            let offset = (questions.count * 7) % max(1, min(18, distractors.count - 2))
            var choices = Array(distractors.dropFirst(offset).prefix(3))
            let answer = (questions.count + 1) % 4
            choices.insert(word, at: answer)
            questions.append(Question(kind: "cloze", prompt: (sentence as NSString).replacingCharacters(in: range, with: "_____"),
                                      choices: choices, answer: answer, evidence: sentence,
                                      explanation: "原句使用了“\(word)”补全这处语境。"))
        }
        return questions
    }
}

struct ImportFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct LessonPack: Decodable {
    let version: Int
    let title: String
    let titleZh: String?
    let source: Source
    let level: String
    let paragraphs: [String]
    let bilingual: [BilingualParagraph]?
    let questions: [Question]

    struct Source: Decodable {
        let name: String
        let title: String?
        let url: URL
        let published: String
    }

    private enum CodingKeys: String, CodingKey {
        case version, title, titleZh, source, level, paragraphs, questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == 1 || version == 2 else {
            throw ImportFailure("此学习包版本不受支持。请导出 version 为 2 的双语学习包。")
        }
        title = try container.decode(String.self, forKey: .title)
        titleZh = try container.decodeIfPresent(String.self, forKey: .titleZh)
        source = try container.decode(Source.self, forKey: .source)
        level = try container.decode(String.self, forKey: .level)
        questions = try container.decode([Question].self, forKey: .questions)
        if version == 2 {
            let pairs = try container.decode([BilingualParagraph].self, forKey: .paragraphs)
            bilingual = pairs
            paragraphs = pairs.map(\.en)
        } else {
            bilingual = nil
            paragraphs = try container.decode([String].self, forKey: .paragraphs)
        }
    }
}

enum ArticleImporter {
    static let extensions = ["jugan", "json", "md", "markdown", "txt", "pdf", "docx", "rtf"]

    static func load(_ url: URL) throws -> Article {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard extensions.contains(url.pathExtension.lowercased()) else {
            throw ImportFailure("请选择 .jugan、JSON、Markdown、TXT、PDF、DOCX 或 RTF 文件。")
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 20 * 1024 * 1024 else {
            throw ImportFailure("请选择不超过 20 MB 的文件。")
        }
        switch url.pathExtension.lowercased() {
        case "jugan", "json":
            let pack: LessonPack
            do { pack = try JSONDecoder().decode(LessonPack.self, from: Data(contentsOf: url)) }
            catch let error as ImportFailure { throw error }
            catch let error as DecodingError {
                let path: [any CodingKey]
                switch error {
                case .keyNotFound(let key, let context): path = context.codingPath + [key]
                case .valueNotFound(_, let context), .typeMismatch(_, let context), .dataCorrupted(let context):
                    path = context.codingPath
                @unknown default: path = []
                }
                let field = path.map { key in key.intValue.map { "[\($0 + 1)]" } ?? key.stringValue }.joined(separator: ".")
                throw ImportFailure(field.isEmpty ? "无法读取学习包。请检查 JSON 结构。" : "学习包字段 \(field) 缺失或格式不正确。")
            }
            return try validate(pack)
        case "pdf":
            guard let document = PDFDocument(url: url), let body = document.string, !body.isEmpty else {
                throw ImportFailure("此 PDF 没有可提取的文字。请先转为带文字层的 PDF 或 TXT。")
            }
            return try plain(body, title: url.deletingPathExtension().lastPathComponent)
        case "docx", "rtf":
            let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "docx" ? .officeOpenXML : .rtf
            let contents = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
            return try plain(contents.string, title: url.deletingPathExtension().lastPathComponent)
        default:
            let data = try Data(contentsOf: url)
            guard let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw ImportFailure("无法识别文本编码。请另存为 UTF-8 再导入。")
            }
            return try plain(body, title: url.deletingPathExtension().lastPathComponent,
                             markdown: ["md", "markdown"].contains(url.pathExtension.lowercased()))
        }
    }

    static func validate(_ pack: LessonPack) throws -> Article {
        let title = pack.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = pack.paragraphs.map(ArticleText.normalizeWhitespace)
        let paragraphs = pack.version == 1 ? normalized.filter { !$0.isEmpty } : normalized
        guard (1...160).contains(title.count),
              ["A2", "B1", "B2", "C1", "C2"].contains(pack.level),
              ["https", "http"].contains(pack.source.url.scheme?.lowercased() ?? ""),
              let host = pack.source.url.host, !host.isEmpty,
              !pack.source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validDate(pack.source.published) else {
            throw ImportFailure("请提供有效的英文标题、CEFR 难度、来源名称、网页链接和发布日期。")
        }
        let aligned = try pack.bilingual.map(validateBilingual)
        if pack.version == 2 {
            guard let chineseTitle = pack.titleZh?.trimmingCharacters(in: .whitespacesAndNewlines),
                  chineseTitle.count <= 160, hasChinese(chineseTitle),
                  let sourceTitle = pack.source.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  (1...300).contains(sourceTitle.count) else {
                throw ImportFailure("双语学习包需要中文标题和来源文章的原始标题。")
            }
        }
        try checkBody(paragraphs)
        let body = paragraphs.joined(separator: " ")
        guard (4...8).contains(pack.questions.count),
              pack.questions.contains(where: { $0.kind == "mainIdea" }),
              pack.questions.contains(where: { $0.kind == "detail" }),
              pack.questions.contains(where: { $0.kind == "inference" }) else {
            throw ImportFailure("学习包需要 4–8 道题，并包含主旨、细节与推断题。")
        }
        var prompts = Set<String>()
        for (index, question) in pack.questions.enumerated() {
            let options = question.choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let prompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = question.evidence.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard ["mainIdea", "detail", "inference", "vocabulary"].contains(question.kind),
                  (4...300).contains(prompt.count), prompts.insert(prompt.lowercased()).inserted,
                  options.count == 4, Set(options).count == 4,
                  options.allSatisfy({ (1...280).contains($0.count) }), options.indices.contains(question.answer),
                  (18...800).contains(evidence.count), body.contains(evidence),
                  (4...650).contains(question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
                throw ImportFailure("第 \(index + 1) 题需要四个不同选项、一个有效答案、解析及逐字匹配的原文证据。")
            }
        }
        var article = Article(title: title, paragraphs: paragraphs, sourceName: pack.source.name, sourceURL: pack.source.url,
                              published: pack.source.published, level: pack.level, questions: pack.questions, isGuided: true)
        article.bilingual = aligned
        article.titleZh = pack.titleZh?.trimmingCharacters(in: .whitespacesAndNewlines)
        article.sourceArticleTitle = pack.source.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return article
    }

    private static func validateBilingual(_ paragraphs: [BilingualParagraph]) throws -> [BilingualParagraph] {
        guard (1...400).contains(paragraphs.count) else { throw ImportFailure("双语正文段落数超出范围。") }
        let normalize = ArticleText.normalizeWhitespace
        func compactChinese(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        return try paragraphs.enumerated().map { index, paragraph in
            let english = normalize(paragraph.en)
            let chinese = normalize(paragraph.zh)
            let label = "第 \(index + 1) 段"
            guard (1...3500).contains(english.count), (1...4500).contains(chinese.count), hasChinese(chinese),
                  (1...45).contains(paragraph.sentences.count) else {
                throw ImportFailure("\(label)需要英文正文、中文译文和对应句对。")
            }
            let sentences = try paragraph.sentences.enumerated().map { offset, sentence in
                let en = normalize(sentence.en)
                let zh = normalize(sentence.zh)
                guard (1...1600).contains(en.count), (1...1800).contains(zh.count),
                      !ArticleText.words(en).isEmpty, hasChinese(zh) else {
                    throw ImportFailure("\(label)第 \(offset + 1) 个句对的英中文本缺失或无效。")
                }
                return BilingualSentence(en: en, zh: zh)
            }
            guard sentences.map(\.en).joined(separator: " ") == english else {
                throw ImportFailure("\(label)的英文句对与段落正文不一致，请检查顺序、漏句或改写。")
            }
            guard sentences.map({ compactChinese($0.zh) }).joined() == compactChinese(chinese) else {
                throw ImportFailure("\(label)的中文句对与段落译文不一致，请检查顺序或漏句。")
            }
            return BilingualParagraph(en: english, zh: chinese, sentences: sentences)
        }
    }

    private static func hasChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
    }

    static func plain(_ body: String, title: String, markdown: Bool = false) throws -> Article {
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        var articleTitle = title
        if markdown, let i = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[i].hasPrefix("# ") {
            articleTitle = String(lines.remove(at: i).dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if markdown {
            lines = lines.map { line in
                line.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[*_`]{1,3}"#, with: "", options: .regularExpression)
            }
        }
        let hasBlank = lines.dropFirst().dropLast().contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        let raw = hasBlank
            ? lines.joined(separator: "\n").replacingOccurrences(of: #"\n[ \t]*\n+"#, with: "\u{1F}", options: .regularExpression).components(separatedBy: "\u{1F}")
            : lines
        let paragraphs = raw.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }
            .flatMap { paragraph in paragraph.count <= 2400 ? [paragraph] : ArticleText.sentences(paragraph) }
        try checkBody(paragraphs)
        let questions = ArticleText.fallbackQuiz(paragraphs: paragraphs)
        guard questions.count >= 3 else {
            throw ImportFailure("可用于练习的完整英文句子不足。请导入正文更完整的文章，或使用带理解题的学习包。")
        }
        return Article(title: String(articleTitle.prefix(160)), paragraphs: paragraphs, questions: questions, isGuided: false)
    }

    private static func checkBody(_ paragraphs: [String]) throws {
        let text = paragraphs.joined(separator: " ")
        guard text.count <= 100_000, paragraphs.count <= 400, paragraphs.allSatisfy({ $0.count <= 3500 }) else {
            throw ImportFailure("正文过长。请按主题拆分为更短的学习材料。")
        }
        let count = ArticleText.words(text).count
        guard count >= 100, paragraphs.flatMap(ArticleText.sentences).count >= 5 else {
            throw ImportFailure("正文至少需要 100 个英文单词和 5 个完整句子。")
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(6000)))
        guard recognizer.dominantLanguage == .english else {
            throw ImportFailure("正文主要语言应为英语。请使用英文正文或英文导读。")
        }
    }

    private static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value && date <= Date()
    }
}
