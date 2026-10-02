import AppKit
import SwiftUI

/// Keys of the settings stored in `UserDefaults` (spec §5.2: app settings live there).
enum SettingsKey {
    static let appearance = "appearance"
    static let openLastVault = "openLastVault"
    static let editorFontSize = "editorFontSize"
    static let editorMaxWidth = "editorMaxWidth"
    static let editorSpellCheck = "editorSpellCheck"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// nil means "follow the system".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    static func apply(_ rawValue: String) {
        NSApp.appearance = (AppAppearance(rawValue: rawValue) ?? .system).nsAppearance
    }
}

struct GeneralSettingsView: View {
    let model: AppModel
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(SettingsKey.openLastVault) private var openLastVault = true

    var body: some View {
        Form {
            Section("笔记库") {
                LabeledContent("当前笔记库") {
                    HStack {
                        Text(model.vaultRoot?.path ?? "未选择")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("更换…") { model.chooseVault() }
                    }
                }
                Toggle("启动时打开上次的笔记库", isOn: $openLastVault)
            }
            Section("外观") {
                Picker("外观", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 260)
        .onChange(of: appearance) { _, new in AppAppearance.apply(new) }
    }
}
