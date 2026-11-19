import Foundation
import Observation

@Observable
final class Library {
    private(set) var articles: [Article] = []
    private(set) var loadingError: String?
    var message: String?
    private let url: URL
    private var writable = true

    init(directory: URL, seed: Bool = true) {
        url = directory.appendingPathComponent("Library.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                articles = try JSONDecoder().decode([Article].self, from: Data(contentsOf: url))
            } else if seed {
                let bundledURL = Bundle.main.resourceURL?.appendingPathComponent("AI-Skill/Genie-4-B1.jugan")
                let bundled = bundledURL.flatMap { try? ArticleImporter.load($0) }
                articles = [bundled ?? Samples.article]
                try save(articles)
            }
        } catch {
            writable = false
            loadingError = "无法打开学习资料库。请在设置中打开数据文件夹，检查 Library.json 后重新启动。"
        }
    }

    func insert(_ article: Article) throws -> String {
        var next = articles
        if let index = next.firstIndex(where: { $0.id == article.id }) {
            let current = next[index]
            guard article.bilingual != nil else { return current.id }
            var updated = article
            updated.added = current.added
            updated.position = current.paragraphs == article.paragraphs ? current.position : 0
            updated.progress = current.progress
            updated.secondsByDay = current.secondsByDay
            updated.lookedUp = current.lookedUp
            updated.translations = current.translations
            if !current.attempts.isEmpty {
                updated.questions = current.questions
                updated.isGuided = current.isGuided
                updated.attempts = current.attempts
            }
            next[index] = updated
        } else {
            next.insert(article, at: 0)
        }
        try save(next)
        articles = next
        return article.id
    }

    func update(_ id: String, _ change: (inout Article) -> Void) {
        guard writable, let i = articles.firstIndex(where: { $0.id == id }) else { return }
        var next = articles
        change(&next[i])
        do {
            try save(next)
            articles = next
        } catch {
            message = "无法保存学习记录。请检查数据文件夹的写入权限与剩余空间。"
        }
    }

    func remove(_ id: String) {
        let next = articles.filter { $0.id != id }
        do { try save(next); articles = next }
        catch { message = "无法移除此文章。\(error.localizedDescription)" }
    }

    var directory: URL { url.deletingLastPathComponent() }
    func article(_ id: String) -> Article? { articles.first(where: { $0.id == id }) }

    private func save(_ snapshot: [Article]) throws {
        guard writable else { throw ImportFailure("当前资料库无法写入。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["JUGAN_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jugan", isDirectory: true)
    }

    static func day(_ date: Date = .now) -> String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}

enum Samples {
    static var article: Article {
        let paragraphs = [
            "On a warm afternoon, two streets in the same neighborhood can feel like different places. On one street, trees shade the sidewalk and people take their time walking home. On the other, sunlight falls directly on concrete and parked cars. The difference matters most to people who cannot easily avoid the heat, such as outdoor workers, older residents, and children waiting for a bus.",
            "A city that wants cooler streets might begin by counting its trees. But a simple tree count can hide the places where shade is needed most. A park may contain hundreds of trees while the route to a nearby school has almost none. Some planners therefore map shade along everyday routes and compare those maps with the times and places where people actually walk.",
            "Planting a tree is only the first step. Young trees need water, space for their roots, and maintenance for several years. They also take time to grow large enough to cool a sidewalk. Where people need relief right away, a city can put temporary shade at bus stops and use longer-term planting to improve the same route.",
            "The useful question is not how many trees the city planted, but whether people can now make an ordinary trip in greater comfort. If more residents can walk to school, wait for a bus, or reach a shop on a hot day, the project has made a difference that a tree count alone could never show."
        ]
        let questions = [
            Question(kind: "mainIdea", prompt: "What is the main argument of the article?",
                     choices: ["Cities should plant the same number of trees in every neighborhood.", "Cities should measure whether shade helps people on everyday trips.", "Parks are the most effective place to build new sidewalks.", "Temporary shade should replace street trees."], answer: 1,
                     evidence: "The useful question is not how many trees the city planted, but whether people can now make an ordinary trip in greater comfort.", explanation: "文章以日常出行的实际改善衡量项目成效，树木数量只是间接指标。"),
            Question(kind: "detail", prompt: "What does the article suggest for a bus stop that needs immediate relief?",
                     choices: ["Widen the street.", "Move it into a park.", "Wait for young trees to grow.", "Add temporary shade."], answer: 3,
                     evidence: "Where people need relief right away, a city can put temporary shade at bus stops and use longer-term planting to improve the same route.", explanation: "临时遮阳可以马上起效，植树是同一线路的长期措施。"),
            Question(kind: "inference", prompt: "Why might planners prioritize a sunny route to a school even next to a wooded park?",
                     choices: ["A well-shaded park does not necessarily shade the route children take.", "Schools usually have enough space to plant a forest.", "Children generally avoid walking through parks.", "Tree counts are always wrong."], answer: 0,
                     evidence: "A park may contain hundreds of trees while the route to a nearby school has almost none.", explanation: "公园的覆盖率与上学路线的遮阴程度可以相差很大。"),
            Question(kind: "vocabulary", prompt: "What does “relief” mean in the third paragraph?",
                     choices: ["An official map.", "The replacement of a worker.", "A reduction in discomfort.", "The height of a tree."], answer: 2,
                     evidence: "Where people need relief right away, a city can put temporary shade at bus stops and use longer-term planting to improve the same route.", explanation: "此处指用遮阳缓解炎热带来的不适。")
        ]
        var article = Article(title: "A Cooler Walk Home", paragraphs: paragraphs, sourceName: "内置练习", level: "B1",
                              questions: questions, isGuided: true)
        article.isSample = true
        return article
    }
}
