import EditorKit
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
                .toolbar { toolbarContent }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        // Until session restore exists (M3) the window itself is the first interactive state.
        .onAppear { LaunchTiming.editorReady() }
        .alert("出错了", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Frequent actions live in the window toolbar, like Apple Notes' compose button (HIG: toolbars).
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { model.newNote() } label: {
                Label("新建笔记", systemImage: "square.and.pencil")
            }
            .help("新建笔记（⌘N）")
            .accessibilityLabel("新建笔记")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("新建文件夹") { model.newFolder() }
                Divider()
                Button("打开笔记库…") { model.chooseVault() }
                Button("新建笔记库…") { model.createVault() }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .help("更多")
            .accessibilityLabel("更多")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = model.currentSession {
            VStack(spacing: 0) {
                SessionBannerView(session: session)
                LiveEditorView(session: session, theme: .default) { model.activeTextView = $0 }
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
