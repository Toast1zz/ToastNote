import AppKit
import SwiftUI
import VaultKit

/// Temporary plain-text editor; replaced by the live-preview editor in Task 15.
struct PlainEditorView: NSViewRepresentable {
    let session: NoteSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 15)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 48, height: 24)
        textView.drawsBackground = false
        textView.string = session.text
        textView.isEditable = session.loadError == nil
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = session.loadError == nil
        if textView.string != session.text {
            let selection = textView.selectedRange()
            context.coordinator.isApplyingExternalText = true
            textView.string = session.text
            context.coordinator.isApplyingExternalText = false
            let length = (session.text as NSString).length
            if NSMaxRange(selection) <= length { textView.setSelectedRange(selection) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: NoteSession
        var isApplyingExternalText = false

        init(session: NoteSession) { self.session = session }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView else { return }
            session.userEdited(textView.string)
        }
    }
}
