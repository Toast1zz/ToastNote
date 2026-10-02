import AIFormatKit
import SwiftUI

/// Side-by-side review of an AI formatting result (spec §8.6): both columns rendered, changed blocks marked.
struct FormatReviewSheet: View {
    let controller: FormatController
    let outcome: FormatOutcome

    @State private var sync = ReviewScrollSync()
    @State private var confirmingForcedAccept = false

    private var passed: Bool { outcome.guardResult.passed }
    private var structureChanges: Int { outcome.diff.changes.count }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !passed { changedSentencesList }
            HStack(spacing: 0) {
                column(title: "原文") {
                    SyncedRenderedPane(markdown: outcome.original, side: .original, sync: sync)
                }
                Divider()
                column(title: "排版后") {
                    SyncedRenderedPane(
                        markdown: outcome.formatted, side: .formatted, sync: sync,
                        labels: outcome.diff.changes.mapValues(\.label)
                    )
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear { sync.update(alignments: outcome.diff.alignments) }
        .confirmationDialog("仍要接受？", isPresented: $confirmingForcedAccept) {
            Button("仍要接受", role: .destructive) { controller.accept() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("AI 可能改动了文字内容。接受后可以用 ⌘Z 撤销。")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            if passed {
                Label("文字内容未改动 · 调整了 \(structureChanges) 处结构", systemImage: "checkmark")
                    .foregroundStyle(Color(nsColor: .systemGreen))
            } else {
                Label("AI 可能改动了文字内容", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
            Spacer()
            if passed {
                Button("放弃") { controller.discard() }
                    .keyboardShortcut(.cancelAction)
                Button("接受") { controller.accept() }
                    .keyboardShortcut(.defaultAction)
            } else {
                // Accepting a changed text takes a deliberate second step.
                Button("仍要接受…") { confirmingForcedAccept = true }
                    .buttonStyle(.link)
                Button("放弃") { controller.discard() }
                    .keyboardShortcut(.defaultAction)
                Button("") { controller.discard() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 12)
        .padding(10)
    }

    private var changedSentencesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("下列句子可能被改动：").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(outcome.guardResult.changedSentences, id: \.self) { sentence in
                        Text(sentence).font(.callout).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
    }

    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            content()
        }
    }
}
