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
                    // The footer sits below the list (not over it) so scrolled rows never show through.
                    VStack(spacing: 0) {
                        FolderTreeView(model: model)
                        Divider()
                        sidebarFooter
                    }
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

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Button { model.newNote() } label: {
                Label("新建笔记", systemImage: "plus")
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button("新建文件夹") { model.newFolder() }
                Divider()
                Button("打开笔记库…") { model.chooseVault() }
                Button("新建笔记库…") { model.createVault() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
