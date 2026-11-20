import AppKit
import SwiftUI

private struct SystemLookupPresenterKey: EnvironmentKey {
    static let defaultValue: ((NSAttributedString, NSPoint) -> Void)? = nil
}

extension EnvironmentValues {
    var presentSystemLookup: ((NSAttributedString, NSPoint) -> Void)? {
        get { self[SystemLookupPresenterKey.self] }
        set { self[SystemLookupPresenterKey.self] = newValue }
    }
}

struct LookupText: NSViewRepresentable {
    let text: String
    var size: CGFloat = 13
    var weight: NSFont.Weight = .regular
    var secondary = false
    var annotation: String?
    var lineSpacing: CGFloat = 2

    @Environment(\.presentSystemLookup) private var presentSystemLookup

    func makeNSView(context: Context) -> LookupTextView {
        let view = LookupTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        return view
    }

    func updateNSView(_ view: LookupTextView, context: Context) {
        view.presentSystemLookup = presentSystemLookup
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let content = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        if let annotation {
            content.append(NSAttributedString(string: "  " + annotation, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]))
        }
        if let storage = view.textStorage, !storage.isEqual(to: content) {
            storage.setAttributedString(content)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: LookupTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite,
              let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }
}

final class LookupTextView: NSTextView {
    var presentSystemLookup: ((NSAttributedString, NSPoint) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let range = lookupRange(at: event.locationInWindow)
        let menu = super.menu(for: event) ?? NSMenu()
        guard let range else { return menu }
        let word = (string as NSString).substring(with: range)
        let title = String(localized: "查询“\(word)”")
        let item = NSMenuItem(title: title, action: #selector(lookUpFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = NSValue(range: range)
        menu.insertItem(item, at: 0)
        return menu
    }

    override func quickLook(with event: NSEvent) {
        guard let range = lookupRange(at: event.locationInWindow) else {
            super.quickLook(with: event)
            return
        }
        showSystemLookup(for: range)
    }

    @objc private func lookUpFromMenu(_ item: NSMenuItem) {
        guard let range = (item.representedObject as? NSValue)?.rangeValue else { return }
        DispatchQueue.main.async { [weak self] in self?.showSystemLookup(for: range) }
    }

    private func showSystemLookup(for range: NSRange) {
        guard let presentSystemLookup, let textStorage, NSMaxRange(range) <= textStorage.length,
              let window, let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let offset = layoutManager.location(forGlyphAt: glyph)
        let baseline = NSPoint(x: textContainerOrigin.x + line.minX + offset.x,
                               y: textContainerOrigin.y + line.minY + offset.y)
        let point = window.convertPoint(toScreen: convert(baseline, to: nil))
        presentSystemLookup(textStorage.attributedSubstring(from: range), point)
    }

    private func lookupRange(at windowPoint: NSPoint) -> NSRange? {
        guard let layoutManager, let textContainer, !string.isEmpty else { return nil }
        let local = convert(windowPoint, from: nil)
        let point = NSPoint(x: local.x - textContainerOrigin.x, y: local.y - textContainerOrigin.y)
        layoutManager.ensureLayout(for: textContainer)
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
                .contains(point) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        let selection = selectedRange()
        let range = NSLocationInRange(index, selection) ? selection : selectionRange(
            forProposedRange: NSRange(location: index, length: 0), granularity: .selectByWord
        )
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length,
              (string as NSString).substring(with: range).rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        return range
    }
}
