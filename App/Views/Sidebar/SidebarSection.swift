import SwiftUI

/// A collapsible sidebar section. The header uses the system sidebar style (its disclosure chevron appears on
/// hover); the collapsed state lives in the model so it survives relaunches.
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
        }
    }
}
