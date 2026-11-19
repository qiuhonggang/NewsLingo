import AppKit
import AVFoundation
import SwiftUI

struct WordDefinitionView: View {
    let word: String
    let entry: SystemDictionary.Entry
    let showSystem: () -> Void
    let close: () -> Void

    @State private var language = DefinitionLanguage.english
    @State private var speaker = AVSpeechSynthesizer()
    @State private var contextMatches: [DefinitionLanguage: ContextMatch] = [:]
    @State private var isExpanded = false

    private struct ContextMatch {
        let preferred: Int?
    }

    private enum DefinitionLanguage: String, CaseIterable, Identifiable {
        case english = "英英"
        case chinese = "英汉"
        var id: Self { self }
    }

    private enum ScrollAnchor {
        case firstSense, otherSenses
    }

    static func size(on screen: NSScreen?) -> CGSize {
        let available = screen?.visibleFrame.size ?? CGSize(width: 800, height: 600)
        return CGSize(width: min(374, available.width - 32), height: min(390, available.height - 40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(StudyPalette.border)
            definitions
            Divider().overlay(StudyPalette.border)
            footer
        }
        .background(StudyPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(StudyPalette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onChange(of: language) { isExpanded = false }
        .task { await matchContext() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(word)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudyPalette.ink)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if let phrase = entry.phrase, phrase.caseInsensitiveCompare(word) != .orderedSame {
                        Text(phrase)
                            .font(.callout)
                            .foregroundStyle(StudyPalette.accent)
                            .lineLimit(1)
                            .accessibilityLabel("所在词组 \(phrase)")
                    }
                    if let pronunciation = entry.chinese?.pronunciation ?? entry.english?.pronunciation {
                        Text(pronunciation)
                            .font(.caption)
                            .foregroundStyle(StudyPalette.muted)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 4)
                Button(action: speak) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(StudyPalette.accent)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("朗读")
                .accessibilityLabel("朗读英文")

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(StudyPalette.muted)
                        .frame(width: 24, height: 26)
                }
                .buttonStyle(.borderless)
                .help("关闭释义")
                .accessibilityLabel("关闭释义")
            }

            Picker("词典语言", selection: $language) {
                ForEach(DefinitionLanguage.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 132)
            .accessibilityIdentifier("dictionaryLanguage")
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    private var definitions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let definition, let firstSense {
                        VStack(alignment: .leading, spacing: 9) {
                            if let status { status }
                            DictionarySenseView(number: 1, sense: definition.senses[firstSense])
                                .accessibilityIdentifier("primaryDictionarySense")
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudyPalette.library, in: RoundedRectangle(cornerRadius: 8))
                        .id(ScrollAnchor.firstSense)
                        if isExpanded {
                            otherSenses(in: definition, after: firstSense)
                        } else if definition.senses.count == 1 {
                            notes(definition.notes)
                        }
                    } else if let definition, !definition.notes.isEmpty {
                        notes(definition.notes)
                    } else if language == .english {
                        Text("当前词典没有收录这个词的英英释义。")
                    } else {
                        Text("可从系统词典或剑桥英汉词典查找。")
                        Button("打开系统查找", action: showSystem)
                            .controlSize(.small)
                    }
                }
                .font(.callout)
                .foregroundStyle(StudyPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .textSelection(.enabled)
            }
            .id(language)
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("dictionaryContent")
            .onChange(of: isExpanded) { _, expanded in
                proxy.scrollTo(expanded ? ScrollAnchor.otherSenses : .firstSense, anchor: .top)
            }
        }
    }

    private func otherSenses(in definition: DictionaryDefinition, after firstSense: Int) -> some View {
        let others = definition.senses.indices.filter { $0 != firstSense }
        return VStack(alignment: .leading, spacing: 12) {
            Text("其他义项")
                .font(.caption.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)
                .id(ScrollAnchor.otherSenses)
            ForEach(Array(others.enumerated()), id: \.element) { index, sense in
                if index > 0 { Divider().overlay(StudyPalette.border) }
                DictionarySenseView(number: index + 2, sense: definition.senses[sense])
            }
            notes(definition.notes)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 4)
    }

    private func notes(_ notes: [DictionaryDefinition.Note]) -> some View {
        ForEach(notes.indices, id: \.self) { index in
            let note = notes[index]
            VStack(alignment: .leading, spacing: 6) {
                Divider().overlay(StudyPalette.border)
                Text(note.title)
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(note.lines.indices, id: \.self) { line in
                    Text(note.lines[line]).lineSpacing(3)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let definition, definition.senses.count > 1 {
                let count = definition.senses.count - 1
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "收起其他义项" : "其他义项（\(count)）",
                          systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StudyPalette.accent)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 25)
                        .contentShape(Rectangle())
                        .background(StudyPalette.softAccent, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityIdentifier("otherDictionarySenses")
            }

            Spacer(minLength: 3)
            if let source {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(StudyPalette.muted)
                    .lineLimit(1)
            }
            Menu {
                Button("在系统浮窗中查看", action: showSystem)
                if let url = cambridge {
                    Button("在剑桥英汉词典中查找") { NSWorkspace.shared.open(url) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(StudyPalette.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多词典")
            .accessibilityLabel("更多词典")
            .accessibilityIdentifier("moreDictionaries")
        }
        .frame(minHeight: 25)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var definition: DictionaryDefinition? {
        language == .english ? entry.english : entry.chinese
    }

    private var firstSense: Int? {
        guard let definition else { return nil }
        let samePartOfSpeech = entry.context?.partOfSpeech.flatMap { part in
            definition.senses.firstIndex { $0.partOfSpeech == part }
        }
        return contextMatches[language]?.preferred ?? samePartOfSpeech ?? definition.senses.indices.first
    }

    private var status: Text? {
        guard entry.context != nil, let definition, definition.senses.count > 1 else { return nil }
        let match = contextMatches[language]
        if match?.preferred != nil {
            return Text("语境优先").font(.caption.weight(.semibold)).foregroundStyle(StudyPalette.accent)
        }
        return Text(match == nil ? "正在匹配原句语境" : "语境待确认")
            .font(.caption).foregroundStyle(StudyPalette.muted)
    }

    private var source: String? {
        if language == .english { return entry.english.map { _ in entry.englishSource } }
        return entry.chinese.map { _ in "macOS 已启用词典" }
    }

    private func matchContext() async {
        guard let context = entry.context else { return }
        for language in DefinitionLanguage.allCases {
            let definition = language == .english ? entry.english : entry.chinese
            guard let definition, definition.senses.count > 1 else { continue }
            let preferred = await DictionarySenseRanker.shared.preferredSense(in: definition, context: context)
            guard !Task.isCancelled else { return }
            contextMatches[language] = ContextMatch(preferred: preferred)
        }
    }

    private func speak() {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: entry.phrase ?? word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.43
        speaker.speak(utterance)
    }

    private var cambridge: URL? {
        let term = (entry.phrase ?? word).lowercased().replacingOccurrences(of: " ", with: "-")
        guard let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !escaped.isEmpty else { return nil }
        return URL(string: "https://dictionary.cambridge.org/dictionary/english-chinese-simplified/\(escaped)")
    }
}

private struct DictionarySenseView: View {
    let number: Int
    let sense: DictionarySense

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(StudyPalette.accent)
                .frame(minWidth: 20, minHeight: 20)
                .background(StudyPalette.softAccent, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel("义项 \(number)")

            VStack(alignment: .leading, spacing: 8) {
                if let heading = sense.heading {
                    Text(heading)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StudyPalette.accent)
                }
                if let grammar = sense.grammar {
                    Text(grammar).font(.caption).foregroundStyle(StudyPalette.muted)
                }
                ForEach(sense.meanings.indices, id: \.self) { index in
                    let meaning = sense.meanings[index]
                    VStack(alignment: .leading, spacing: 2) {
                        if let usage = meaning.usage {
                            Text(usage).font(.caption).foregroundStyle(StudyPalette.muted)
                        }
                        meaningText(meaning).lineSpacing(3)
                    }
                }
                if !sense.examples.isEmpty {
                    examples
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func meaningText(_ meaning: DictionaryMeaning) -> Text {
        let gloss = Text(meaning.text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(StudyPalette.ink)
        guard let annotation = meaning.annotation else { return gloss }
        let detail = Text(annotation).font(.caption).foregroundStyle(StudyPalette.muted)
        return Text("\(gloss)  \(detail)")
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("例句与搭配")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(StudyPalette.muted)
                .accessibilityAddTraits(.isHeader)
            ForEach(sense.examples.indices, id: \.self) { index in
                let example = sense.examples[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.text).foregroundStyle(StudyPalette.ink)
                    if let translation = example.translation {
                        Text(translation).foregroundStyle(StudyPalette.muted)
                    }
                }
                .font(.system(size: 13))
                .lineSpacing(2)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(StudyPalette.accentBorder)
                        .frame(width: 2)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
