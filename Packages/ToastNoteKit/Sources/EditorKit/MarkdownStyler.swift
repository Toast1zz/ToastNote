import Foundation

/// One row of a rendered table: the visible cell contents and the inner pipes between them.
public struct TableRow: Equatable, Sendable {
    public var line: NSRange
    public var cells: [NSRange]
    /// Inner pipes kept as invisible spacers; the view widens each so the next cell starts on its column.
    public var spacers: [Int]
    public var isHeader: Bool
    /// The opening pipe, kept as a zero-width stand-in: leading hidden glyphs would ride on the previous line
    /// fragment and put the row's text on a continuation line (which uses the wrap indent).
    public var leadingPipe: Int?

    public init(line: NSRange, cells: [NSRange], spacers: [Int], isHeader: Bool, leadingPipe: Int? = nil) {
        self.line = line
        self.cells = cells
        self.spacers = spacers
        self.isHeader = isHeader
        self.leadingPipe = leadingPipe
    }
}

public struct TableLayout: Equatable, Sendable {
    public var range: NSRange
    public var rows: [TableRow]

    public init(range: NSRange, rows: [TableRow]) {
        self.range = range
        self.rows = rows
    }
}

public enum Decoration: Equatable, Sendable {
    case bullet(at: Int, depth: Int)
    /// The number of an ordered item ("1." or "1)"), drawn right-aligned in the list gutter.
    case orderedNumber(String, at: Int, depth: Int)
    case table(TableLayout)
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
    /// - Parameter resolveImage: whether an image source points at a file; images that do not stay visible as
    ///   muted source text instead of vanishing.
    public static func style(
        blocks: [Block], text: NSString, active: IndexSet, concealAll: Bool = false,
        resolveImage: (String) -> Bool = { _ in true }
    ) -> StyleResult {
        var result = StyleResult()
        for (index, block) in blocks.enumerated() {
            let isActive = !concealAll && active.contains(index)
            emit(block, text: text, isActive: isActive, resolveImage: resolveImage, into: &result)
        }
        emitBlankLines(blocks: blocks, text: text, into: &result)
        return result
    }

    /// Blank lines are real empty paragraphs; give them a short line so they do not double paragraph gaps.
    private static func emitBlankLines(blocks: [Block], text: NSString, into result: inout StyleResult) {
        var cursor = 0
        var previous: Block?
        func isBox(_ block: Block?) -> Bool {
            switch block?.kind {
            case .codeBlock?, .table?: true
            default: false
            }
        }
        func scan(upTo end: Int, before next: Block?) {
            var kind = BlankLine.plain
            if case .heading(let level)? = next?.kind {
                kind = .beforeHeading(level, afterBox: isBox(previous))
            } else if isBox(next) || isBox(previous) {
                kind = .besideBox
            }
            var index = cursor
            while index < min(end, text.length) {
                // A blank line is a newline that starts its line.
                if text.character(at: index) == 0x0A, index == 0 || text.character(at: index - 1) == 0x0A {
                    result.runs.append(StyleRun(range: NSRange(location: index, length: 1), style: TextStyle(role: .body, blankLine: kind)))
                }
                index += 1
            }
        }
        for block in blocks.sorted(by: { $0.range.location < $1.range.location }) {
            scan(upTo: block.range.location, before: block)
            // Skip the block's own line terminator.
            cursor = max(cursor, NSMaxRange(block.range) + 1)
            previous = block
        }
        scan(upTo: text.length, before: nil)
    }

    // MARK: Per block

    private static func emit(_ block: Block, text: NSString, isActive: Bool, resolveImage: (String) -> Bool, into result: inout StyleResult) {
        let base = baseRole(of: block)

        switch block.kind {
        case .frontmatter:
            if isActive {
                result.runs.append(StyleRun(range: block.range, style: TextStyle(role: .codeInline)))
            } else {
                // The first "-" stays as an invisible stand-in so the summary gets a line of its own.
                result.hidden.append(NSRange(location: block.range.location + 1, length: block.range.length - 1))
                result.runs.append(StyleRun(range: NSRange(location: block.range.location, length: 1), style: TextStyle(role: .frontmatterPlaceholder)))
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
                // One stand-in character keeps the rule's line; fully hidden it would ride on the line above.
                result.hidden.append(NSRange(location: block.range.location + 1, length: block.range.length - 1))
                result.runs.append(StyleRun(range: NSRange(location: block.range.location, length: 1), style: TextStyle(role: .rulePlaceholder)))
                result.decorations.append(.rule(block.range))
            }
            return
        case .table:
            if isActive {
                emitTableSource(block, text: text, into: &result)
            } else {
                emitTableGrid(block, text: text, into: &result)
            }
            return
        default:
            break
        }

        // Paragraph-level attributes (spacing, indents) come from a paragraph's first character, which is
        // often a marker, so the base style covers the whole block, not just its visible content.
        var listDepth: Int?
        var isListItem = false
        var runRange = block.range
        if case .listItem(_, _, let depth) = block.kind {
            isListItem = true
            // Inactive items are indented by paragraph style, so the source indentation is hidden. The
            // indentation joins the block run so the paragraph style starts at the line's first character.
            let lead = leadingWhitespace(before: block.range.location, in: text)
            runRange = NSRange(location: lead.location, length: NSMaxRange(block.range) - lead.location)
            listDepth = isActive ? 0 : depth
            if !isActive, lead.length > 0 { result.hidden.append(lead) }
        }
        let blockStyle = TextStyle(role: base, listDepth: listDepth, tightSpacing: isListItem)
        if runRange.length > 0 {
            result.runs.append(StyleRun(range: runRange, style: blockStyle))
        }
        for segment in contentSegments(of: block) where segment.length > 0 {
            result.runs.append(StyleRun(range: segment, style: blockStyle))
        }

        emitBlockSyntax(block, text: text, isActive: isActive, into: &result)
        emitInlines(block, base: base, isActive: isActive, resolveImage: resolveImage, into: &result)

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
        let hideMarkers = !isActive
        var decoration: Decoration?
        if case .listItem(let ordered, let task, let depth) = block.kind, let syntax = block.syntaxRanges.first, !isActive {
            if let task {
                decoration = .checkbox(at: syntax.location, done: task == .done)
            } else if ordered {
                let number = text.substring(with: syntax).trimmingCharacters(in: .whitespaces)
                decoration = .orderedNumber(number, at: syntax.location, depth: depth)
            } else {
                decoration = .bullet(at: syntax.location, depth: depth)
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

    private static func emitInlines(_ block: Block, base: TextStyle.Role, isActive: Bool, resolveImage: (String) -> Bool, into result: inout StyleResult) {
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
                // Only a line that is nothing but an image is drawn as a picture; inside a sentence it stays text.
                guard block.range == span.range, resolveImage(source) else {
                    result.runs.append(StyleRun(range: span.range, style: marker))
                    continue
                }
                if !isActive {
                    // Keep "!" so the line exists (a paragraph of only hidden glyphs gets no line fragment).
                    result.hidden.append(NSRange(location: span.range.location + 1, length: span.range.length - 1))
                    result.runs.append(StyleRun(range: NSRange(location: span.range.location, length: 1), style: TextStyle(role: .imagePlaceholder)))
                    result.decorations.append(.image(source: source, lineRange: block.range))
                    continue
                }
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

    /// Inactive tables render as a grid: outer pipes, cell padding and the delimiter row are hidden, inner pipes
    /// stay as spacers, the header row is bold, and the view lines the columns up and draws the rules.
    private static func emitTableGrid(_ block: Block, text: NSString, into result: inout StyleResult) {
        result.runs.append(StyleRun(range: block.range, style: TextStyle(role: .body, tableRow: true)))
        var rows: [TableRow] = []
        var location = block.range.location
        var lineNumber = 0
        while location < NSMaxRange(block.range) {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = NSRange(location: start, length: min(contentsEnd, NSMaxRange(block.range)) - start)
            if lineNumber == 1 {
                // The delimiter row goes with its line break, like a code fence.
                result.hidden.append(NSRange(location: line.location, length: min(end, NSMaxRange(block.range) + 1) - line.location))
            } else {
                let row = tableRow(line, text: text, isHeader: lineNumber == 0)
                rows.append(row)
                let kept = row.cells + (row.spacers + [row.leadingPipe].compactMap { $0 }).map { NSRange(location: $0, length: 1) }
                result.hidden.append(contentsOf: subtract(kept, from: line))
                for cell in row.cells where cell.length > 0 {
                    result.runs.append(StyleRun(range: cell, style: TextStyle(role: .body, bold: row.isHeader, tableRow: true)))
                }
                for spacer in row.spacers + [row.leadingPipe].compactMap({ $0 }) {
                    result.runs.append(StyleRun(range: NSRange(location: spacer, length: 1), style: TextStyle(role: .tableSpacer, bold: row.isHeader, tableRow: true)))
                }
            }
            lineNumber += 1
            location = end
        }
        result.decorations.append(.table(TableLayout(range: block.range, rows: rows)))
    }

    /// Cells are the text between unescaped pipes, trimmed; a leading or trailing pipe opens or closes the row.
    private static func tableRow(_ line: NSRange, text: NSString, isHeader: Bool) -> TableRow {
        var pipes: [Int] = []
        var index = line.location
        while index < NSMaxRange(line) {
            let character = text.character(at: index)
            if character == 0x5C {  // a backslash escapes the next character
                index += 2
                continue
            }
            if character == 0x7C { pipes.append(index) }
            index += 1
        }
        var segments: [NSRange] = []
        var cursor = line.location
        for pipe in pipes {
            segments.append(NSRange(location: cursor, length: pipe - cursor))
            cursor = pipe + 1
        }
        segments.append(NSRange(location: cursor, length: NSMaxRange(line) - cursor))
        var boundaries = pipes
        var leadingPipe: Int?
        func isBlank(_ range: NSRange) -> Bool {
            text.substring(with: range).trimmingCharacters(in: .whitespaces).isEmpty
        }
        if segments.count > 1, isBlank(segments[0]) {
            segments.removeFirst()
            leadingPipe = boundaries.removeFirst()
        }
        if segments.count > 1, isBlank(segments[segments.count - 1]) {
            segments.removeLast()
            boundaries.removeLast()
        }
        return TableRow(line: line, cells: segments.map { trimmed($0, in: text) }, spacers: boundaries, isHeader: isHeader, leadingPipe: leadingPipe)
    }

    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        func isSpace(_ index: Int) -> Bool { text.character(at: index) == 0x20 || text.character(at: index) == 0x09 }
        var start = range.location, end = NSMaxRange(range)
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// While edited, a table shows its source: monospaced, pipes and the delimiter row muted.
    private static func emitTableSource(_ block: Block, text: NSString, into result: inout StyleResult) {
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
