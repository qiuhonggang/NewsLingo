import SwiftUI

private let questionLabels = [
    "mainIdea": "主旨", "detail": "细节", "inference": "推断", "vocabulary": "语境词汇", "cloze": "原文填空"
]

struct QuizView: View {
    let article: Article
    let library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var answers: [Int: Int] = [:]
    @State private var results: Attempt?
    @State private var orders: [[Int]]
    @State private var confirmClose = false
    @State private var saveFailed = false

    init(article: Article, library: Library) {
        self.article = article
        self.library = library
        _orders = State(initialValue: article.questions.map { Array($0.choices.indices).shuffled() })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 11) {
                    StudyGlyph(symbol: results == nil ? "checklist" : "checkmark.seal", size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(results == nil ? "阅读测验" : "测验结果")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(StudyPalette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(article.title).font(.callout).foregroundStyle(StudyPalette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 5)
                    if results == nil {
                        Text("第 \(page + 1) 题，共 \(article.questions.count) 题")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(StudyPalette.accent)
                            .accessibilityIdentifier("quizStep")
                    }
                }
                if results == nil {
                    HStack(spacing: 5) {
                        ForEach(article.questions.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? StudyPalette.accent : (answers[index] == nil ? StudyPalette.border : StudyPalette.accentBorder))
                                .frame(height: 4)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(22)
            .background(StudyPalette.surface)
            if let results {
                resultsPage(results)
            } else {
                questionPage
            }
            Rectangle().fill(StudyPalette.border).frame(height: 1).accessibilityHidden(true)
            controls
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(StudyPalette.surface)
        }
        .frame(minWidth: 540, idealWidth: 630, maxWidth: 710, minHeight: 495, idealHeight: 555, maxHeight: 690)
        .background(StudyPalette.canvas)
        .confirmationDialog("放弃本次测验？", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("放弃测验", role: .destructive) { dismiss() }
        } message: {
            Text("本次答案尚未提交。")
        }
        .alert("无法保存测验成绩", isPresented: $saveFailed) {
            Button("好", role: .cancel) {}
        } message: { Text("请检查资料库的写入权限和剩余空间，然后重新提交。") }
    }

    private var questionPage: some View {
        let question = article.questions[page]
        return ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(questionLabels[question.kind] ?? "理解")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudyPalette.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(StudyPalette.softAccent, in: Capsule())
                Text(question.prompt)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(StudyPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("quizQuestion")
                VStack(spacing: 7) {
                    ForEach(Array(orders[page].enumerated()), id: \.offset) { index, choice in
                        QuizOption(letter: ["A", "B", "C", "D"][index],
                                   text: question.choices[choice],
                                   isSelected: answers[page] == choice) {
                            answers[page] = choice
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                        .accessibilityIdentifier("choice\(index)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("选择一个答案")
                .accessibilityIdentifier("quizChoices")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .id(page)
    }

    private var controls: some View {
        HStack {
            if results != nil {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("finishQuiz")
            } else {
                Button("取消") { if answers.isEmpty { dismiss() } else { confirmClose = true } }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if page > 0 { Button("上一题") { page -= 1 } }
                if page < article.questions.count - 1 {
                    Button("下一题") { page += 1 }
                        .disabled(answers[page] == nil).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("nextQuestion")
                } else {
                    Button("提交测验") { submit() }
                        .disabled(answers.count != article.questions.count).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("submitQuiz")
                }
            }
        }
    }

    private func resultsPage(_ score: Attempt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(score.percentage)")
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("分").font(.title3.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        Text("答对 \(score.correct) / \(score.total) 题")
                            .font(.callout)
                            .foregroundStyle(StudyPalette.whiteMint)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("quizScore")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Label(score.isPassing ? "测评通过" : "测评未通过",
                              systemImage: score.isPassing ? "checkmark.seal.fill" : "xmark.circle")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(score.isPassing ? StudyPalette.mint : StudyPalette.whiteMint)
                            .accessibilityIdentifier("quizPassingStatus")
                        Text("\(Attempt.passingPercentage) 分通过")
                            .font(.caption).foregroundStyle(StudyPalette.whiteMint)
                        Label(score.isPassing ? "已安排 3 天后复习" : "已安排明天复习", systemImage: "calendar")
                            .font(.callout).foregroundStyle(StudyPalette.whiteMint)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 13)
                .background(StudyPalette.hero, in: RoundedRectangle(cornerRadius: 15))

                ForEach(Array(article.questions.enumerated()), id: \.offset) { index, question in
                    let isCorrect = score.answers[index] == question.answer
                    VStack(alignment: .leading, spacing: 8) {
                        Label("第 \(index + 1) 题 · \(isCorrect ? "答对" : "答错")",
                              systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isCorrect ? StudyPalette.accent : Color.orange)
                        Text(question.prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
                        if !isCorrect {
                            Text("你的答案　\(question.choices[score.answers[index]])").font(.callout).foregroundStyle(.secondary)
                        }
                        Text("正确答案　\(question.choices[question.answer])").font(.callout)
                        Text(question.explanation).font(.callout)
                        Text(question.evidence)
                            .font(.system(.callout, design: .serif))
                            .lineSpacing(4).foregroundStyle(.secondary)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(StudyPalette.canvas, in: RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                            .accessibilityLabel("原文证据：\(question.evidence)")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studyPanel(cornerRadius: 12)
                }
            }
            .padding(24)
        }
    }

    private func submit() {
        guard answers.count == article.questions.count else { return }
        let ordered = article.questions.indices.compactMap { answers[$0] }
        let correct = zip(article.questions, ordered).filter { $0.0.answer == $0.1 }.count
        let attempt = Attempt(date: .now, answers: ordered, correct: correct, total: article.questions.count)
        library.update(article.id) { $0.attempts.append(attempt) }
        if library.article(article.id)?.attempts.last?.id == attempt.id {
            results = attempt
        } else {
            library.message = nil
            saveFailed = true
        }
    }
}

private struct QuizOption: View {
    let letter: String
    let text: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11)
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Text(letter)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(isSelected ? StudyPalette.accent : StudyPalette.muted)
                    .frame(width: 25, height: 25)
                    .background(isSelected ? StudyPalette.surface : StudyPalette.canvas, in: RoundedRectangle(cornerRadius: 7))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(StudyPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? StudyPalette.accent : StudyPalette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 39, alignment: .leading)
            .background(isSelected ? StudyPalette.softAccent : StudyPalette.surface, in: shape)
            .overlay {
                shape.strokeBorder(isSelected || isHovered ? StudyPalette.accentBorder : StudyPalette.border,
                                   lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(letter). \(text)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
