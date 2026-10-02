import Foundation
import Observation

/// Providers, the selected one and the extra prompt text, kept in `UserDefaults` (API keys live in the
/// keychain, see `KeychainStore`).
@Observable
public final class ProviderStore {
    @ObservationIgnored private let defaults: UserDefaults
    private static let providersKey = "aiProviders"
    private static let currentKey = "aiCurrentProvider"
    private static let extraKey = "aiExtraInstructions"

    public private(set) var providers: [ProviderConfig]

    public var currentID: String {
        didSet { defaults.set(currentID, forKey: Self.currentKey) }
    }

    public var extraInstructions: String {
        didSet { defaults.set(extraInstructions, forKey: Self.extraKey) }
    }

    public var current: ProviderConfig? { providers.first { $0.id == currentID } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stored = defaults.data(forKey: Self.providersKey)
            .flatMap { try? JSONDecoder().decode([ProviderConfig].self, from: $0) } ?? []
        stored.removeAll { ProviderPresets.retiredIDs.contains($0.id) }
        // Presets added in later versions must show up for existing users; edited ones keep the user's values.
        for preset in ProviderPresets.all where !stored.contains(where: { $0.id == preset.id }) {
            stored.append(preset)
        }
        // Keep the built-in order (DeepSeek first), with custom providers after it.
        let presetIDs = ProviderPresets.all.map(\.id)
        providers = stored.sorted { lhs, rhs in
            let l = presetIDs.firstIndex(of: lhs.id) ?? presetIDs.count
            let r = presetIDs.firstIndex(of: rhs.id) ?? presetIDs.count
            return l < r
        }
        currentID = defaults.string(forKey: Self.currentKey) ?? "deepseek"
        extraInstructions = defaults.string(forKey: Self.extraKey) ?? ""
        if current == nil { currentID = "deepseek" }
    }

    public func add(_ provider: ProviderConfig) {
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        save()
    }

    public func update(_ provider: ProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return add(provider) }
        providers[index] = provider
        save()
    }

    public func remove(id: String) {
        providers.removeAll { $0.id == id }
        if currentID == id { currentID = "deepseek" }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(providers) { defaults.set(data, forKey: Self.providersKey) }
    }
}
