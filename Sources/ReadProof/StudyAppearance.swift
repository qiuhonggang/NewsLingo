import AppKit
import SwiftUI

enum StudyPalette {
    static let canvas = adaptive(0xEFF3F8, 0x141922)
    static let library = adaptive(0xF5F7FA, 0x1A202B)
    static let surface = adaptive(0xFFFFFF, 0x212937)
    static let border = adaptive(0xDDE5EE, 0x394454)
    static let ink = adaptive(0x172836, 0xEEF4FA)
    static let muted = adaptive(0x536471, 0xAFBDCB)
    static let accent = adaptive(0x176356, 0xA1E6CF)
    static let softAccent = adaptive(0xE9F7F1, 0x263F3C)
    static let accentBorder = adaptive(0xA7D6C7, 0x496D65)
    static let mint = Color(nsColor: rgb(0xA6EFDA))
    static let whiteMint = Color(nsColor: rgb(0xDBF3F0))
    static let hero = LinearGradient(
        colors: [Color(nsColor: rgb(0x1C315C)), Color(nsColor: rgb(0x172842)), Color(nsColor: rgb(0x114A50))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func wordColors(for appearance: NSAppearance) -> (background: NSColor, underline: NSColor) {
        let dark = isDark(appearance)
        return (rgb(dark ? 0x31594C : 0xBBEBDA), rgb(dark ? 0xA2E9D1 : 0x276F60))
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in rgb(isDark(appearance) ? dark : light) })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

extension View {
    func studyPanel(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background(StudyPalette.surface, in: shape)
            .overlay { shape.strokeBorder(StudyPalette.border, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct StudyGlyph: View {
    let symbol: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(StudyPalette.accent)
            .frame(width: size, height: size)
            .background(StudyPalette.softAccent, in: RoundedRectangle(cornerRadius: size * 0.30))
            .accessibilityHidden(true)
    }
}

struct ArticleCompletionBadges: View {
    let article: Article
    var onCover = false

    var body: some View {
        if article.hasCompletedReading || article.hasPassedAssessment {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { badges }
                    .fixedSize()
                VStack(alignment: .leading, spacing: 5) { badges }
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if article.hasCompletedReading {
            badge("已读完", symbol: "checkmark.circle", highlighted: false)
        }
        if article.hasPassedAssessment {
            badge("测评通过", symbol: "checkmark.seal.fill", highlighted: true)
        }
    }

    private func badge(_ title: String, symbol: String, highlighted: Bool) -> some View {
        let ink = onCover ? (highlighted ? StudyPalette.mint : StudyPalette.whiteMint)
                          : (highlighted ? StudyPalette.accent : StudyPalette.muted)
        let background = onCover ? ink.opacity(0.14) : (highlighted ? StudyPalette.softAccent : StudyPalette.canvas)
        let border = onCover ? ink.opacity(0.40) : (highlighted ? StudyPalette.accentBorder : StudyPalette.border)
        return Label(title, systemImage: symbol)
            .font(.system(size: onCover ? 11 : 10, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .overlay { Capsule().strokeBorder(border, lineWidth: 1) }
            .fixedSize()
    }
}

struct ReadingCover: View {
    let article: Article
    let showsChineseTitle: Bool
    let showsBothTitles: Bool
    @State private var isSourceHovered = false
    private var minutes: Int { max(1, Int(ceil(Double(article.words) / 150))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                if let level = article.level {
                    Text(level)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(StudyPalette.mint, in: Capsule())
                        .foregroundStyle(Color(red: 0.08, green: 0.25, blue: 0.24))
                        .accessibilityLabel("CEFR \(level)")
                }
                source
                if let published = article.published {
                    Text(published)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(StudyPalette.whiteMint)

            Text(showsChineseTitle ? article.titleZh ?? article.title : article.title)
                .font(.system(size: 37, weight: .semibold, design: .serif))
                .tracking(-0.7)
                .foregroundStyle(.white)
                .frame(maxWidth: 580, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("articleTitle")
            if showsBothTitles, let title = article.titleZh {
                Text(title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(StudyPalette.whiteMint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Label("\(article.words) 词", systemImage: "text.alignleft")
                    Label("约 \(minutes) 分钟", systemImage: "clock")
                    Label(article.isGuided ? "\(article.questions.count) 道理解题" : "\(article.questions.count) 道填空", systemImage: "checklist")
                }
                Spacer(minLength: 0)
                ArticleCompletionBadges(article: article, onCover: true)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(StudyPalette.whiteMint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                StudyPalette.hero
                Canvas { context, size in
                    let angle = -24.0 * Double.pi / 180
                    let center = CGPoint(x: size.width * 0.90, y: size.height * 0.55)
                    let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
                    for inset in [0.0, 19.0, 38.0] {
                        let rect = CGRect(x: -119 + inset, y: -70 + inset, width: 238 - inset * 2, height: 140 - inset * 2)
                        let outline = Path(roundedRect: rect, cornerRadius: 23).applying(transform)
                        context.stroke(outline, with: .color(StudyPalette.mint.opacity(0.16)), lineWidth: 1)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 19))
    }

    @ViewBuilder
    private var source: some View {
        if let url = article.sourceURL {
            let name = article.displaySource ?? "打开原文"
            Link(destination: url) {
                Label {
                    Text(name)
                        .underline(isSourceHovered)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(isSourceHovered ? Color.white : StudyPalette.whiteMint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(StudyPalette.whiteMint.opacity(isSourceHovered ? 0.19 : 0.06), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(StudyPalette.whiteMint.opacity(isSourceHovered ? 0.72 : 0.28), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { isSourceHovered = $0 }
            .help(article.sourceArticleTitle.map { "打开原文 · \($0)" } ?? "打开原文")
            .accessibilityLabel(name == "打开原文" ? name : "打开原文，\(name)")
            .accessibilityIdentifier("sourceArticleLink")
        } else {
            Label(article.displaySource ?? "本地文档", systemImage: "doc.text")
                .lineLimit(1)
        }
    }
}
