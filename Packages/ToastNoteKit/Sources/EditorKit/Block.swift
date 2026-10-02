import Foundation

public enum BlockKind: Hashable, Sendable {
    case paragraph, heading(level: Int), quote, codeBlock(language: String?), table, thematicBreak, frontmatter
    /// Each list item is its own block (spec §7.2).
    case listItem(ordered: Bool, task: TaskState?, depth: Int)
}

public enum TaskState: Hashable, Sendable { case open, done }

public enum InlineKind: Equatable, Sendable {
    case strong, emphasis, strikethrough, inlineCode
    case link(url: String), image(source: String), bareURL(String), tag(String)
}

public struct InlineSpan: Equatable, Sendable {
    public var kind: InlineKind
    public var range: NSRange
    /// Markers that are hidden while the block is inactive.
    public var syntaxRanges: [NSRange]

    public init(kind: InlineKind, range: NSRange, syntaxRanges: [NSRange] = []) {
        self.kind = kind
        self.range = range
        self.syntaxRanges = syntaxRanges
    }
}

public struct Block: Equatable, Sendable {
    public var kind: BlockKind
    /// Full block including markers, excluding the trailing newline.
    public var range: NSRange
    /// Block-level markers: "# ", "> ", "- [ ] ", fences, "---", the whole frontmatter.
    public var syntaxRanges: [NSRange]
    /// The visible content.
    public var contentRange: NSRange
    public var inlines: [InlineSpan]

    public init(kind: BlockKind, range: NSRange, syntaxRanges: [NSRange], contentRange: NSRange, inlines: [InlineSpan] = []) {
        self.kind = kind
        self.range = range
        self.syntaxRanges = syntaxRanges
        self.contentRange = contentRange
        self.inlines = inlines
    }
}

public extension Array where Element == Block {
    /// Blocks touched by `range`. A caret counts when it sits anywhere in the block, ends included.
    func indices(intersecting range: NSRange) -> IndexSet {
        var result = IndexSet()
        for (index, block) in enumerated() {
            let blockEnd = NSMaxRange(block.range)
            if range.length == 0 {
                if range.location >= block.range.location && range.location <= blockEnd { result.insert(index) }
            } else if NSIntersectionRange(range, block.range).length > 0 {
                result.insert(index)
            }
        }
        return result
    }
}
