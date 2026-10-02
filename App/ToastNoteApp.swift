import SwiftUI

@main
struct ToastNoteApp: App {
    @State private var model = AppModel()
    @State private var formatController = FormatController()
    @State private var updates = UpdateController()

    var body: some Scene {
        WindowGroup {
            MainWindow(model: model, formatController: formatController)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { AppCommands(model: model, formatController: formatController, updates: updates) }

        Settings {
            SettingsWindow(model: model, controller: formatController, updates: updates)
        }
    }
}
