import IndexKit
import SwiftUI

/// The search field at the top of the sidebar (⌘⇧F focuses it; Esc or the clear button leaves search).
struct SidebarSearchField: View {
    @Bindable var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("搜索笔记")
                .onKeyPress(.escape) {
                    model.clearSearch()
                    isFocused = false
                    return .handled
                }
            if !model.searchText.isEmpty {
                Button { model.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .help("搜索所有笔记（⌘⇧F）")
        .onChange(of: model.searchFocusToken) { _, _ in isFocused = true }
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
            List(model.searchResults, id: \.path) { hit in
                Button { model.openSearchResult(hit) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title).lineLimit(1)
                        Text(Self.highlighted(hit.snippet))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(hit.path)
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
