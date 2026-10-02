import SwiftUI

@main
struct ToastNoteApp: App {
    @State private var model = AppModel()
    @State private var formatController = FormatController()

    var body: some Scene {
        WindowGroup {
            MainWindow(model: model, formatController: formatController)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { AppCommands(model: model, formatController: formatController) }

        Settings {
            SettingsWindow(controller: formatController)
        }
    }
}
