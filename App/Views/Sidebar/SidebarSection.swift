import SwiftUI

/// A collapsible sidebar section with the header style of spec §9.5: 11 pt semibold, secondary color,
/// no divider. The collapsed state lives in the model so it survives relaunches.
struct SidebarSection<Content: View>: View {
    let title: String
    let model: AppModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section(isExpanded: Binding(
            get: { !model.collapsedSections.contains(title) },
            set: { _ in model.toggleSection(title) }
        )) {
            content()
        } header: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                // List rows are inset 2 pt further than section headers; this puts both on one edge.
                .padding(.leading, 2)
        }
    }
}
