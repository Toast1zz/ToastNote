import SwiftUI
import VaultKit

struct MainWindow: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.vaultRoot == nil {
                WelcomeView(model: model)
            } else {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    FolderTreeView(model: model)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
                } detail: {
                    detail
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .alert("出错了", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = model.currentSession {
            VStack(spacing: 0) {
                SessionBannerView(session: session)
                PlainEditorView(session: session)
            }
            .id(ObjectIdentifier(session))
            .navigationTitle(((session.path as NSString).lastPathComponent as NSString).deletingPathExtension)
        } else {
            Text("按 ⌘N 新建笔记，或按 ⌘P 打开")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
