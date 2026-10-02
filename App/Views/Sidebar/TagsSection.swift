import IndexKit
import SwiftUI

/// Rows of the 标签 section: nested tags with disclosure, a `number` symbol, the name and the note count.
struct TagsSection: View {
    @Bindable var model: AppModel

    private struct Row: Identifiable {
        var id: String { tag }
        let tag: String
        let leaf: String
        let count: Int
        let depth: Int
        let hasChildren: Bool
    }

    private var rows: [Row] {
        let all = model.tagCounts
        var result: [Row] = []
        func children(of parent: String?) -> [TagCount] {
            all.filter { entry in
                let parts = entry.tag.split(separator: "/").map(String.init)
                if let parent { return entry.tag.hasPrefix(parent + "/") && parts.count == parent.split(separator: "/").count + 1 }
                return parts.count == 1
            }
        }
        func walk(_ parent: String?, depth: Int) {
            for entry in children(of: parent) {
                let kids = children(of: entry.tag)
                result.append(Row(
                    tag: entry.tag, leaf: String(entry.tag.split(separator: "/").last ?? ""), count: entry.count,
                    depth: depth, hasChildren: !kids.isEmpty
                ))
                if model.expandedTags.contains(entry.tag) { walk(entry.tag, depth: depth + 1) }
            }
        }
        walk(nil, depth: 0)
        return result
    }

    var body: some View {
        if model.tagCounts.isEmpty {
            Text("暂无标签")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(height: 28)
                .selectionDisabled()
        } else {
            ForEach(rows) { row in
                HStack(spacing: 4) {
                    if row.hasChildren {
                        Button { toggle(row.tag) } label: {
                            Image(systemName: model.expandedTags.contains(row.tag) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.expandedTags.contains(row.tag) ? "折叠" : "展开")
                    } else {
                        Color.clear.frame(width: 12)
                    }
                    Button { model.selectTag(row.tag) } label: {
                        HStack(spacing: 4) {
                            Label(row.leaf, systemImage: "number").lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(row.count)").foregroundStyle(.secondary).font(.callout)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("#" + row.tag)
                }
                .frame(height: 28)
                .padding(.leading, CGFloat(row.depth) * 14)
                .selectionDisabled()
            }
        }
    }

    private func toggle(_ tag: String) {
        if model.expandedTags.contains(tag) { model.expandedTags.remove(tag) } else { model.expandedTags.insert(tag) }
    }
}
