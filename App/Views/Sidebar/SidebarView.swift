import SwiftUI
import VaultKit

/// Arc-style sidebar: 置顶 / 已打开 / 文件夹 / 标签 (spec §10.1), built from system list rows so row height,
/// insets, disclosure triangles, badges and selection follow macOS (and the user's sidebar size setting).
struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SidebarSearchField(model: model)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 10)
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
        return List(selection: selection) {
            // Like Pinned in Apple Notes, the section only exists while something is pinned.
            if !model.workspace.pinned.isEmpty {
                SidebarSection(title: "置顶", model: model) {
                    ForEach(model.workspace.pinned, id: \.self) { path in
                        NoteRow(path: path, title: titles[path] ?? path)
                            .contextMenu { SidebarMenus.note(path, pinned: true, open: false, model: model) }
                            .dropDestination(for: String.self) { paths, _ in pinAll(paths) }
                            .tag(SidebarRowID.pinned + path)
                    }
                }
            }
            if !model.workspace.open.isEmpty {
                SidebarSection(title: "已打开", model: model) {
                    ForEach(model.workspace.open, id: \.self) { path in
                        NoteRow(path: path, title: titles[path] ?? path, showsCloseButton: true) {
                            model.close(path: path)
                        }
                        .draggable(path)
                        .contextMenu { SidebarMenus.note(path, pinned: false, open: true, model: model) }
                        .tag(SidebarRowID.open + path)
                    }
                    .onMove { model.moveOpen(from: $0, to: $1) }
                }
            }
            SidebarSection(title: "文件夹", model: model) {
                FolderBranch(node: model.tree, model: model)
            }
            SidebarSection(title: "标签", model: model) {
                TagsSection(model: model)
            }
        }
        .listStyle(.sidebar)
        .contextMenu {
            Button("新建笔记") { model.newNote(inFolder: "") }
            Button("新建文件夹") { model.newFolder(inFolder: "") }
        }
    }

    /// The list highlights the row the current note is shown in (置顶 or 已打开, else the tree); choosing a row
    /// opens the note, selects and expands a folder, or lists a tag's notes.
    private var selection: Binding<String?> {
        Binding(
            get: {
                guard let path = model.selection else { return nil }
                if model.workspace.pinned.contains(path) { return SidebarRowID.pinned + path }
                if model.workspace.open.contains(path) { return SidebarRowID.open + path }
                return SidebarRowID.tree + path
            },
            set: { id in
                guard let id, let (prefix, value) = SidebarRowID.split(id) else { return }
                if prefix == SidebarRowID.tag {
                    model.selectTag(value)
                } else if value.hasSuffix(".md") || value.hasSuffix(".markdown") {
                    model.selection = value
                    model.open(path: value)
                } else {
                    model.selection = value
                    if model.expandedFolders.contains(value) {
                        model.expandedFolders.remove(value)
                    } else {
                        model.expandedFolders.insert(value)
                    }
                }
            }
        )
    }

    private func pinAll(_ paths: [String]) -> Bool {
        paths.forEach { model.pin(path: $0) }
        return !paths.isEmpty
    }
}
