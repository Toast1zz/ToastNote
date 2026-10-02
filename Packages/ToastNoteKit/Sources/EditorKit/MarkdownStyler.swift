import Foundation

public enum Decoration: Equatable, Sendable {
    case bullet(at: Int, depth: Int)
    case checkbox(at: Int, done: Bool)
    case quoteBar(NSRange)
    case codeBackground(NSRange)
    case inlineCodeBackground(NSRange)
    case rule(NSRange)
    case tagPill(NSRange)
    case codeLanguage(String, NSRange)
    case image(source: String, lineRange: NSRange)
    case frontmatterSummary(count: Int, lineRange: NSRange)
}

public struct StyleRun: Equatable, Sendable {
    public var range: NSRange
    public var style: TextStyle

    public init(range: NSRange, style: TextStyle) {
        self.range = range
        self.style = style
    }
}

public struct StyleResult: Equatable, Sendable {
    public var runs: [StyleRun] = []
    /// Ranges whose glyphs are hidden (markers of inactive blocks).
    public var hidden: [NSRange] = []
    public var decorations: [Decoration] = []

    public init(runs: [StyleRun] = [], hidden: [NSRange] = [], decorations: [Decoration] = []) {
        self.runs = runs
        self.hidden = hidden
        self.decorations = decorations
    }
}

/// Pure function from the block model and the active blocks to styles, hidden ranges and decorations.
public enum MarkdownStyler {
    /// - Parameter concealAll: read-only rendering: no block is ever treated as active.
    public static func style(blocks: [Block], text: NSString, active: IndexSet, concealAll: Bool = false) -> StyleResult {
        var result = StyleResult()
        for (index, block) in blocks.enumerated() {
            let isActive = !concealAll && active.contains(index)
            emit(block, text: text, isActive: isActive, into: &result)
        }
        emitBlankLines(blocks: blocks, text: text, into: &result)
        return result
    }

    /// Blank lines are real empty paragraphs; give them a short line so they do not double paragraph gaps.
    private static func emitBlankLines(blocks: [Block], text: NSString, into result: inout StyleResult) {
        var cursor = 0
        func scan(upTo end: Int) {
            var index = cursor
            while index < min(end, text.length) {
                // A blank line is a newline that starts its line.
                if text.character(at: index) == 0x0A, index == 0 || text.character(at: index - 1) == 0x0A {
                    result.runs.append(StyleRun(range: NSRange(location: index, length: 1), style: TextStyle(role: .body, blankLine: true)))
                }
                index += 1
            }
        }
        for block in blocks.sorted(by: { $0.range.location < $1.range.location }) {
            scan(upTo: block.range.location)
            // Skip the block's own line terminator.
            cursor = max(cursor, NSMaxRange(block.range) + 1)
        }
        scan(upTo: text.length)
    }

    // MARK: Per block

    private static func emit(_ block: Block, text: NSString, isActive: Bool, into result: inout StyleResult) {
        let base = baseRole(of: block)

        switch block.kind {
        case .frontmatter:
            if isActive {
                result.runs.append(StyleRun(range: block.range, style: TextStyle(role: .codeInline)))
            } else {
                result.hidden.append(block.range)
                var start = 0, end = 0, contentsEnd = 0
                text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: block.range.location, length: 0))
                let lineEnd = NSRange(location: start, length: contentsEnd - start)
                result.decorations.append(.frontmatterSummary(count: frontmatterKeyCount(block.range, text: text), lineRange: lineEnd))
            }
            return
        case .thematicBreak:
            if isActive {
                result.runs.append(StyleRun(range: block.range, style: TextStyle(role: .marker)))
            } else {
                result.hidden.append(block.range)
                result.decorations.append(.rule(block.range))
            }
            return
        case .table:
            emitTable(block, text: text, into: &result)
            return
        default:
            break
        }

        // Paragraph-level attributes (spacing, indents) come from a paragraph's first character, which is
        // often a marker, so the base style covers the whole block, not just its visible content.
        var listDepth: Int?
        var isListItem = false
        var runRange = block.range
        if case .listItem(let ordered, _, let depth) = block.kind {
            isListItem = true
            if !ordered {
                // Inactive bullets are indented by paragraph style, so the source indentation is hidden. The
                // indentation joins the block run so the paragraph style starts at the line's first character.
                let lead = leadingWhitespace(before: block.range.location, in: text)
                runRange = NSRange(location: lead.location, length: NSMaxRange(block.range) - lead.location)
                listDepth = isActive ? 0 : depth
                if !isActive, lead.length > 0 { result.hidden.append(lead) }
            }
        }
        let blockStyle = TextStyle(role: base, listDepth: listDepth, tightSpacing: isListItem)
        if runRange.length > 0 {
            result.runs.append(StyleRun(range: runRange, style: blockStyle))
        }
        for segment in contentSegments(of: block) where segment.length > 0 {
            result.runs.append(StyleRun(range: segment, style: blockStyle))
        }

        emitBlockSyntax(block, text: text, isActive: isActive, into: &result)
        emitInlines(block, base: base, isActive: isActive, into: &result)

        switch block.kind {
        case .quote where !isActive:
            result.decorations.append(.quoteBar(block.range))
        case .codeBlock(let language):
            result.decorations.append(.codeBackground(block.range))
            if let language { result.decorations.append(.codeLanguage(language, block.range)) }
        default:
            break
        }
    }

    private static func baseRole(of block: Block) -> TextStyle.Role {
        switch block.kind {
        case .heading(let level): .heading(level)
        case .quote: .quote
        case .codeBlock: .codeBlock
        case .listItem(_, .done?, _): .taskDone
        default: .body
        }
    }

    /// Visible content: the content range, or for quotes the block minus its per-line markers.
    private static func contentSegments(of block: Block) -> [NSRange] {
        if case .quote = block.kind { return subtract(block.syntaxRanges, from: block.range) }
        return [block.contentRange]
    }

    private static func emitBlockSyntax(_ block: Block, text: NSString, isActive: Bool, into result: inout StyleResult) {
        let marker = TextStyle(role: .marker)
        var hideMarkers = !isActive
        var decoration: Decoration?
        if case .listItem(let ordered, let task, let depth) = block.kind, let syntax = block.syntaxRanges.first {
            if ordered {
                // Ordered numbers stay visible, muted.
                hideMarkers = false
                result.runs.append(StyleRun(range: syntax, style: marker))
            } else if !isActive {
                decoration = task.map { .checkbox(at: syntax.location, done: $0 == .done) } ?? .bullet(at: syntax.location, depth: depth)
            }
        }
        for (index, syntax) in block.syntaxRanges.enumerated() where syntax.length > 0 {
            if hideMarkers {
                result.hidden.append(fenceAware(syntax, index: index, block: block, text: text))
            } else if isActive {
                result.runs.append(StyleRun(range: syntax, style: marker))
            }
        }
        if let decoration { result.decorations.append(decoration) }
    }

    /// Fence lines are hidden together with their line break, or they would leave empty lines inside the block.
    private static func fenceAware(_ syntax: NSRange, index: Int, block: Block, text: NSString) -> NSRange {
        guard case .codeBlock = block.kind else { return syntax }
        var hidden = syntax
        if index == 0, NSMaxRange(syntax) < text.length, text.character(at: NSMaxRange(syntax)) == 0x0A {
            hidden.length += 1
        } else if index == 1, syntax.location > 0, text.character(at: syntax.location - 1) == 0x0A {
            hidden.location -= 1
            hidden.length += 1
        }
        return hidden
    }

    /// The spaces and tabs between the start of the line and `location`.
    private static func leadingWhitespace(before location: Int, in text: NSString) -> NSRange {
        var start = location
        while start > 0 {
            let previous = text.character(at: start - 1)
            guard previous == 0x20 || previous == 0x09 else { break }
            start -= 1
        }
        return NSRange(location: start, length: location - start)
    }

    // MARK: Inlines

    private static func emitInlines(_ block: Block, base: TextStyle.Role, isActive: Bool, into result: inout StyleResult) {
        let marker = TextStyle(role: .marker)
        let styling = block.inlines.filter {
            switch $0.kind {
            case .strong, .emphasis, .strikethrough: true
            default: false
            }
        }
        // Outer spans first so inner runs, which carry the merged flags, win.
        for span in block.inlines.sorted(by: { $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.range.length > $1.range.length }) {
            switch span.kind {
            case .strong, .emphasis, .strikethrough:
                let inner = innerRange(of: span)
                guard inner.length > 0 else { break }
                var style = TextStyle(role: base)
                for other in styling where NSIntersectionRange(other.range, inner).length == inner.length {
                    switch other.kind {
                    case .strong: style.bold = true
                    case .emphasis: style.italic = true
                    case .strikethrough: style.strikethrough = true
                    default: break
                    }
                }
                result.runs.append(StyleRun(range: inner, style: style))
            case .inlineCode:
                let inner = innerRange(of: span)
                result.runs.append(StyleRun(range: inner, style: TextStyle(role: .codeInline)))
                result.decorations.append(.inlineCodeBackground(inner))
            case .link:
                let inner = linkTextRange(of: span)
                result.runs.append(StyleRun(range: inner, style: TextStyle(role: .link)))
            case .bareURL:
                result.runs.append(StyleRun(range: span.range, style: TextStyle(role: .link)))
            case .image(let source):
                result.decorations.append(.image(source: source, lineRange: block.range))
            case .tag:
                result.runs.append(StyleRun(range: span.range, style: TextStyle(role: .tag)))
                result.decorations.append(.tagPill(span.range))
            }
            for syntax in span.syntaxRanges where syntax.length > 0 {
                if isActive {
                    result.runs.append(StyleRun(range: syntax, style: marker))
                } else {
                    result.hidden.append(syntax)
                }
            }
        }
    }

    /// The span without its first and last syntax ranges (e.g. the text between `**` markers).
    private static func innerRange(of span: InlineSpan) -> NSRange {
        guard span.syntaxRanges.count == 2 else { return span.range }
        let start = NSMaxRange(span.syntaxRanges[0])
        return NSRange(location: start, length: max(span.syntaxRanges[1].location - start, 0))
    }

    private static func linkTextRange(of span: InlineSpan) -> NSRange { innerRange(of: span) }

    // MARK: Tables, frontmatter

    private static func emitTable(_ block: Block, text: NSString, into result: inout StyleResult) {
        result.runs.append(StyleRun(range: block.range, style: TextStyle(role: .codeInline)))
        let marker = TextStyle(role: .marker)
        var location = block.range.location
        var lineNumber = 0
        while location < NSMaxRange(block.range) {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: start, length: min(contentsEnd, NSMaxRange(block.range)) - start)
            if lineNumber == 1 {
                result.runs.append(StyleRun(range: line, style: marker))
            } else {
                for offset in 0..<line.length where text.character(at: line.location + offset) == 0x7C {  // "|"
                    result.runs.append(StyleRun(range: NSRange(location: line.location + offset, length: 1), style: marker))
                }
            }
            lineNumber += 1
            location = end
        }
    }

    /// Top-level `key:` lines between the frontmatter fences.
    private static func frontmatterKeyCount(_ range: NSRange, text: NSString) -> Int {
        let lines = text.substring(with: range).components(separatedBy: "\n").dropFirst().dropLast()
        return lines.filter { line in
            guard let first = line.first, first != " ", first != "\t", first != "-", first != "#" else { return false }
            return line.contains(":")
        }.count
    }

    private static func subtract(_ removed: [NSRange], from range: NSRange) -> [NSRange] {
        var pieces: [NSRange] = []
        var cursor = range.location
        for hole in removed.sorted(by: { $0.location < $1.location }) {
            if hole.location > cursor { pieces.append(NSRange(location: cursor, length: hole.location - cursor)) }
            cursor = max(cursor, NSMaxRange(hole))
        }
        if cursor < NSMaxRange(range) { pieces.append(NSRange(location: cursor, length: NSMaxRange(range) - cursor)) }
        return pieces
    }
}
