import SwiftUI

/// A note in the sidebar: a `doc.text` label like every other sidebar row, so icons share one column and
/// titles another (Finder, Mail and Notes sidebars all work this way). Rows in the open list show a close
/// button while hovered (spec §9.5); the system sets the row height.
struct NoteRow: View {
    let path: String
    let title: String
    var showsCloseButton = false
    var onClose: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Label(title, systemImage: "doc.text")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if showsCloseButton, isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭标签页")
                .accessibilityLabel("关闭 \(title)")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(path)
    }
}
