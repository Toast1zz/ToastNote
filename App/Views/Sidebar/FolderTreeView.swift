import SwiftUI
import VaultKit

struct FolderTreeView: View {
    @Bindable var model: AppModel

    private struct Row: Identifiable {
        var id: String { path }
        let path: String
        let name: String
        let isFolder: Bool
        let depth: Int
    }

    private var rows: [Row] {
        var result: [Row] = []
        func walk(_ node: FolderNode, depth: Int) {
            for folder in node.folders {
                result.append(Row(path: folder.path, name: folder.name, isFolder: true, depth: depth))
                if model.expandedFolders.contains(folder.path) { walk(folder, depth: depth + 1) }
            }
            for note in node.notes {
                result.append(Row(path: note.path, name: note.title, isFolder: false, depth: depth))
            }
        }
        walk(model.tree, depth: 0)
        return result
    }

    var body: some View {
        List(selection: $model.selection) {
            ForEach(rows) { row in
                rowView(row)
                    .tag(row.path)
                    .contextMenu { menu(for: row) }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.selection) { _, new in
            guard let new else { return }
            guard let row = rows.first(where: { $0.path == new }) else { return }
            if row.isFolder { toggle(row.path) } else { model.open(path: new) }
        }
        .contextMenu {
            Button("新建笔记") { model.newNote(inFolder: "") }
            Button("新建文件夹") { model.newFolder(inFolder: "") }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 4) {
            if row.isFolder {
                Button { toggle(row.path) } label: {
                    Image(systemName: model.expandedFolders.contains(row.path) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.expandedFolders.contains(row.path) ? "折叠" : "展开")
                Label(row.name, systemImage: "folder")
            } else {
                Text(row.name).lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.leading, CGFloat(row.depth) * 14 + (row.isFolder ? 0 : 16))
        .help(row.path)
    }

    @ViewBuilder
    private func menu(for row: Row) -> some View {
        let folder = row.isFolder ? row.path : (row.path as NSString).deletingLastPathComponent
        Button("新建笔记") { model.newNote(inFolder: folder) }
        Button("新建文件夹") { model.newFolder(inFolder: folder) }
        Divider()
        Button("重命名") { model.rename(path: row.path) }
        Button("移到废纸篓") { model.trash(path: row.path) }
    }

    private func toggle(_ path: String) {
        if model.expandedFolders.contains(path) {
            model.expandedFolders.remove(path)
        } else {
            model.expandedFolders.insert(path)
        }
    }
}
