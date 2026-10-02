import AIFormatKit
import SwiftUI

/// Settings → AI (spec §10.8): providers, key, model, connection test and extra instructions.
struct AISettingsView: View {
    let controller: FormatController

    @State private var selectedID = ""
    @State private var draft = ProviderPresets.all[0]
    @State private var apiKey = ""
    @State private var test = ConnectionTest.idle
    @State private var loadedID = ""

    private enum ConnectionTest: Equatable {
        case idle, running, success, unauthorized, modelMissing, network

        var message: String {
            switch self {
            case .idle: ""
            case .running: "正在测试…"
            case .success: "成功"
            case .unauthorized: "API Key 无效"
            case .modelMissing: "模型不存在"
            case .network: "网络错误"
            }
        }
    }

    private var store: ProviderStore { controller.providers }

    var body: some View {
        HStack(spacing: 0) {
            providerList
                .frame(width: 190)
            Divider()
            form
        }
        .frame(width: 640, height: 460)
        .onAppear {
            selectedID = store.currentID
            load(selectedID)
        }
        .onChange(of: selectedID) { _, new in
            guard new != loadedID else { return }
            load(new)
            store.currentID = new
        }
    }

    // MARK: Provider list

    private var providerList: some View {
        VStack(spacing: 0) {
            List(store.providers, selection: $selectedID) { provider in
                HStack {
                    Text(provider.name)
                    Spacer()
                    if provider.id == store.currentID {
                        Text("当前").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(provider.id)
            }
            Divider()
            HStack {
                Button { addCustom() } label: { Image(systemName: "plus") }
                    .help("添加自定义服务商")
                    .accessibilityLabel("添加自定义服务商")
                Button { removeSelected() } label: { Image(systemName: "minus") }
                    .help("删除所选服务商")
                    .accessibilityLabel("删除所选服务商")
                    .disabled(ProviderPresets.all.contains { $0.id == selectedID })
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                TextField("名称", text: $draft.name)
                Picker("接口类型", selection: $draft.kind) {
                    Text("OpenAI 兼容").tag(ProviderKind.openAICompatible)
                    Text("Anthropic").tag(ProviderKind.anthropic)
                }
                TextField("Base URL", text: $draft.baseURL)
                TextField("模型", text: $draft.model, prompt: Text("模型名称，见服务商文档"))
                if draft.requiresKey {
                    SecureField("API Key", text: $apiKey, prompt: Text("粘贴 API Key，保存在钥匙串中"))
                } else {
                    Text("此服务商不需要 API Key").foregroundStyle(.secondary)
                }
                HStack {
                    Button("测试连接") { runTest() }
                        .disabled(test == .running)
                    Text(test.message)
                        .foregroundStyle(test == .success ? Color(nsColor: .systemGreen) : .secondary)
                }
            }
            Section("额外要求") {
                TextEditor(text: Binding(get: { store.extraInstructions }, set: { store.extraInstructions = $0 }))
                    .font(.body)
                    .frame(height: 80)
                Text("追加在系统提示词末尾，例如“列表一律用 -”。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft) { _, new in
            guard new.id == loadedID else { return }
            store.update(new)
        }
        .onChange(of: apiKey) { _, new in
            guard !loadedID.isEmpty else { return }
            if new.isEmpty { try? controller.keychain.delete(account: loadedID) } else { try? controller.keychain.set(new, account: loadedID) }
            test = .idle
        }
    }

    // MARK: Actions

    private func load(_ id: String) {
        guard let provider = store.providers.first(where: { $0.id == id }) else { return }
        loadedID = id
        draft = provider
        apiKey = (try? controller.keychain.get(account: id)) ?? ""
        test = .idle
    }

    private func addCustom() {
        let id = "custom-" + UUID().uuidString.prefix(8).lowercased()
        let provider = ProviderConfig(id: id, name: "自定义服务商", kind: .openAICompatible, baseURL: "https://", model: "", requiresKey: true)
        store.add(provider)
        selectedID = id
    }

    private func removeSelected() {
        let id = selectedID
        try? controller.keychain.delete(account: id)
        store.remove(id: id)
        selectedID = store.currentID
        load(selectedID)
    }

    /// A very short request, so a bad key, model or network shows up immediately (spec §8.2).
    private func runTest() {
        test = .running
        let config = draft
        let key = apiKey
        Task {
            let provider = makeProvider(config, apiKey: key, client: URLSessionHTTPClient(timeout: 30))
            do {
                _ = try await provider.complete(system: "Reply with OK", user: "OK", maxTokens: 8)
                test = .success
            } catch AIError.unauthorized, AIError.notConfigured {
                test = .unauthorized
            } catch AIError.modelNotFound {
                test = .modelMissing
            } catch {
                test = .network
            }
        }
    }
}
