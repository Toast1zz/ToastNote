import SwiftUI

/// The ⌘, window (spec §10.8): 通用 / 编辑器 / AI / 更新.
struct SettingsWindow: View {
    let model: AppModel
    let controller: FormatController
    let updates: UpdateController

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("通用", systemImage: "gearshape") }
            EditorSettingsView()
                .tabItem { Label("编辑器", systemImage: "textformat") }
            AISettingsView(controller: controller)
                .tabItem { Label("AI", systemImage: "wand.and.stars") }
            UpdateSettingsView(updates: updates)
                .tabItem { Label("更新", systemImage: "arrow.triangle.2.circlepath") }
        }
        .scenePadding()
    }
}
