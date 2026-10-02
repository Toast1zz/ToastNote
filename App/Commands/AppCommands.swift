import AppKit
import EditorKit
import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    let formatController: FormatController

    /// Menu item that forwards to the focused editor through the responder chain.
    private func formatButton(_ title: String, key: KeyEquivalent, modifiers: EventModifiers, action: Selector) -> some View {
        Button(title) { NSApp.sendAction(action, to: nil, from: nil) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(model.currentSession == nil)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建笔记") { model.newNote() }
                .keyboardShortcut("n")
                .disabled(model.vaultRoot == nil)
            Button("打开笔记库…") { model.chooseVault() }
                .keyboardShortcut("o")
            Button("快速打开…") { model.isQuickOpenPresented.toggle() }
                .keyboardShortcut("p")
                .disabled(model.vaultRoot == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存") { model.saveNow() }
                .keyboardShortcut("s")
                .disabled(model.currentSession == nil)
        }
        CommandMenu("标签页") {
            Button("关闭标签页") { model.closeCurrent() }
                .keyboardShortcut("w")
                .disabled(model.workspace.current == nil)
            Divider()
            Button("下一个标签页") { model.selectNext() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("上一个标签页") { model.selectPrevious() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button("切换到第 \(number) 个标签页") { model.select(index: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                    .disabled(model.workspace.ordered.count < number)
            }
        }
        CommandMenu("格式") {
            Button(formatController.isRunning ? "取消 AI 排版" : "AI 排版") {
                if let textView = model.activeTextView { formatController.start(textView: textView) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(model.currentSession == nil)
            Divider()
            formatButton("粗体", key: "b", modifiers: .command, action: #selector(MarkdownTextView.toggleBold(_:)))
            formatButton("斜体", key: "i", modifiers: .command, action: #selector(MarkdownTextView.toggleItalic(_:)))
            formatButton("删除线", key: "x", modifiers: [.command, .shift], action: #selector(MarkdownTextView.toggleStrikethrough(_:)))
            formatButton("行内代码", key: "e", modifiers: .command, action: #selector(MarkdownTextView.toggleInlineCode(_:)))
            formatButton("插入链接", key: "k", modifiers: .command, action: #selector(MarkdownTextView.insertMarkdownLink(_:)))
        }
        CommandGroup(replacing: .sidebar) {
            Button("显示或隐藏侧边栏") {
                model.columnVisibility = model.columnVisibility == .detailOnly ? .all : .detailOnly
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }
}
