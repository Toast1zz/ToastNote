import SwiftUI

/// A note in the sidebar: title only, no icon (spec §1.2.3). Rows are 28 pt high; rows in the open list
/// show a close button while hovered (spec §9.5).
struct NoteRow: View {
    let path: String
    let title: String
    var showsCloseButton = false
    var onClose: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if showsCloseButton, isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭标签页")
                .accessibilityLabel("关闭 \(title)")
            }
        }
        .frame(height: SidebarMetrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(path)
    }
}
