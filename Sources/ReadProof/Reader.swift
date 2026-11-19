import AppKit
import Combine
import SwiftUI

private enum ReadMode: String, CaseIterable, Identifiable, Hashable {
    case english = "英文"
    case parallel = "中英对照"
    case chinese = "中文"
    var id: Self { self }
}

private struct SentencePosition: Hashable {
    let paragraph: Int
    let sentence: Int
}

struct ReaderView: View {
    let library: Library
    let article: Article
    let readerFont: Double
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = ReadMode.english
    @State private var toggledTranslations: [ReadMode: Set<SentencePosition>] = [:]
    @State private var showsQuiz = false
    @State private var showsStats = false
    @State private var didSetScroll = false
    @State private var timeStarted: ContinuousClock.Instant?
    @State private var clockRemainder = 0.0
    @State private var scrollPosition: Int?
    @State private var windowIsActive = true
    @State private var activity: ContinuousClock.Instant?
    @State private var monitor: Any?

    private var countsTime: Bool { phase == .active && windowIsActive && !showsQuiz && !showsStats && mode != .chinese }
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ReadingCover(article: article, showsChineseTitle: mode == .chinese, showsBothTitles: mode == .parallel)
                        .id("readerTop")
                    readingPage
                    readerFooter
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .accessibilityIdentifier("articleReader")
            .safeAreaInset(edge: .top, spacing: 0) {
                readerControls {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        proxy.scrollTo("readerTop", anchor: .top)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsStats = true } label: { Label("本文统计", systemImage: "chart.bar.xaxis") }
                    .help("本文统计")
                    .accessibilityIdentifier("articleStats")
                    .popover(isPresented: $showsStats, arrowEdge: .bottom) {
                        ArticleStats(article: article).padding(17).frame(width: 310)
                    }
            }
        }
        .sheet(isPresented: $showsQuiz) { QuizView(article: article, library: library) }
        .onAppear {
            if article.position > 0 { scrollPosition = article.position }
            windowIsActive = NSApp.isActive
            resetTimer()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
                if event.window?.isKeyWindow == true { activity = .now }
                return event
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                didSetScroll = true
            }
        }
        .onDisappear {
            flushTimer()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in windowIsActive = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in windowIsActive = false }
        .onChange(of: countsTime) { _, now in
            flushTimer()
            if now { resetTimer() }
        }
        .onReceive(tick) { _ in if countsTime { flushTimer(); timeStarted = .now } }
        .onChange(of: scrollPosition) { _, value in
            guard let value, didSetScroll, mode == .english || mode == .parallel else { return }
            if article.position != value { library.update(article.id) { $0.position = value } }
        }
    }

    private func readerControls(goToTop: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                readingModeControl
                Spacer(minLength: 0)
                Button(action: goToTop) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(StudyPalette.muted)
                .help("回到文章开头")
                .accessibilityLabel("回到文章开头")
                .accessibilityIdentifier("readerTopButton")

                if article.hasCompletedReading {
                    Button {
                        showsQuiz = true
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            Label(article.attempts.isEmpty ? "开始测验" : "再测一次", systemImage: "checklist").fixedSize()
                            Image(systemName: "checklist")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(StudyPalette.accent)
                    .help("开始文章测验")
                    .accessibilityLabel(article.attempts.isEmpty ? "开始测验" : "再测一次")
                    .accessibilityIdentifier("headerQuiz")
                } else {
                    ViewThatFits(in: .horizontal) {
                        Label("读完后测验", systemImage: "lock").fixedSize()
                        Image(systemName: "lock")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(StudyPalette.muted)
                    .accessibilityLabel("在文末标记已读完后解锁测验")
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            Rectangle().fill(StudyPalette.border).frame(height: 1).accessibilityHidden(true)
        }
        .background(StudyPalette.surface)
    }

    private var readingModeControl: some View {
        HStack(spacing: 3) {
            ForEach(ReadMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(mode == option ? .semibold : .medium))
                        .foregroundStyle(mode == option ? StudyPalette.accent : StudyPalette.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if mode == option {
                                Capsule().fill(StudyPalette.softAccent)
                                    .overlay { Capsule().strokeBorder(StudyPalette.accentBorder, lineWidth: 1) }
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(option != .english && article.bilingual == nil)
                .help(option != .english && article.bilingual == nil ? "此文章缺少配对译文" : option.rawValue)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(StudyPalette.canvas, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("阅读语言")
        .accessibilityIdentifier("readMode")
    }

    private var readingPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                if mode != .chinese {
                    Label("点按单词查词", systemImage: "cursorarrow.click")
                        .foregroundStyle(StudyPalette.accent)
                }
                Spacer(minLength: 4)
                if article.bilingual == nil {
                    Text("英文版 · 导入双语包启用对照")
                        .foregroundStyle(StudyPalette.muted)
                } else if mode != .english {
                    Label("学习包译文", systemImage: "character.bubble")
                        .foregroundStyle(StudyPalette.muted)
                }
            }
            .font(.caption.weight(.medium))
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(article.paragraphs.indices, id: \.self) { index in
                    paragraph(index).id(index)
                }
            }
            .scrollTargetLayout()
        }
        .padding(.horizontal, 23)
        .padding(.vertical, 23)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPanel()
    }

    private func paragraph(_ index: Int) -> some View {
        let pair = article.bilingual.flatMap { $0.indices.contains(index) ? $0[index] : nil }
        return Group {
            if let pair {
                if mode == .chinese {
                    translationBlock(pair.zh)
                } else {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(Array(pair.sentences.enumerated()), id: \.offset) { row in
                            sentenceRow(row.element, at: SentencePosition(paragraph: index, sentence: row.offset))
                        }
                    }
                }
            } else {
                DictionaryText(text: article.paragraphs[index], fontSize: readerFont, onLookup: recordLookup)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readingParagraph\(index)")
    }

    private func sentenceRow(_ sentence: BilingualSentence, at position: SentencePosition) -> some View {
        let toggled = toggledTranslations[mode]?.contains(position) ?? false
        let showsTranslation = (mode == .parallel) != toggled
        let action = SentenceTranslationAction(
            isExpanded: showsTranslation,
            accessibilityContext: "第 \(position.paragraph + 1) 段第 \(position.sentence + 1) 句",
            identifier: "sentenceTranslation-\(position.paragraph)-\(position.sentence)"
        ) {
            if toggledTranslations[mode, default: []].remove(position) == nil {
                toggledTranslations[mode, default: []].insert(position)
            }
        }
        return VStack(alignment: .leading, spacing: 7) {
            DictionaryText(text: sentence.en, fontSize: readerFont, translation: action, onLookup: recordLookup)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsTranslation {
                translationBlock(sentence.zh)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pairedSentence-\(position.paragraph)-\(position.sentence)")
    }

    private func translationBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: readerFont * 0.82))
            .lineSpacing(6)
            .foregroundStyle(StudyPalette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(mode == .chinese ? 0 : 12)
            .background(mode == .chinese ? Color.clear : StudyPalette.softAccent, in: RoundedRectangle(cornerRadius: 10))
    }

    private var readerFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            if article.hasCompletedReading {
                StudyGlyph(symbol: "checklist", size: 37)
                VStack(alignment: .leading, spacing: 5) {
                    Text("阅读测验").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(article.isGuided ? "提交后查看原文证据" : "提交后查看答案")
                        .font(.caption).foregroundStyle(StudyPalette.muted)
                }
                Spacer(minLength: 5)
                Button(article.attempts.isEmpty ? "开始测验" : "再测一次") {
                    showsQuiz = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("footerQuiz")
            } else {
                StudyGlyph(symbol: "book.closed", size: 37)
                VStack(alignment: .leading, spacing: 5) {
                    Text("读完这篇文章了吗？").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(mode == .chinese ? "切换到英文或中英对照后可标记" : "确认读完后即可开始测验")
                        .font(.caption).foregroundStyle(StudyPalette.muted)
                }
                Spacer(minLength: 5)
                Button("标记为已读完") { library.update(article.id) { $0.markReadingComplete() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(mode == .chinese)
                    .accessibilityIdentifier("confirmReadingCompletion")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPanel()
    }

    private func recordLookup(_ word: String) {
        library.update(article.id) { $0.lookedUp[word.lowercased(), default: 0] += 1 }
    }

    private func resetTimer() {
        activity = .now
        timeStarted = countsTime ? .now : nil
    }

    private func flushTimer() {
        guard let start = timeStarted else { return }
        timeStarted = nil
        let now = ContinuousClock.Instant.now
        let end = min(now, (activity ?? now).advanced(by: .seconds(120)))
        let pieces = start.duration(to: end).components
        let elapsed = max(0, Double(pieces.seconds) + Double(pieces.attoseconds) / 1e18)
        clockRemainder += elapsed
        let seconds = Int(clockRemainder)
        guard seconds > 0 else { return }
        clockRemainder -= Double(seconds)
        library.update(article.id) { $0.secondsByDay[Library.day(), default: 0] += seconds }
    }
}
