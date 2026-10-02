import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建笔记") { model.newNote() }
                .keyboardShortcut("n")
                .disabled(model.vaultRoot == nil)
            Button("打开笔记库…") { model.chooseVault() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存") { model.saveNow() }
                .keyboardShortcut("s")
                .disabled(model.currentSession == nil)
        }
        CommandGroup(replacing: .sidebar) {
            Button("显示或隐藏侧边栏") {
                model.columnVisibility = model.columnVisibility == .detailOnly ? .all : .detailOnly
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }
}
