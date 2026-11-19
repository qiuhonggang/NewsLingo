import Charts
import SwiftUI

struct ArticleStats: View {
    let article: Article
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("本文统计").font(.headline).accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                LabeledContent("前台英文阅读", value: ArticleText.roundedMinutes(article.readingSeconds))
                LabeledContent("查词次数", value: "\(article.lookedUp.values.reduce(0, +)) 次")
                LabeledContent("测验次数", value: "\(article.attempts.count) 次")
                if let first = article.attempts.first, let latest = article.attempts.last {
                    Divider()
                    LabeledContent("首答 · 最近", value: "\(first.percentage) 分 · \(latest.percentage) 分")
                    if let date = article.reviewDate {
                        LabeledContent("下次复习") { Text(date, format: .dateTime.month().day()) }
                    }
                }
            }
            .font(.callout).monospacedDigit()
            if !article.lookedUp.isEmpty {
                Divider()
                Text("查过的词").font(.subheadline.weight(.semibold))
                Text(article.lookedUp.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(8).map(\.key).joined(separator: "、"))
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}

struct StatisticsView: View {
    let articles: [Article]
    let openArticle: (String) -> Void
    @State private var range = 7

    private struct Daily: Identifiable {
        let date: Date
        let seconds: Int
        var id: Date { date }
    }

    private var daily: [Daily] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<range).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Library.day(day)
            return Daily(date: day, seconds: articles.reduce(0) { $0 + ($1.secondsByDay[key] ?? 0) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack(spacing: 12) {
                    StudyGlyph(symbol: "chart.bar.xaxis", size: 44)
                    Text("学习统计")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudyPalette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("statisticsTitle")
                }
                overview
                chart
                    .padding(19)
                    .studyPanel()
                recentAttempts
                    .padding(19)
                    .studyPanel()
            }
            .frame(maxWidth: 850, alignment: .leading)
            .padding(34)
            .frame(maxWidth: .infinity)
        }
    }

    private var overview: some View {
        let assessed = articles.filter(\.isGuided).compactMap(\.attempts.first)
        let accuracy = assessed.isEmpty ? nil : Int((Double(assessed.map(\.percentage).reduce(0, +)) / Double(assessed.count)).rounded())
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
            GridRow {
                metric("已读完", icon: "book", "\(articles.filter(\.hasCompletedReading).count) 篇")
                metric("完成测验", icon: "checklist", "\(articles.filter { !$0.attempts.isEmpty }.count) 篇")
                metric("理解首答均分", icon: "target", accuracy.map { "\($0) 分" } ?? "—")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, icon: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StudyGlyph(symbol: icon, size: 30)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StudyPalette.ink)
            Text(title).font(.caption).foregroundStyle(StudyPalette.muted)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studyPanel(cornerRadius: 13)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("英文阅读时长").font(.headline)
                    Text(ArticleText.roundedMinutes(daily.reduce(0) { $0 + $1.seconds }))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Picker("时长范围", selection: $range) {
                    Text("近 7 天").tag(7)
                    Text("近 30 天").tag(30)
                }
                .labelsHidden().pickerStyle(.segmented)
                .frame(width: 150)
            }
            let maximum = max(1, (daily.map(\.seconds).max() ?? 0) / 60 + 1)
            Chart(daily) { day in
                BarMark(x: .value("日期", day.date, unit: .day), y: .value("分钟", Double(day.seconds) / 60))
                    .foregroundStyle(StudyPalette.accent.gradient)
                    .cornerRadius(3)
                    .accessibilityLabel(Text(day.date, format: .dateTime.month().day()))
                    .accessibilityValue(ArticleText.roundedMinutes(day.seconds))
            }
            .chartYScale(domain: 0...Double(maximum))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    if let number = value.as(Double.self), number == number.rounded() {
                        AxisValueLabel { Text("\(Int(number)) 分") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 7)) {
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 185)
            if daily.allSatisfy({ $0.seconds == 0 }) {
                Text("此时间段还没有英文阅读记录。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var recentAttempts: some View {
        let recent = articles.filter { !$0.attempts.isEmpty }.sorted {
            ($0.attempts.last?.date ?? .distantPast) > ($1.attempts.last?.date ?? .distantPast)
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("文章成绩").font(.headline)
            if recent.isEmpty {
                Text("完成一篇文章的测验后，成绩会显示在这里。").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(recent) { article in
                Button {
                    openArticle(article.id)
                } label: {
                    HStack(spacing: 9) {
                        StudyGlyph(symbol: "doc.text", size: 29)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.title).font(.callout.weight(.medium)).foregroundStyle(StudyPalette.ink)
                            Text(article.isGuided ? "理解测验" : "原文填空").font(.caption).foregroundStyle(StudyPalette.muted)
                        }
                        Spacer(minLength: 10)
                        if let first = article.attempts.first, let last = article.attempts.last {
                            Text("首答 \(first.percentage)  ·  最近 \(last.percentage)")
                                .font(.caption.monospacedDigit()).foregroundStyle(StudyPalette.accent)
                        }
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(StudyPalette.muted)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyPalette.canvas, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开这篇文章")
            }
        }
    }
}
