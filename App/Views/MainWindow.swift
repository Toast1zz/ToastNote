import EditorKit
import SwiftUI
import VaultKit

struct MainWindow: View {
    @Bindable var model: AppModel
    let formatController: FormatController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.vaultRoot == nil {
                WelcomeView(model: model)
            } else {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    SidebarView(model: model)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
                } detail: {
                    detail
                }
                .toolbar { toolbarContent }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .sheet(isPresented: Binding(
            get: { formatController.outcome != nil },
            set: { if !$0 { formatController.discard() } }
        )) {
            if let outcome = formatController.outcome {
                FormatReviewSheet(controller: formatController, outcome: outcome)
            }
        }
        // Esc cancels a running request.
        .onExitCommand { if formatController.isRunning { formatController.cancel() } }
        .overlay(alignment: .top) {
            if model.isQuickOpenPresented {
                QuickOpenPanel(model: model)
                    .padding(.top, 56)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.isQuickOpenPresented)
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
            Button {
                if let textView = model.activeTextView { formatController.start(textView: textView) }
            } label: {
                if formatController.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("AI 排版", systemImage: "wand.and.stars")
                }
            }
            .help(formatController.isRunning ? "取消 AI 排版 ⌘⇧L" : "AI 排版 ⌘⇧L")
            .accessibilityLabel(formatController.isRunning ? "取消 AI 排版" : "AI 排版")
            .disabled(model.currentSession == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.exportPDF() } label: {
                if model.isExporting { ProgressView().controlSize(.small) } else { Label("导出", systemImage: "square.and.arrow.up") }
            }
            .help("导出 PDF ⌘⇧E")
            .accessibilityLabel("导出 PDF")
            .disabled(model.currentSession == nil || model.isExporting)
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
                if let banner = formatController.banner {
                    EditorBanner(message: banner.message, actions: banner.actions.map { action in
                        EditorBanner.Action(title: action.title) {
                            formatController.dismissBanner()
                            action.perform()
                        }
                    })
                }
                LiveEditorView(session: session, theme: .default, vaultRoot: model.vaultRoot ?? URL(fileURLWithPath: "/")) {
                    model.activeTextView = $0
                    model.applyPendingHighlight(to: $0)
                }
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
