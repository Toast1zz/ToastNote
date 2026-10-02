import SwiftUI

/// A strip above the editor with a message and optional buttons: external-change notices, errors, hints.
struct EditorBanner: View {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let perform: () -> Void
    }

    let message: String
    var actions: [Action] = []

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
            Spacer()
            ForEach(actions) { action in
                Button(action.title, action: action.perform)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}
