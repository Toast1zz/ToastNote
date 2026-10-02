import SwiftUI

@main
struct ToastNoteApp: App {
    var body: some Scene {
        WindowGroup {
            Text("ToastNote")
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
