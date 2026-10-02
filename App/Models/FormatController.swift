import AIFormatKit
import AppKit
import EditorKit
import Observation
import SwiftUI

/// A message above the editor with optional buttons, used for AI errors and notices (spec §8.7).
struct FormatBanner: Identifiable {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let perform: @MainActor () -> Void
    }

    let id = UUID()
    let message: String
    var actions: [Action] = []
}

/// Runs AI formatting for the open note and owns everything around it: providers, progress, errors, the
/// review of the result and applying it (spec §8).
@MainActor @Observable
final class FormatController {
    let providers = ProviderStore()
    @ObservationIgnored let keychain = KeychainStore()

    private(set) var isRunning = false
    /// The finished run waiting for the user's decision; the review window shows while it is set.
    private(set) var outcome: FormatOutcome?
    private(set) var banner: FormatBanner?
    /// Whether the run covered a selection rather than the whole note.
    private(set) var isFragment = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = FormatRequestToken(text: "")
    @ObservationIgnored private var targetRange = NSRange(location: 0, length: 0)
    @ObservationIgnored private weak var textView: MarkdownTextView?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    // MARK: Running

    /// ⌘⇧L: formats the selection, or the whole note when nothing is selected. Pressing it again cancels.
    func start(textView: MarkdownTextView) {
        if isRunning {
            cancel()
            return
        }
        banner = nil
        self.textView = textView

        guard let config = providers.current else {
            show(error: .notConfigured)
            return
        }
        let key = (try? keychain.get(account: config.id)) ?? nil
        if config.requiresKey, (key ?? "").isEmpty {
            // First use: go straight to the page where the key is entered.
            openSettings()
            show(error: .notConfigured)
            return
        }

        let document = textView.string as NSString
        let selection = textView.selectedRange()
        isFragment = selection.length > 0
        targetRange = isFragment ? selection : NSRange(location: 0, length: document.length)
        guard targetRange.length > 0 else { return }

        let text = document.substring(with: targetRange)
        token = FormatRequestToken(text: textView.string)
        let fragment = isFragment
        let provider = makeProvider(config, apiKey: key, client: URLSessionHTTPClient())
        let pipeline = FormatPipeline(provider: provider, extraInstructions: providers.extraInstructions)

        isRunning = true
        task = Task { [weak self] in
            do {
                let result = try await pipeline.run(text, isFragment: fragment)
                self?.finish(with: result)
            } catch is CancellationError {
                self?.isRunning = false
            } catch let error as AIError {
                self?.isRunning = false
                self?.show(error: error)
            } catch {
                self?.isRunning = false
                self?.show(error: .network)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func finish(with result: FormatOutcome) {
        isRunning = false
        guard let textView else { return }
        // The note was edited while the model worked: its answer no longer fits, so drop it (Review Focus 3).
        if token.isStale(currentText: textView.string) {
            show(error: .textChanged)
            return
        }
        if result.hasChanges {
            outcome = result
        } else {
            notice("已经很整齐了，无需调整")
        }
    }

    // MARK: Review

    func accept() {
        guard let outcome, let textView else { return }
        self.outcome = nil
        if token.isStale(currentText: textView.string) {
            show(error: .textChanged)
            return
        }
        // One undo step named "AI 排版" (spec §8.1).
        textView.applyEdit(range: targetRange, replacement: outcome.formatted, actionName: "AI 排版")
    }

    func discard() {
        outcome = nil
    }

    // MARK: Banners

    func dismissBanner() {
        noticeTask?.cancel()
        banner = nil
    }

    private func notice(_ message: String) {
        banner = FormatBanner(message: message)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    /// Error copy and buttons exactly as in the table of spec §8.7.
    private func show(error: AIError) {
        let modelName = providers.current?.model ?? ""
        let settings = FormatBanner.Action(title: "打开设置") { [weak self] in self?.openSettings() }
        let retry = FormatBanner.Action(title: "重试") { [weak self] in
            guard let self, let textView = self.textView else { return }
            self.start(textView: textView)
        }
        switch error {
        case .notConfigured: banner = FormatBanner(message: "先设置一个 AI 服务商", actions: [settings])
        case .unauthorized: banner = FormatBanner(message: "API Key 无效或没有权限", actions: [settings])
        case .modelNotFound(let model): banner = FormatBanner(message: "找不到模型“\(model.isEmpty ? modelName : model)”", actions: [settings])
        case .rateLimited: banner = FormatBanner(message: "请求太频繁或额度不足", actions: [retry])
        case .network, .timeout: banner = FormatBanner(message: "网络连接失败", actions: [retry])
        case .incompleteResult: banner = FormatBanner(message: "AI 返回的结果不完整", actions: [retry])
        case .textChanged: banner = FormatBanner(message: "内容已变化，请重新排版")
        }
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
