import Foundation
import Testing
@testable import AIFormatKit

private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "tn-test-" + UUID().uuidString)!
}

@Suite struct ProviderStoreTests {
    @Test func presetsMatchSpec() throws {
        let presets = ProviderPresets.all
        #expect(presets.map(\.id) == ["deepseek", "anthropic", "openai", "siliconflow", "dashscope", "openrouter", "ollama"])
        let deepseek = try #require(presets.first(where: { $0.id == "deepseek" }))
        #expect(deepseek.baseURL == "https://api.deepseek.com")
        #expect(deepseek.model == "deepseek-flash")
        #expect(deepseek.kind == .openAICompatible)
        let anthropic = try #require(presets.first(where: { $0.id == "anthropic" }))
        #expect(anthropic.kind == .anthropic)
        #expect(anthropic.baseURL == "https://api.anthropic.com")
        #expect(anthropic.model == "claude-haiku-4-5")
        let ollama = try #require(presets.first(where: { $0.id == "ollama" }))
        #expect(ollama.requiresKey == false)
        #expect(ollama.baseURL == "http://localhost:11434/v1")
        let needKey = presets.filter { $0.id != "ollama" }
        let allNeedKey = needKey.allSatisfy { $0.requiresKey }
        #expect(allNeedKey)
    }

    @Test func otherPresetsLeaveTheModelForTheUser() throws {
        for id in ["openai", "siliconflow", "dashscope", "openrouter", "ollama"] {
            let preset = ProviderPresets.all.first(where: { $0.id == id })
            #expect(preset?.model == "")
        }
    }

    @Test func defaultCurrentIsDeepSeek() {
        let store = ProviderStore(defaults: isolatedDefaults())
        #expect(store.currentID == "deepseek")
        #expect(store.current?.id == "deepseek")
        #expect(store.providers.count == ProviderPresets.all.count)
    }

    @Test func editedPresetPersists() {
        let defaults = isolatedDefaults()
        let store = ProviderStore(defaults: defaults)
        var deepseek = store.providers[0]
        deepseek.model = "deepseek-pro"
        store.update(deepseek)
        #expect(ProviderStore(defaults: defaults).providers[0].model == "deepseek-pro")
    }

    @Test func customProviderPersists() {
        let defaults = isolatedDefaults()
        let store = ProviderStore(defaults: defaults)
        let custom = ProviderConfig(id: "mine", name: "我的服务", kind: .openAICompatible, baseURL: "https://example.com/v1", model: "m1", requiresKey: true)
        store.add(custom)
        store.currentID = "mine"
        store.extraInstructions = "列表一律用 -"

        let reloaded = ProviderStore(defaults: defaults)
        #expect(reloaded.providers.contains(custom))
        #expect(reloaded.currentID == "mine")
        #expect(reloaded.current == custom)
        #expect(reloaded.extraInstructions == "列表一律用 -")
    }

    @Test func removingTheCurrentProviderFallsBackToDeepSeek() {
        let store = ProviderStore(defaults: isolatedDefaults())
        let custom = ProviderConfig(id: "mine", name: "我的服务", kind: .anthropic, baseURL: "https://x", model: "m", requiresKey: true)
        store.add(custom)
        store.currentID = "mine"
        store.remove(id: "mine")
        #expect(store.currentID == "deepseek")
        #expect(!store.providers.contains(custom))
    }

    @Test func corruptStoredProvidersFallBackToPresets() {
        let defaults = isolatedDefaults()
        defaults.set(Data("not json".utf8), forKey: "aiProviders")
        let store = ProviderStore(defaults: defaults)
        #expect(store.providers == ProviderPresets.all)
    }

    @Test func presetsAddedLaterAppearForExistingUsers() {
        // A stored list that predates a preset must not hide it.
        let defaults = isolatedDefaults()
        let partial = [ProviderPresets.all[0]]
        defaults.set(try! JSONEncoder().encode(partial), forKey: "aiProviders")
        let store = ProviderStore(defaults: defaults)
        let ids = store.providers.map(\.id)
        #expect(ids.contains("ollama"))
        #expect(store.providers[0].id == "deepseek")
    }
}
