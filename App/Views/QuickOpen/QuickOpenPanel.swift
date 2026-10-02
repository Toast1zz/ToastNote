import SwiftUI
import VaultKit

/// ⌘P: a floating, top-centered fuzzy finder over note titles and paths (spec §10.2).
struct QuickOpenPanel: View {
    let model: AppModel
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private enum Row: Identifiable {
        case note(NoteRef)
        case create(String)

        var id: String {
            switch self {
            case .note(let note): note.path
            case .create(let title): "create:" + title
            }
        }
    }

    private var rows: [Row] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return suggestedNotes.map(Row.note) }
        let matches = FuzzyMatcher.rank(query: trimmed, candidates: model.tree.allNotes(), limit: 50)
        return matches.isEmpty ? [.create(trimmed)] : matches.map(Row.note)
    }

    /// For an empty query: recently opened notes, then the open tabs, so the list is never blank.
    private var suggestedNotes: [NoteRef] {
        var notes = model.recentNotes()
        let known = Dictionary(model.tree.allNotes().map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        for path in model.workspace.open where !notes.contains(where: { $0.path == path }) {
            if let note = known[path] { notes.append(note) }
        }
        return Array(notes.prefix(10))
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("按标题或路径搜索笔记", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($fieldFocused)
                    .onSubmit { activate(rows) }
                    .accessibilityLabel("快速打开")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            if !rows.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("最近")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 4)
                                    .padding(.bottom, 4)
                            }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                rowView(row, isHighlighted: index == highlighted)
                                    .id(index)
                                    .onTapGesture { highlighted = index; activate(rows) }
                            }
                        }
                        .padding(6)
                    }
                    // A scroll view takes all the height it is offered; size it to its rows instead.
                    .frame(height: min(CGFloat(rows.count) * 32 + 12 + (query.trimmingCharacters(in: .whitespaces).isEmpty ? 22 : 0), 340))
                    .onChange(of: highlighted) { _, new in proxy.scrollTo(new) }
                }
            }
        }
        .frame(width: 560)
        .glassSurface(cornerRadius: 14)
        .floatingShadow()
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(rows.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            model.isQuickOpenPresented = false
            return .handled
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            switch row {
            case .note(let note):
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(note.title).lineLimit(1)
                Text((note.path as NSString).deletingLastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            case .create(let title):
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text("新建笔记“\(title)”").lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
    }

    private func activate(_ rows: [Row]) {
        guard rows.indices.contains(highlighted) else { return }
        switch rows[highlighted] {
        case .note(let note): model.open(path: note.path)
        case .create(let title): model.createNote(titled: title)
        }
        model.isQuickOpenPresented = false
    }
}
