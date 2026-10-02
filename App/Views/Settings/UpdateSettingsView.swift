import SwiftUI

struct UpdateSettingsView: View {
    let updates: UpdateController
    @State private var automatic = true

    var body: some View {
        Form {
            Section {
                Toggle("自动检查更新", isOn: $automatic)
                    .disabled(!updates.isConfigured)
                    .onChange(of: automatic) { _, new in updates.automaticallyChecks = new }
                HStack {
                    Button("立即检查") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                    Spacer()
                }
                LabeledContent("当前版本", value: updates.versionDescription)
            }
            if !updates.isConfigured {
                Section {
                    Text("这个构建没有更新签名公钥，所以更新功能未启用。正式发布的版本会带有公钥，见 docs/RELEASING.md。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 260)
        .onAppear { automatic = updates.isConfigured ? updates.automaticallyChecks : false }
    }
}
