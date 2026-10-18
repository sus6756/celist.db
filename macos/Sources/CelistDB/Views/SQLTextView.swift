import SwiftUI
import AppKit

/// A text view that highlights SQL as you type. `TextEditor` cannot render
/// attributed content, so this wraps an `NSTextView` and re-applies token
/// colours from `SQLSyntax` on every edit (attribute-only changes don't
/// re-enter `textDidChange`, so there is no feedback loop).
struct SQLTextView: NSViewRepresentable {
    @Binding var text: String
    var dark: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .white
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.highlight(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            context.coordinator.highlight(textView)
            let location = min(selection.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLTextView
        weak var textView: NSTextView?

        init(_ parent: SQLTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(textView)
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let attributed = SQLSyntax.nsAttributedString(textView.string, dark: parent.dark)
            let selection = textView.selectedRange()
            storage.beginEditing()
            storage.setAttributedString(attributed)
            storage.endEditing()
            textView.setSelectedRange(selection)
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(HighlightPalette.forScheme(parent.dark).plain),
            ]
        }
    }
}

extension SQLSyntax {
    /// Builds an AppKit-attributed string with the palette applied, used by
    /// the SQL editor. Ranges are derived by walking the source in token order
    /// (tokens partition the input exactly).
    static func nsAttributedString(_ source: String, dark: Bool) -> NSAttributedString {
        let palette = HighlightPalette.forScheme(dark)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let result = NSMutableAttributedString(
            string: source,
            attributes: [.font: font, .foregroundColor: NSColor(palette.plain)]
        )
        var index = source.startIndex
        for token in tokens(in: source, palette: palette) {
            guard let end = source.index(index, offsetBy: token.text.count, limitedBy: source.endIndex) else { break }
            let range = NSRange(index..<end, in: source)
            result.addAttribute(.foregroundColor, value: nsColor(palette, token.kind), range: range)
            index = end
        }
        return result
    }

    private static func nsColor(_ palette: HighlightPalette, _ kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword: return NSColor(palette.keyword)
        case .string: return NSColor(palette.string)
        case .number: return NSColor(palette.number)
        case .comment: return NSColor(palette.comment)
        case .identifier: return NSColor(palette.identifier)
        case .punctuation: return NSColor(palette.punctuation)
        case .plain: return NSColor(palette.plain)
        }
    }
}
