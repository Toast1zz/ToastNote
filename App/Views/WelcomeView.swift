import SwiftUI

struct WelcomeView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("欢迎使用 ToastNote")
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 16)
            Text("笔记就是文件夹里的 Markdown 文件。选一个已有的文件夹，或新建一个。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 8)
            HStack(spacing: 12) {
                Button("新建笔记库…") { model.createVault() }
                    .controlSize(.large)
                Button("打开文件夹…") { model.chooseVault() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 28)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
