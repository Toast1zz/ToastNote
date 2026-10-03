import IndexKit
import SwiftUI

/// Rows of the 标签 section: the `number` symbol, the tag name and the note count as a system badge. Nested
/// tags (`#工作/周报`) are native disclosure rows. Selecting a tag lists its notes (spec §10.3).
struct TagsSection: View {
    let model: AppModel

    var body: some View {
        if model.tagCounts.isEmpty {
            Text("暂无标签")
                .foregroundStyle(.tertiary)
                .selectionDisabled()
        } else {
            TagBranch(parent: nil, model: model)
        }
    }
}

private struct TagBranch: View {
    let parent: String?
    let model: AppModel

    private var children: [TagCount] {
        let depth = parent.map { $0.split(separator: "/").count + 1 } ?? 1
        return model.tagCounts.filter { entry in
            guard entry.tag.split(separator: "/").count == depth else { return false }
            return parent.map { entry.tag.hasPrefix($0 + "/") } ?? true
        }
    }

    var body: some View {
        ForEach(children, id: \.tag) { entry in
            if model.tagCounts.contains(where: { $0.tag.hasPrefix(entry.tag + "/") }) {
                DisclosureGroup(isExpanded: expansion(of: entry.tag)) {
                    TagBranch(parent: entry.tag, model: model)
                } label: {
                    row(entry)
                }
                .tag(SidebarRowID.tag + entry.tag)
            } else {
                row(entry).tag(SidebarRowID.tag + entry.tag)
            }
        }
    }

    private func row(_ entry: TagCount) -> some View {
        Label(String(entry.tag.split(separator: "/").last ?? ""), systemImage: "number")
            .lineLimit(1)
            .badge(entry.count)
            .help("#" + entry.tag)
    }

    private func expansion(of tag: String) -> Binding<Bool> {
        Binding(
            get: { model.expandedTags.contains(tag) },
            set: { expanded in
                if expanded { model.expandedTags.insert(tag) } else { model.expandedTags.remove(tag) }
            }
        )
    }
}
