import SwiftUI
import VaultKit

/// Arc-style sidebar: 置顶 / 已打开 / 文件夹 / 标签 (spec §10.1).
struct SidebarView: View {
    @Bindable var model: AppModel

    private struct FolderRow: Identifiable {
        var id: String { path }
        let path: String
        let name: String
        let isFolder: Bool
        let depth: Int
    }

    private var folderRows: [FolderRow] {
        var result: [FolderRow] = []
        func walk(_ node: FolderNode, depth: Int) {
            for folder in node.folders {
                result.append(FolderRow(path: folder.path, name: folder.name, isFolder: true, depth: depth))
                if model.expandedFolders.contains(folder.path) { walk(folder, depth: depth + 1) }
            }
            for note in node.notes {
                result.append(FolderRow(path: note.path, name: note.title, isFolder: false, depth: depth))
            }
        }
        walk(model.tree, depth: 0)
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarSearchField(model: model)
            if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                SearchResultsList(model: model)
            } else if let tag = model.selectedTag {
                TagNotesList(model: model, tag: tag)
            } else {
                sectionsList
            }
        }
    }

    private var sectionsList: some View {
        let titles = model.workspace.displayTitles()
        return List(selection: $model.selection) {
            SidebarSection(title: "置顶", model: model) {
                if model.workspace.pinned.isEmpty {
                    Text("拖入笔记以置顶")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(height: SidebarMetrics.rowHeight)
                        .selectionDisabled()
                        .dropDestination(for: String.self) { paths, _ in pinAll(paths) }
                }
                ForEach(model.workspace.pinned, id: \.self) { path in
                    NoteRow(path: path, title: titles[path] ?? path)
                        .tag(path)
                        .contextMenu { noteMenu(path: path, pinned: true, open: false) }
                        .dropDestination(for: String.self) { paths, _ in pinAll(paths) }
                }
            }
            SidebarSection(title: "已打开", model: model) {
                ForEach(model.workspace.open, id: \.self) { path in
                    NoteRow(path: path, title: titles[path] ?? path, showsCloseButton: true) {
                        model.close(path: path)
                    }
                    .tag(path)
                    .draggable(path)
                    .contextMenu { noteMenu(path: path, pinned: false, open: true) }
                }
                .onMove { model.moveOpen(from: $0, to: $1) }
            }
            SidebarSection(title: "文件夹", model: model) {
                ForEach(folderRows) { row in
                    folderRowView(row)
                        .tag(row.path)
                        .contextMenu { folderMenu(row) }
                }
            }
            SidebarSection(title: "标签", model: model) {
                TagsSection(model: model)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.selection) { _, new in
            guard let new else { return }
            if let row = folderRows.first(where: { $0.path == new }), row.isFolder {
                toggle(row.path)
            } else if new.hasSuffix(".md") || new.hasSuffix(".markdown") {
                model.open(path: new)
            }
        }
        .contextMenu {
            Button("新建笔记") { model.newNote(inFolder: "") }
            Button("新建文件夹") { model.newFolder(inFolder: "") }
        }
    }

    private func pinAll(_ paths: [String]) -> Bool {
        paths.forEach { model.pin(path: $0) }
        return !paths.isEmpty
    }

    // MARK: Folder tree rows

    @ViewBuilder
    private func folderRowView(_ row: FolderRow) -> some View {
        SidebarTreeRow(
            depth: row.depth,
            leading: row.isFolder ? .folder(isExpanded: model.expandedFolders.contains(row.path)) { toggle(row.path) } : .none,
            title: row.name
        ) { EmptyView() }
        .draggable(row.path)
        .help(row.path)
    }

    private func toggle(_ path: String) {
        if model.expandedFolders.contains(path) {
            model.expandedFolders.remove(path)
        } else {
            model.expandedFolders.insert(path)
        }
    }

    // MARK: Context menus

    @ViewBuilder
    private func noteMenu(path: String, pinned: Bool, open: Bool) -> some View {
        if pinned {
            Button("取消置顶") { model.unpin(path: path) }
        } else {
            Button("置顶") { model.pin(path: path) }
        }
        if open { Button("关闭标签页") { model.close(path: path) } }
        Divider()
        Button("在访达中显示") { model.revealInFinder(path: path) }
        Button("重命名") { model.rename(path: path) }
        Button("移到废纸篓") { model.trash(path: path) }
    }

    @ViewBuilder
    private func folderMenu(_ row: FolderRow) -> some View {
        let folder = row.isFolder ? row.path : (row.path as NSString).deletingLastPathComponent
        Button("新建笔记") { model.newNote(inFolder: folder) }
        Button("新建文件夹") { model.newFolder(inFolder: folder) }
        Divider()
        if !row.isFolder {
            if model.workspace.pinned.contains(row.path) {
                Button("取消置顶") { model.unpin(path: row.path) }
            } else {
                Button("置顶") { model.pin(path: row.path) }
            }
        }
        Button("在访达中显示") { model.revealInFinder(path: row.path) }
        Button("重命名") { model.rename(path: row.path) }
        Button("移到废纸篓") { model.trash(path: row.path) }
    }
}
