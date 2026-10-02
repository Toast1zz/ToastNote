import SwiftUI

/// One grid for every sidebar row, so left edges and heights agree across sections:
///
///     [indent × depth][disclosure 14][icon 18][gap 6] title ………… trailing
///
/// Folders and tags fill all columns. A note inside the tree leaves the disclosure and icon columns empty, so
/// its title starts exactly where its sibling folders' titles start. Sections that hold only notes (置顶, 已打开)
/// start their titles at the section header's left edge.
enum SidebarMetrics {
    static let rowHeight: CGFloat = 28
    static let indent: CGFloat = 14
    static let disclosureWidth: CGFloat = 14
    static let iconWidth: CGFloat = 18
    static let gap: CGFloat = 6
}

/// A row of the folder tree or the tag list.
struct SidebarTreeRow<Trailing: View>: View {
    enum Leading {
        /// A note: empty disclosure and icon columns.
        case none
        case folder(isExpanded: Bool, toggle: () -> Void)
        /// A tag, with a disclosure only when it has child tags.
        case tag(hasChildren: Bool, isExpanded: Bool, toggle: () -> Void)
    }

    let depth: Int
    let leading: Leading
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(depth) * SidebarMetrics.indent)
            disclosure.frame(width: SidebarMetrics.disclosureWidth)
            icon.frame(width: SidebarMetrics.iconWidth)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, SidebarMetrics.gap)
            Spacer(minLength: 4)
            trailing()
        }
        .frame(height: SidebarMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var disclosure: some View {
        switch leading {
        case .folder(let isExpanded, let toggle), .tag(true, let isExpanded, let toggle):
            Button(action: toggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.disclosureWidth, height: SidebarMetrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "折叠" : "展开")
        default:
            Color.clear
        }
    }

    @ViewBuilder private var icon: some View {
        switch leading {
        case .folder:
            Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(Color.accentColor)
        case .tag:
            Image(systemName: "number").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        case .none:
            Color.clear
        }
    }
}
