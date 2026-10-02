import SwiftUI

@main
struct ToastNoteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindow(model: model)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { AppCommands(model: model) }
    }
}
