import EditorKit
import Foundation

public enum BlockChangeKind: Equatable, Sendable {
    case becameHeading, becameList, becameQuote, becameTable, split, merged, addedEmphasis

    /// Labels shown next to changed blocks in the review window (spec §8.6).
    public var label: String {
        switch self {
        case .becameHeading: "变为标题"
        case .becameList: "变为列表"
        case .becameQuote: "变为引用"
        case .becameTable: "变为表格"
        case .split: "拆分段落"
        case .merged: "合并段落"
        case .addedEmphasis: "新增强调"
        }
    }
}

/// A run of original blocks and the run of formatted blocks that hold the same text.
public struct BlockAlignment: Equatable, Sendable {
    public var original: Range<Int>
    public var formatted: Range<Int>

    public init(original: Range<Int>, formatted: Range<Int>) {
        self.original = original
        self.formatted = formatted
    }
}

public struct BlockDiffResult: Equatable, Sendable {
    /// Formatted block index → what happened to it.
    public var changes: [Int: BlockChangeKind]
    public var alignments: [BlockAlignment]
}

/// Which blocks changed structure between the original and the formatted text (spec §8.6).
public enum BlockDiff {
    private struct Side {
        var blocks: [Block]
        var normalized: [String]
    }

    public static func compare(original: String, formatted: String) -> BlockDiffResult {
        let before = side(original)
        let after = side(formatted)
        let alignments = align(before.normalized, after.normalized)

        var changes: [Int: BlockChangeKind] = [:]
        for alignment in alignments {
            classify(alignment, before: before.blocks, after: after.blocks, into: &changes)
        }
        return BlockDiffResult(changes: changes, alignments: alignments)
    }

    private static func side(_ markdown: String) -> Side {
        let ns = markdown as NSString
        let blocks = BlockParser.parse(markdown)
        let normalized = blocks.map { block in
            ContentGuard.normalizedText(PlainText.extract(ns.substring(with: block.range)))
        }
        return Side(blocks: blocks, normalized: normalized)
    }

    // MARK: Alignment

    /// Greedily groups blocks until both sides hold the same text. Grouping stops early when the texts
    /// differ (neither is a prefix of the other), so edited text cannot swallow the rest of the document.
    private static func align(_ original: [String], _ formatted: [String]) -> [BlockAlignment] {
        var alignments: [BlockAlignment] = []
        var i = 0, j = 0
        while i < original.count || j < formatted.count {
            let oStart = i, fStart = j
            var a = ""
            var b = ""
            if i < original.count { a += original[i]; i += 1 }
            if j < formatted.count { b += formatted[j]; j += 1 }
            while a != b, a.hasPrefix(b) || b.hasPrefix(a) {
                if a.count <= b.count, i < original.count {
                    a += original[i]; i += 1
                } else if j < formatted.count, b.count <= a.count {
                    b += formatted[j]; j += 1
                } else if i < original.count {
                    a += original[i]; i += 1
                } else if j < formatted.count {
                    b += formatted[j]; j += 1
                } else {
                    break
                }
            }
            // Blocks without text (rules, empty lines) never need a group of their own.
            alignments.append(BlockAlignment(original: oStart..<i, formatted: fStart..<j))
        }
        return alignments
    }

    // MARK: Classification

    private static func classify(
        _ alignment: BlockAlignment, before: [Block], after: [Block], into changes: inout [Int: BlockChangeKind]
    ) {
        let originalBlocks = Array(before[alignment.original])
        let formattedBlocks = Array(after[alignment.formatted])
        guard !formattedBlocks.isEmpty, !originalBlocks.isEmpty else { return }

        if originalBlocks.count == 1, formattedBlocks.count == 1 {
            let (old, new) = (originalBlocks[0], formattedBlocks[0])
            if let kind = becameKind(old: old, new: new) {
                changes[alignment.formatted.lowerBound] = kind
            } else if emphasisCount(new) > emphasisCount(old) {
                changes[alignment.formatted.lowerBound] = .addedEmphasis
            }
            return
        }

        if originalBlocks.count == 1 {
            // One block became several: lists and headings are named for what they became, the rest is a split.
            for (offset, new) in formattedBlocks.enumerated() {
                let kind = becameKind(old: originalBlocks[0], new: new) ?? .split
                changes[alignment.formatted.lowerBound + offset] = kind
            }
        } else if formattedBlocks.count == 1 {
            let new = formattedBlocks[0]
            let kind = becameKind(old: originalBlocks[0], new: new) ?? .merged
            changes[alignment.formatted.lowerBound] = kind
        } else if originalBlocks.count != formattedBlocks.count {
            for (offset, new) in formattedBlocks.enumerated() {
                changes[alignment.formatted.lowerBound + offset] = becameKind(old: originalBlocks[min(offset, originalBlocks.count - 1)], new: new)
                    ?? (formattedBlocks.count > originalBlocks.count ? .split : .merged)
            }
        } else {
            for (offset, new) in formattedBlocks.enumerated() {
                if let kind = becameKind(old: originalBlocks[offset], new: new) {
                    changes[alignment.formatted.lowerBound + offset] = kind
                }
            }
        }
    }

    /// The structural kind a block turned into, when it differs from what it was.
    private static func becameKind(old: Block, new: Block) -> BlockChangeKind? {
        switch (old.kind, new.kind) {
        case (.heading, .heading), (.listItem, .listItem), (.quote, .quote), (.table, .table): return nil
        case (_, .heading): return .becameHeading
        case (_, .listItem): return .becameList
        case (_, .quote): return .becameQuote
        case (_, .table): return .becameTable
        default: return nil
        }
    }

    private static func emphasisCount(_ block: Block) -> Int {
        block.inlines.filter { $0.kind == .strong || $0.kind == .emphasis }.count
    }
}
