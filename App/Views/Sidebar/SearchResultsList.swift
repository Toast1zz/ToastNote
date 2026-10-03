import AppKit
import IndexKit
import SwiftUI

/// The search field at the top of the sidebar: a system `NSSearchField` (magnifier, clear button, Esc to
/// leave). ⌘⇧F focuses it.
struct SidebarSearchField: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "搜索"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.toolTip = "搜索所有笔记（⌘⇧F）"
        field.setAccessibilityLabel("搜索笔记")
        context.coordinator.focusToken = model.searchFocusToken
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.model = model
        if field.stringValue != model.searchText { field.stringValue = model.searchText }
        if context.coordinator.focusToken != model.searchFocusToken {
            context.coordinator.focusToken = model.searchFocusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var model: AppModel
        var focusToken = 0

        init(model: AppModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            model.searchText = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            model.clearSearch()
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// Results replace the sidebar sections while the search field has text (spec §10.4).
struct SearchResultsList: View {
    let model: AppModel

    var body: some View {
        if model.searchResults.isEmpty {
            Text("没有找到匹配的笔记")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(model.searchResults, id: \.path) { hit in
                        Button { model.openSearchResult(hit) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hit.title).fontWeight(.medium).lineLimit(1)
                                Text(Self.highlighted(hit.snippet))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(hit.path)
                    }
                } header: {
                    Text("\(model.searchResults.count) 篇笔记")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// Text between "[" and "]" is the match: bold, in the accent color.
    static func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var inMatch = false
        for piece in snippet.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "[" || $0 == "]" }) {
            var part = AttributedString(String(piece))
            if inMatch {
                part.font = .callout.bold()
                part.foregroundColor = .accentColor
            }
            result += part
            inMatch.toggle()
        }
        return result
    }
}
