import SwiftUI

struct EditorSettingsView: View {
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = 15.0
    @AppStorage(SettingsKey.editorMaxWidth) private var maxWidth = 960.0
    @AppStorage(SettingsKey.editorSpellCheck) private var spellCheck = false

    var body: some View {
        Form {
            Section("排版") {
                LabeledContent("正文字号") {
                    HStack {
                        Slider(value: $fontSize, in: 13...20, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                LabeledContent("正文最大宽度") {
                    HStack {
                        Slider(value: $maxWidth, in: 600...1200, step: 20)
                        Text("\(Int(maxWidth)) pt").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
                Text("窗口较窄时正文列会随窗口收窄；这里设的是它最宽能到多少。").font(.caption).foregroundStyle(.secondary)
            }
            Section("输入") {
                Toggle("拼写检查", isOn: $spellCheck)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 280)
    }
}
