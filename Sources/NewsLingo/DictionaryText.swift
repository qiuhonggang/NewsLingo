import AppKit
import SwiftUI

struct SentenceTranslationAction {
    let isExpanded: Bool
    let accessibilityContext: String
    let identifier: String
    let perform: () -> Void

    var title: String { isExpanded ? "收起译文" : "翻译整句" }
}

struct DictionaryText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    var translation: SentenceTranslationAction? = nil
    let onLookup: (String) -> Void

    func makeNSView(context: Context) -> WordTextView {
        let view = WordTextView(usingTextLayoutManager: false)
        view.drawsBackground = false
        view.isEditable = false
        view.isSelectable = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 1
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        view.setAccessibilityLabel(text)
        return view
    }

    func updateNSView(_ view: WordTextView, context: Context) {
        view.onLookup = onLookup
        view.updateReadingText(text, fontSize: fontSize, translation: translation)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: WordTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        return CGSize(width: width, height: view.measuredHeight(for: width))
    }
}

final class WordTextView: NSTextView, NSPopoverDelegate {
    var onLookup: (String) -> Void = { _ in }
    private var readingText = ""
    private var readingSize: CGFloat = 0
    private var translation: SentenceTranslationAction?
    private var translationRange: NSRange?
    private let translationButtonSize = NSSize(width: 62, height: 19)
    private let translationGap: CGFloat = 5
    private lazy var translationButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(translateSentence))
        button.bezelStyle = .inline
        button.controlSize = .small
        return button
    }()
    private var definitionPopover: NSPopover?
    private var definitionDismissalMonitor: Any?
    private var markedRange: NSRange?
    private var clickLookup: DispatchWorkItem?

    private let measuringText = NSTextStorage()
    private lazy var measuringLayout: NSLayoutManager = {
        let layout = NSLayoutManager()
        layout.addTextContainer(measuringContainer)
        measuringText.addLayoutManager(layout)
        return layout
    }()
    private let measuringContainer = NSTextContainer(size: .zero)

    func updateReadingText(_ text: String, fontSize: CGFloat, translation action: SentenceTranslationAction?) {
        let hasAction = action != nil
        let needsTextUpdate = readingText != text || readingSize != fontSize || (translation != nil) != hasAction
        translation = action
        if let action {
            translationButton.attributedTitle = NSAttributedString(string: action.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ])
            translationButton.toolTip = action.isExpanded ? action.title : "显示本句中文译文"
            translationButton.setAccessibilityLabel("\(action.accessibilityContext)，\(action.title)")
            translationButton.setAccessibilityIdentifier(action.identifier)
            if translationButton.superview == nil { addSubview(translationButton) }
        }
        guard needsTextUpdate else { return }
        dismissDefinition()
        readingText = text
        readingSize = fontSize
        setAccessibilityLabel(text)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.38
        paragraph.lineBreakMode = .byWordWrapping
        let font = NSFont(name: "Georgia", size: fontSize) ?? .systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ]
        let content = NSMutableAttributedString(string: text, attributes: attributes)
        if hasAction {
            // Reserve inline space in TextKit for the native button. The word joiner keeps it with the sentence ending.
            content.append(NSAttributedString(string: "\u{2060}", attributes: attributes))
            let attachment = NSTextAttachment()
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: NSImage(size: NSSize(
                width: translationButtonSize.width + translationGap, height: translationButtonSize.height
            )))
            let range = NSRange(location: content.length, length: 1)
            translationRange = range
            content.append(NSAttributedString(attachment: attachment))
            content.addAttributes(attributes, range: range)
        } else if translationRange != nil {
            translationRange = nil
            translationButton.removeFromSuperview()
        }
        textStorage?.setAttributedString(content)
        measuringText.setAttributedString(content)
        measuringContainer.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 1
        needsLayout = true
    }

    @objc private func translateSentence() {
        dismissDefinition()
        translation?.perform()
    }

    override func accessibilityChildren() -> [Any]? {
        if translation != nil { return [translationButton] }
        return super.accessibilityChildren()
    }

    override func accessibilityValue() -> String? {
        if translation != nil { return readingText }
        return super.accessibilityValue()
    }

    override func layout() {
        super.layout()
        guard let translationRange, let layoutManager, let textContainer, bounds.width > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let glyphs = layoutManager.glyphRange(forCharacterRange: translationRange, actualCharacterRange: nil)
        let slot = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        translationButton.frame = NSRect(
            x: slot.minX + textContainerOrigin.x + translationGap,
            y: round(line.midY + textContainerOrigin.y - translationButtonSize.height / 2),
            width: translationButtonSize.width,
            height: translationButtonSize.height
        )
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        let layout = measuringLayout
        measuringContainer.containerSize = CGSize(width: max(1, width - 2 * textContainerInset.width), height: 100_000)
        layout.ensureLayout(for: measuringContainer)
        return ceil(layout.usedRect(for: measuringContainer).height + 2 * textContainerInset.height + 1)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let textContainer, newSize.width > 0 else { return }
        let width = max(1, newSize.width - 2 * textContainerInset.width)
        textContainer.containerSize = CGSize(width: width, height: 100_000)
        if translationRange != nil { needsLayout = true }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            clickLookup?.cancel()
            dismissDefinition()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let markedRange { drawMark(at: markedRange) }
    }

    func popoverWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSPopover, closing === definitionPopover else { return }
        clearDefinition()
    }

    func dismissDefinition() {
        definitionPopover?.delegate = nil
        definitionPopover?.close()
        clearDefinition()
    }

    private func clearDefinition() {
        definitionPopover = nil
        if let definitionDismissalMonitor {
            NSEvent.removeMonitor(definitionDismissalMonitor)
            self.definitionDismissalMonitor = nil
        }
        clearMark()
    }

    private func drawMark(at range: NSRange) {
        let colors = StudyPalette.wordColors(for: effectiveAppearance)
        layoutManager?.addTemporaryAttributes([
            .backgroundColor: colors.background,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: colors.underline
        ], forCharacterRange: range)
        markedRange = range
        needsDisplay = true
    }

    private func clearMark() {
        guard let markedRange else { return }
        for key: NSAttributedString.Key in [.backgroundColor, .underlineStyle, .underlineColor] {
            layoutManager?.removeTemporaryAttribute(key, forCharacterRange: markedRange)
        }
        self.markedRange = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        clickLookup?.cancel()
        let range = wordRange(near: event.locationInWindow)
        super.mouseDown(with: event)
        guard event.clickCount == 1,
              event.modifierFlags.intersection([.shift, .control, .option]).isEmpty,
              selectedRange().length == 0, let range,
              let release = NSApp.currentEvent, release.type == .leftMouseUp,
              hypot(release.locationInWindow.x - event.locationInWindow.x,
                    release.locationInWindow.y - event.locationInWindow.y) < 4 else { return }
        let lookup = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil else { return }
            self.showWord(range)
        }
        clickLookup = lookup
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(170), execute: lookup)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let selection = selectedRange()
        guard let range = selection.length > 0 ? selection : wordRange(near: event.locationInWindow) else { return menu }
        let item = NSMenuItem(title: "在 NewsLingo 中查词", action: #selector(lookupFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = NSValue(range: range)
        menu.insertItem(item, at: 0)
        return menu
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "d", event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .command] {
            let selection = selectedRange()
            if selection.length > 0 { showWord(selection); return }
        }
        super.keyDown(with: event)
    }

    override func copy(_ sender: Any?) {
        let length = (readingText as NSString).length
        guard translationRange != nil, NSMaxRange(selectedRange()) > length else {
            super.copy(sender)
            return
        }
        let range = NSIntersectionRange(selectedRange(), NSRange(location: 0, length: length))
        guard range.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((readingText as NSString).substring(with: range), forType: .string)
    }

    @objc private func lookupFromMenu(_ sender: NSMenuItem) {
        if let range = (sender.representedObject as? NSValue)?.rangeValue { showWord(range) }
    }

    private func wordRange(near windowPoint: NSPoint) -> NSRange? {
        guard let layoutManager, let textContainer, !readingText.isEmpty else { return nil }
        let inView = convert(windowPoint, from: nil)
        let point = CGPoint(x: inView.x - textContainerOrigin.x, y: inView.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
                .insetBy(dx: -2, dy: -2).contains(point) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        return ArticleText.wordPattern.matches(in: readingText, range: NSRange(location: 0, length: (readingText as NSString).length))
            .first { NSLocationInRange(character, $0.range) }?.range
    }

    private func showWord(_ range: NSRange) {
        guard range.location != NSNotFound,
              let layoutManager, let textContainer else { return }
        let source = readingText as NSString
        let range = NSIntersectionRange(range, NSRange(location: 0, length: source.length))
        guard range.length > 0 else { return }
        let word = source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= 70 else { return }
        dismissDefinition()
        drawMark(at: range)
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var firstLine = NSRange()
        _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: &firstLine)
        let anchorGlyphs = NSIntersectionRange(glyphs, firstLine)
        let anchor = layoutManager.boundingRect(forGlyphRange: anchorGlyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let panel = NSPopover()
        // Keep the app's definition open while AppKit presents a second lookup popover.
        panel.behavior = .applicationDefined
        panel.delegate = self
        panel.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let size = WordDefinitionView.size(on: window?.screen)
        let definition = WordDefinitionView(
            word: word,
            entry: SystemDictionary.lookup(word, in: readingText, at: range),
            showSystem: { [weak self] in
                self?.showDefinition(for: nil, range: range, options: [.presentationType: NSView.DefinitionPresentationType.overlay])
            },
            close: { [weak panel] in panel?.close() }
        )
        .frame(width: size.width, height: size.height)
        .environment(\.presentSystemLookup) { [weak self] text, screenPoint in
            guard let host = self?.window?.contentView else { return }
            guard let hostWindow = host.window else { return }
            let windowPoint = hostWindow.convertPoint(fromScreen: screenPoint)
            let point = host.convert(windowPoint, from: nil)
            let visible = host.visibleRect.insetBy(dx: 8, dy: 8)
            let baseline = NSPoint(x: min(max(point.x, visible.minX), visible.maxX),
                                   y: min(max(point.y, visible.minY), visible.maxY))
            // AppKit's Look Up popover must be presented from the reading window.
            host.showDefinition(for: text, range: NSRange(location: 0, length: text.length),
                                options: [.presentationType: NSView.DefinitionPresentationType.overlay]) { _ in baseline }
        }
        let controller = NSHostingController(rootView: definition)
        // Resizing a visible popover makes AppKit choose its anchor position again.
        controller.sizingOptions = []
        panel.contentViewController = controller
        panel.contentSize = size
        definitionPopover = panel
        panel.show(relativeTo: anchor, of: self, preferredEdge: .minY)
        if panel.isShown, let readingWindow = window {
            definitionDismissalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak readingWindow] event in
                if let readingWindow, event.window === readingWindow { self?.dismissDefinition() }
                return event
            }
        }
        onLookup(word)
    }
}
