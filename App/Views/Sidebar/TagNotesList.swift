import SwiftUI
import VaultKit

/// After a tag is chosen the sidebar lists that tag's notes under a "#标签名" section header with a back button
/// (spec §10.3). Rows are the same note rows as everywhere else in the sidebar.
struct TagNotesList: View {
    let model: AppModel
    let tag: String

    var body: some View {
        List(selection: Binding<String?>(
            get: { model.selection },
            set: { path in
                guard let path else { return }
                model.selection = path
                model.open(path: path)
            }
        )) {
            Section {
                if model.tagNotes.isEmpty {
                    Text("没有带这个标签的笔记")
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                ForEach(model.tagNotes, id: \.path) { note in
                    NoteRow(path: note.path, title: note.title)
                        .contextMenu {
                            SidebarMenus.note(note.path, pinned: model.workspace.pinned.contains(note.path), open: false, model: model)
                        }
                        .tag(note.path)
                }
            } header: {
                HStack(spacing: 6) {
                    Button { model.selectTag(nil) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .help("返回")
                    .accessibilityLabel("返回")
                    Text("#" + tag)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
