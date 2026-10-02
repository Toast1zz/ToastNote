import AIFormatKit
import AppKit
import EditorKit
import SwiftUI

/// Keeps the two review panes level: scrolling one scrolls the other to the aligned block (spec §8.6).
/// Alignment is by block, not by pixel, because the formatted side is usually taller.
@MainActor
final class ReviewScrollSync {
    enum Side { case original, formatted }

    private var panes: [Side: (textView: MarkdownTextView, scrollView: NSScrollView)] = [:]
    nonisolated(unsafe) private var observers: [Side: NSObjectProtocol] = [:]
    private var alignments: [BlockAlignment] = []
    private var isApplying = false
    /// Layout settling right after the window opens also moves the clip views; only later scrolls are the user's.
    private var quietUntil = Date.distantPast

    func update(alignments: [BlockAlignment]) {
        self.alignments = alignments
        quietUntil = Date().addingTimeInterval(0.5)
    }

    func register(_ side: Side, textView: MarkdownTextView, scrollView: NSScrollView) {
        panes[side] = (textView, scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        if let old = observers[side] { NotificationCenter.default.removeObserver(old) }
        observers[side] = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled(side) }
        }
    }

    deinit {
        for observer in observers.values { NotificationCenter.default.removeObserver(observer) }
    }

    private func scrolled(_ side: Side) {
        guard !isApplying, Date() >= quietUntil, let source = panes[side], let target = panes[side == .original ? .formatted : .original] else { return }
        let top = source.scrollView.contentView.bounds.minY
        guard let index = source.textView.blockIndexAt(y: top), let sourceTop = source.textView.blockTop(at: index) else { return }
        let nextTop = source.textView.blockTop(at: index + 1) ?? (sourceTop + 1)
        let fraction = max(0, min(1, (top - sourceTop) / max(nextTop - sourceTop, 1)))

        guard let mapped = mappedBlock(index, from: side),
              let targetTop = target.textView.blockTop(at: mapped) else { return }
        let targetNext = target.textView.blockTop(at: mapped + 1) ?? (targetTop + 1)
        let y = targetTop + fraction * (targetNext - targetTop)

        isApplying = true
        let maxY = max(target.textView.frame.height - target.scrollView.contentView.bounds.height, 0)
        target.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, min(y, maxY))))
        target.scrollView.reflectScrolledClipView(target.scrollView.contentView)
        isApplying = false
    }

    /// The block on the other side that holds the same text, spreading blocks evenly across a group.
    private func mappedBlock(_ index: Int, from side: Side) -> Int? {
        for alignment in alignments {
            let (mine, theirs) = side == .original ? (alignment.original, alignment.formatted) : (alignment.formatted, alignment.original)
            guard mine.contains(index), !theirs.isEmpty else { continue }
            let offset = index - mine.lowerBound
            let scaled = offset * theirs.count / max(mine.count, 1)
            return theirs.lowerBound + min(scaled, theirs.count - 1)
        }
        // A block without a counterpart: stay at the closest alignment.
        let closest = alignments.min { lhs, rhs in
            distance(index, side == .original ? lhs.original : lhs.formatted) < distance(index, side == .original ? rhs.original : rhs.formatted)
        }
        return closest.map { side == .original ? $0.formatted.lowerBound : $0.original.lowerBound }
    }

    private func distance(_ index: Int, _ range: Range<Int>) -> Int {
        index < range.lowerBound ? range.lowerBound - index : max(index - (range.upperBound - 1), 0)
    }
}

/// One rendered, read-only column of the review window. It is the real editor view in `concealAll` mode, so
/// what you review is what you get after accepting (spec §7.6).
struct SyncedRenderedPane: NSViewRepresentable {
    let markdown: String
    let side: ReviewScrollSync.Side
    let sync: ReviewScrollSync
    var labels: [Int: String] = [:]

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(theme: .default, concealAll: true)
        textView.fixedHorizontalInset = 72
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.markdown = markdown
        textView.blockLabels = labels

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        sync.register(side, textView: textView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        if textView.string != markdown { textView.markdown = markdown }
        textView.blockLabels = labels
    }
}
