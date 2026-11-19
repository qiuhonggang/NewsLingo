import AppKit
import Foundation

@main
enum Program {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 1 {
            NewsLingoApp.main()
            return
        }
        if arguments[1] == "--validate" && arguments.count == 3 {
            do {
                let article = try ArticleImporter.load(URL(fileURLWithPath: arguments[2]))
                let result = ["title": article.title, "words": "\(article.words)", "questions": "\(article.questions.count)",
                              "mode": article.isGuided ? "comprehension" : "cloze", "fingerprint": article.id,
                              "bilingualParagraphs": "\(article.bilingual?.count ?? 0)",
                              "alignedSentences": "\(article.bilingual?.flatMap(\.sentences).count ?? 0)"]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
                print(String(decoding: data, as: UTF8.self))
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if arguments[1] == "--system-check" {
            let entry = SystemDictionary.lookup("maintenance")
            print("English dictionary: \(entry.english == nil ? "unavailable" : "ok")")
            print("Chinese dictionary: \(entry.chinese == nil ? "use system Look Up" : "ok")")
            exit(entry.english == nil ? 1 : 0)
        }
        // Launch Services and the Xcode test harness may add standard process arguments.
        NewsLingoApp.main()
    }
}
