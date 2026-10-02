import SwiftUI
import VaultKit

/// After a tag is clicked the sidebar lists that tag's notes under a "#标签名" header with a back button (spec §10.3).
struct TagNotesList: View {
    let model: AppModel
    let tag: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { model.selectTag(nil) } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("返回侧边栏")
                Spacer()
                Text("#" + tag).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            if model.tagNotes.isEmpty {
                Text("没有带这个标签的笔记")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.tagNotes, id: \.path) { note in
                    Button { model.open(path: note.path) } label: {
                        NoteRow(path: note.path, title: note.title)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
    }
}
