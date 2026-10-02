import SwiftUI

struct WelcomeView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Text("选择一个文件夹作为笔记库")
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Button("选择文件夹…") { model.chooseVault() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("新建笔记库…") { model.createVault() }
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
