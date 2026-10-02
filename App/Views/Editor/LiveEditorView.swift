import AppKit
import EditorKit
import SwiftUI
import VaultKit

/// Hosts the live-preview `MarkdownTextView` for one `NoteSession`.
struct LiveEditorView: NSViewRepresentable {
    let session: NoteSession
    let theme: EditorTheme
    /// Reports the hosted text view (or nil on teardown) so commands, AI and search can reach it.
    var onTextViewChange: (MarkdownTextView?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(theme: theme)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.markdown = session.text
        textView.isEditable = session.loadError == nil
        textView.onTextChange = { [session] text in session.userEdited(text) }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        context.coordinator.textView = textView
        // New and freshly opened notes take the keyboard with the caret at the start.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            onTextViewChange(textView)
            LaunchTiming.editorReady()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.isEditable = session.loadError == nil
        if textView.theme.bodySize != theme.bodySize || textView.theme.maxContentWidth != theme.maxContentWidth {
            textView.theme = theme
        }
        guard textView.string != session.text else { return }
        // An external reload: keep the caret and scroll position when they still make sense.
        let selection = textView.selectedRange()
        let scrollOrigin = scrollView.contentView.bounds.origin
        textView.markdown = session.text
        let length = (session.text as NSString).length
        if NSMaxRange(selection) <= length { textView.setSelectedRange(selection) }
        scrollView.contentView.scroll(to: scrollOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.textView?.onTextChange = nil
    }

    final class Coordinator {
        weak var textView: MarkdownTextView?
    }
}
