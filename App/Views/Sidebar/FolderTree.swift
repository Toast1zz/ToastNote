import SwiftUI
import VaultKit

/// Row identifiers in the sidebar list. One note can appear in 置顶 or 已打开 and again in the folder tree; each
/// appearance needs its own identifier so only the row the user is looking at is highlighted.
enum SidebarRowID {
    static let pinned = "pin:"
    static let open = "open:"
    static let tree = "tree:"
    static let tag = "tag:"

    /// Splits an identifier into its section prefix and the path or tag after it.
    static func split(_ id: String) -> (prefix: String, value: String)? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        return (String(id[...colon]), String(id[id.index(after: colon)...]))
    }
}

/// One level of the folder tree: folders as native disclosure rows (folder symbol), then notes (title only).
struct FolderBranch: View {
    let node: FolderNode
    let model: AppModel

    var body: some View {
        ForEach(node.folders, id: \.path) { folder in
            DisclosureGroup(isExpanded: expansion(of: folder.path)) {
                FolderBranch(node: folder, model: model)
            } label: {
                Label(folder.name, systemImage: "folder")
                    .lineLimit(1)
                    .help(folder.path)
                    .draggable(folder.path)
                    .contextMenu { SidebarMenus.folder(folder.path, model: model) }
            }
            .tag(SidebarRowID.tree + folder.path)
        }
        ForEach(node.notes, id: \.path) { note in
            NoteRow(path: note.path, title: note.title)
                .draggable(note.path)
                .contextMenu { SidebarMenus.treeNote(note.path, model: model) }
                .tag(SidebarRowID.tree + note.path)
        }
    }

    private func expansion(of path: String) -> Binding<Bool> {
        Binding(
            get: { model.expandedFolders.contains(path) },
            set: { expanded in
                if expanded { model.expandedFolders.insert(path) } else { model.expandedFolders.remove(path) }
            }
        )
    }
}

/// Context menus shared by the sidebar sections.
@MainActor
enum SidebarMenus {
    @ViewBuilder
    static func note(_ path: String, pinned: Bool, open: Bool, model: AppModel) -> some View {
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
    static func treeNote(_ path: String, model: AppModel) -> some View {
        Button("新建笔记") { model.newNote(inFolder: (path as NSString).deletingLastPathComponent) }
        Divider()
        note(path, pinned: model.workspace.pinned.contains(path), open: false, model: model)
    }

    @ViewBuilder
    static func folder(_ path: String, model: AppModel) -> some View {
        Button("新建笔记") { model.newNote(inFolder: path) }
        Button("新建文件夹") { model.newFolder(inFolder: path) }
        Divider()
        Button("在访达中显示") { model.revealInFinder(path: path) }
        Button("重命名") { model.rename(path: path) }
        Button("移到废纸篓") { model.trash(path: path) }
    }
}
