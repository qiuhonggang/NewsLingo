import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpen: (([URL]) -> Void)?
    private var pending: [URL] = []

    #if DEBUG
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["NEWSLINGO_QA_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpen { onOpen(urls) } else { pending.append(contentsOf: urls) }
    }
    func connect(_ callback: @escaping ([URL]) -> Void) {
        onOpen = callback
        if !pending.isEmpty {
            let urls = pending
            pending.removeAll()
            callback(urls)
        }
    }
}

struct NewsLingoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library = Library(directory: Library.defaultDirectory)
    @State private var destination: Destination? = .library
    @State private var selectedArticle: String?
    @State private var managesFiles = false
    @State private var search = ""
    @State private var statusFilter = ArticleStatusFilter.all
    @State private var dateFilter = ArticleDateFilter.today
    @State private var libraryDate = Date.now
    @State private var removesArticle: Article?
    @AppStorage("ReaderFontSize") private var readerFont = 20.0

    var body: some Scene {
        Window("NewsLingo", id: "main") {
            root
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    if selectedArticle == nil { reconcileSelection() }
                    delegate.connect(importFiles)
                    if let error = library.loadingError { library.message = error }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入文章…") { managesFiles = true }
                    .keyboardShortcut("o")
            }
            CommandMenu("阅读") {
                Button("学习资料库") { destination = .library }
                    .keyboardShortcut("1")
                Button("待复习") { destination = .review }
                    .keyboardShortcut("2")
                Button("学习统计") { destination = .statistics }
                    .keyboardShortcut("3")
                Divider()
                Button("放大阅读字体") { readerFont = min(28, readerFont + 1) }
                    .keyboardShortcut("+")
                Button("缩小阅读字体") { readerFont = max(15, readerFont - 1) }
                    .keyboardShortcut("-")
                Button("还原阅读字体") { readerFont = 20 }
                    .keyboardShortcut("0")
            }
        }

        Settings {
            AppSettings(directory: library.directory)
        }
    }

    private var selected: Article? { selectedArticle.flatMap(library.article) }

    private var root: some View {
        NavigationSplitView {
            List(selection: Binding(get: { destination }, set: { if let value = $0 { destination = value } })) {
                HStack(spacing: 7) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().scaledToFit().frame(width: 35, height: 35)
                        .accessibilityHidden(true)
                    Text("NewsLingo")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudyPalette.ink)
                }
                .padding(.vertical, 5)
                .accessibilityAddTraits(.isHeader)
                .selectionDisabled()
                Section("学习") {
                    Label("资料库", systemImage: "square.stack").tag(Destination.library)
                    Label("待复习", systemImage: "clock.arrow.circlepath").tag(Destination.review)
                    Label("学习统计", systemImage: "chart.bar.xaxis").tag(Destination.statistics)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 148, ideal: 170, max: 215)
            .accessibilityIdentifier("navigation")
        } content: {
            if destination == .statistics {
                Color.clear.navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0).accessibilityHidden(true)
            } else {
                articleList
                    .navigationSplitViewColumnWidth(min: 176, ideal: 248, max: 330)
            }
        } detail: {
            Group {
                if destination == .statistics {
                    StatisticsView(articles: library.articles, openArticle: revealArticle)
                } else if let article = selected {
                    ReaderView(library: library, article: article, readerFont: readerFont)
                        .id(article.id)
                } else {
                    if destination == .review {
                        ContentUnavailableView("暂无待复习文章", systemImage: "checkmark.circle",
                                               description: Text("完成测验后，NewsLingo 会根据成绩安排复习。"))
                    } else if !search.isEmpty || statusFilter != .all {
                        ContentUnavailableView("没有匹配的文章", systemImage: "line.3.horizontal.decrease")
                    } else if dateFilter == .today && !library.articles.isEmpty {
                        ContentUnavailableView {
                            Label("今天还没有导入文章", systemImage: "calendar")
                        } actions: {
                            Button("查看全部日期") { dateFilter = .all }.buttonStyle(.bordered)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("开始阅读", systemImage: "book")
                        } description: {
                            Text("导入英文文章或 AI 生成的学习包。")
                        } actions: {
                            Button("导入文章…") { managesFiles = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .background(StudyPalette.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { managesFiles = true } label: {
                    Label("导入文章", systemImage: "square.and.arrow.down")
                }
                .help("导入文章（⌘O）")
                .accessibilityIdentifier("importArticles")
            }
        }
        .fileImporter(isPresented: $managesFiles, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            importFiles(files)
            return true
        }
        .alert("NewsLingo", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(library.message ?? "")
        }
        .confirmationDialog("移除文章", isPresented: Binding(get: { removesArticle != nil }, set: { if !$0 { removesArticle = nil } }),
                            titleVisibility: .visible, presenting: removesArticle) { article in
            Button("移除文章及学习记录", role: .destructive) {
                library.remove(article.id)
                reconcileSelection()
            }
        } message: { article in
            Text("“\(article.title)”及其测验和阅读记录将从 NewsLingo 中移除。")
        }
        .onChange(of: destination) { _, _ in
            search = ""
            reconcileSelection()
        }
        .onChange(of: search) { _, _ in reconcileSelection() }
        .onChange(of: statusFilter) { _, _ in reconcileSelection() }
        .onChange(of: dateFilter) { _, _ in reconcileSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in libraryDate = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in libraryDate = .now }
    }

    private var articleList: some View {
        let articles = filtered
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center) {
                    Text(destination == .review ? "待复习" : "资料库")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(StudyPalette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(articles.count) 篇")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(StudyPalette.muted)
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(StudyPalette.muted)
                        .accessibilityHidden(true)
                    TextField("搜索文章", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("searchArticles")
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(StudyPalette.muted)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .studyPanel(cornerRadius: 9)

                if destination == .library {
                    libraryFilters
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if articles.isEmpty {
                VStack(spacing: 8) {
                    let hasFilter = !search.isEmpty || (destination == .library && statusFilter != .all)
                    let todayIsEmpty = destination == .library && dateFilter == .today && !library.articles.isEmpty
                    StudyGlyph(symbol: hasFilter ? "magnifyingglass" : (todayIsEmpty ? "calendar" : "tray"), size: 38)
                    Text(hasFilter ? "没有匹配的文章" : (todayIsEmpty ? "今天还没有导入文章" : "暂无文章"))
                        .font(.callout).foregroundStyle(StudyPalette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(articles) { article in
                                let isSelected = selectedArticle == article.id
                                Button {
                                    selectedArticle = article.id
                                } label: {
                                    ArticleRow(article: article, selected: isSelected)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                                .help(article.title)
                                .contextMenu {
                                    Button("移除文章…", role: .destructive) { removesArticle = article }
                                }
                                .id(article.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                    .onChange(of: selectedArticle) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
                .accessibilityIdentifier("articleList")
            }
        }
        .background(StudyPalette.library)
    }

    private var libraryFilters: some View {
        VStack(spacing: 0) {
            filterMenu("导入日期", symbol: "calendar", selection: $dateFilter)
                .accessibilityIdentifier("articleDateFilter")
            Rectangle().fill(StudyPalette.border).frame(height: 1).padding(.horizontal, 9)
                .accessibilityHidden(true)
            filterMenu("学习状态", symbol: "line.3.horizontal.decrease", selection: $statusFilter)
                .accessibilityIdentifier("articleStatusFilter")
        }
        .studyPanel(cornerRadius: 9)
    }

    private func filterMenu<Filter: RawRepresentable & CaseIterable & Hashable>(
        _ title: String, symbol: String, selection: Binding<Filter>
    ) -> some View where Filter.RawValue == String {
        Menu {
            Picker(title, selection: selection) {
                ForEach(Array(Filter.allCases), id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(selection.wrappedValue.rawValue, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .frame(minHeight: 30)
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(StudyPalette.muted)
                .padding(.trailing, 11)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(title)
        .accessibilityValue(selection.wrappedValue.rawValue)
    }

    private var filtered: [Article] {
        let calendar = Calendar.autoupdatingCurrent
        let candidates = destination == .review
            ? library.articles.filter { $0.reviewDate.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: libraryDate) } ?? false }
                .sorted { ($0.reviewDate ?? .distantFuture) < ($1.reviewDate ?? .distantFuture) }
            : library.articles.filter {
                dateFilter.includes($0.added, on: libraryDate, calendar: calendar) && statusFilter.matches($0)
            }.sorted { $0.added > $1.added }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? candidates : candidates.filter {
            $0.title.localizedStandardContains(query) || ($0.displaySource?.localizedStandardContains(query) ?? false)
        }
    }

    private func reconcileSelection() {
        guard destination != .statistics else { return }
        if !filtered.contains(where: { $0.id == selectedArticle }) { selectedArticle = filtered.first?.id }
    }

    private func revealArticle(_ id: String) {
        guard let article = library.article(id) else { return }
        destination = .library
        search = ""
        statusFilter = .all
        if !dateFilter.includes(article.added, on: libraryDate, calendar: .autoupdatingCurrent) {
            dateFilter = .all
        }
        selectedArticle = article.id
    }

    private func importFiles(_ urls: [URL]) {
        var last: String?
        var failures: [String] = []
        for url in urls {
            do { last = try library.insert(ArticleImporter.load(url)) }
            catch { failures.append("\(url.lastPathComponent)\n\(error.localizedDescription)") }
        }
        if let last {
            revealArticle(last)
            NSApp.activate(ignoringOtherApps: true)
        }
        if !failures.isEmpty { library.message = failures.joined(separator: "\n\n") }
    }

    static let importTypes: [UTType] = ArticleImporter.extensions.compactMap { UTType(filenameExtension: $0) }
}

enum Destination: Hashable { case library, review, statistics }

private enum ArticleDateFilter: String, CaseIterable {
    case today = "今日导入"
    case all = "全部日期"

    func includes(_ date: Date, on today: Date, calendar: Calendar) -> Bool {
        self == .all || calendar.isDate(date, inSameDayAs: today)
    }
}

private enum ArticleStatusFilter: String, CaseIterable {
    case all = "全部状态"
    case unfinished = "未读完"
    case awaitingPass = "已读完 · 待通过"
    case passed = "测评已通过"

    func matches(_ article: Article) -> Bool {
        switch self {
        case .all: true
        case .unfinished: !article.hasCompletedReading && !article.hasPassedAssessment
        case .awaitingPass: article.hasCompletedReading && !article.hasPassedAssessment
        case .passed: article.hasPassedAssessment
        }
    }
}

struct ArticleRow: View {
    let article: Article
    let selected: Bool

    private var status: String? {
        if let attempt = article.attempts.last { return "最近 \(attempt.percentage) 分" }
        return article.level
    }

    private var importDate: String {
        article.added.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN")))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        VStack(alignment: .leading, spacing: 8) {
            Text(article.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudyPalette.ink)
                .lineLimit(3)
            HStack(spacing: 5) {
                Image(systemName: article.isGuided ? "doc.text" : "text.alignleft")
                    .foregroundStyle(StudyPalette.accent)
                    .accessibilityHidden(true)
                Text(article.displaySource ?? "本地文档")
                    .lineLimit(1)
                    .foregroundStyle(StudyPalette.muted)
                Spacer(minLength: 2)
                if let status {
                    Text(status)
                        .monospacedDigit()
                        .foregroundStyle(selected ? StudyPalette.accent : StudyPalette.muted)
                        .fixedSize()
                }
            }
            .font(.system(size: 10, weight: .medium))

            Label(importDate, systemImage: "calendar")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(StudyPalette.muted)
                .accessibilityLabel("导入时间 \(importDate)")

            ArticleCompletionBadges(article: article)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? StudyPalette.softAccent : StudyPalette.surface, in: shape)
        .overlay { shape.strokeBorder(selected ? StudyPalette.accentBorder : StudyPalette.border, lineWidth: 1).allowsHitTesting(false) }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

struct AppSettings: View {
    let directory: URL
    @AppStorage("ReaderFontSize") private var size = 20.0

    var body: some View {
        TabView {
            Form {
                Section("阅读") {
                    Stepper("英文字号 \(Int(size)) pt", value: $size, in: 15...28)
                    LabeledContent("外观", value: "跟随 macOS")
                    LabeledContent("查词来源", value: "macOS 已启用词典 · \(SystemDictionary.offlineSource)")
                    Button("打开词典") { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Dictionary.app"), configuration: .init()) }
                }
                Section("本地数据") {
                    Button("在 Finder 中打开数据文件夹") { NSWorkspace.shared.open(directory) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gear") }

            Form {
                Section("从 AI 导入") {
                    Text("让 AI 从真实新闻生成预译的双语 .newslingo 学习包，再双击、拖放或用本地命令导入。")
                    Button("显示 AI Skill 和示例") {
                        if let folder = Bundle.main.resourceURL?.appendingPathComponent("AI-Skill") {
                            NSWorkspace.shared.open(folder)
                        }
                    }
                    Button("复制本地导入命令") {
                        let paste = NSPasteboard.general
                        paste.clearContents()
                        paste.setString("open -b app.newslingo.reader /绝对路径/文章.newslingo", forType: .string)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("AI 导入", systemImage: "arrow.down.document") }
        }
        .frame(width: 490, height: 320)
    }
}
