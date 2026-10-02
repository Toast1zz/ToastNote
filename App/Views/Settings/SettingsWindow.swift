import SwiftUI

/// The ⌘, window (spec §10.8). Pages are added as they are built.
struct SettingsWindow: View {
    let controller: FormatController

    var body: some View {
        TabView {
            AISettingsView(controller: controller)
                .tabItem { Label("AI", systemImage: "wand.and.stars") }
        }
        .scenePadding()
    }
}
