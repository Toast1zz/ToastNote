import Foundation
import Markdown

public enum BlockParser {
    public static func parse(_ text: String) -> [Block] {
        guard !text.isEmpty else { return [] }
        var blocks: [Block] = []

        // swift-markdown has no frontmatter support: detect it first, then parse the rest.
        let (frontmatter, body) = FrontmatterParser.split(text)
        if let frontmatter {
            blocks.append(Block(kind: .frontmatter, range: frontmatter, syntaxRanges: [frontmatter], contentRange: frontmatter))
        }
        let bodyString = String(body)
        let baseOffset = text.utf16.count - bodyString.utf16.count
        let converter = Converter(full: text as NSString, body: bodyString, baseOffset: baseOffset)
        let document = Document(parsing: bodyString)
        for child in document.children {
            blocks.append(contentsOf: converter.blocks(for: child, listDepth: 0))
        }
        return blocks.sorted { $0.range.location < $1.range.location }
    }
}

private struct Converter {
    let full: NSString
    let lineIndex: LineIndex
    let baseOffset: Int

    init(full: NSString, body: String, baseOffset: Int) {
        self.full = full
        self.lineIndex = LineIndex(body)
        self.baseOffset = baseOffset
    }

    // MARK: Ranges

    func range(of markup: Markup) -> NSRange? {
        guard let source = markup.range else { return nil }
        var result = lineIndex.nsRange(source)
        result.location += baseOffset
        return trimTrailingNewlines(result)
    }

    private func trimTrailingNewlines(_ range: NSRange) -> NSRange {
        var result = range
        while result.length > 0, result.location + result.length <= full.length,
              full.character(at: result.location + result.length - 1) == 0x0A {
            result.length -= 1
        }
        return result
    }

    /// The line containing `location`, without its line terminator.
    private func lineRange(containing location: Int) -> NSRange {
        var start = 0, end = 0, contentsEnd = 0
        full.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(location, full.length), length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    private func substring(_ range: NSRange) -> String {
        guard range.location >= 0, NSMaxRange(range) <= full.length else { return "" }
        return full.substring(with: range)
    }

    // MARK: Blocks

    func blocks(for markup: Markup, listDepth: Int) -> [Block] {
        guard let range = range(of: markup) else { return [] }
        switch markup {
        case let heading as Heading:
            return [headingBlock(heading, range: range)]
        case let list as UnorderedList:
            return listBlocks(Array(list.listItems), ordered: false, depth: listDepth)
        case let list as OrderedList:
            return listBlocks(Array(list.listItems), ordered: true, depth: listDepth)
        case let code as CodeBlock:
            return [codeBlock(code, range: range)]
        case is ThematicBreak:
            return [Block(kind: .thematicBreak, range: range, syntaxRanges: [range], contentRange: range)]
        case is Table:
            return [Block(kind: .table, range: range, syntaxRanges: [], contentRange: range)]
        case is BlockQuote:
            return [quoteBlock(markup, range: range)]
        default:
            return [finish(Block(kind: .paragraph, range: range, syntaxRanges: [], contentRange: range), markup: markup)]
        }
    }

    private func headingBlock(_ heading: Heading, range: NSRange) -> Block {
        var syntax: [NSRange] = []
        var content = range
        if substring(NSRange(location: range.location, length: min(1, range.length))) == "#" {
            let markerEnd = heading.child(at: 0).flatMap { self.range(of: $0)?.location } ?? NSMaxRange(range)
            syntax = [NSRange(location: range.location, length: markerEnd - range.location)]
            content = NSRange(location: markerEnd, length: NSMaxRange(range) - markerEnd)
        }
        return finish(Block(kind: .heading(level: heading.level), range: range, syntaxRanges: syntax, contentRange: content), markup: heading)
    }

    private func quoteBlock(_ quote: Markup, range: NSRange) -> Block {
        var syntax: [NSRange] = []
        var location = range.location
        while location < NSMaxRange(range) {
            let line = lineRange(containing: location)
            let text = substring(line) as NSString
            var index = 0
            while index < text.length, index < 3, text.character(at: index) == 0x20 { index += 1 }
            if index < text.length, text.character(at: index) == 0x3E {  // ">"
                var length = index + 1
                if length < text.length, text.character(at: length) == 0x20 { length += 1 }
                syntax.append(NSRange(location: line.location + index, length: length - index))
            }
            location = NSMaxRange(line) + 1
        }
        return finish(Block(kind: .quote, range: range, syntaxRanges: syntax, contentRange: range), markup: quote)
    }

    private func codeBlock(_ code: CodeBlock, range: NSRange) -> Block {
        let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
        let firstLine = lineRange(containing: range.location)
        let firstText = substring(firstLine).trimmingCharacters(in: .whitespaces)
        guard firstText.hasPrefix("```") || firstText.hasPrefix("~~~") else {
            return Block(kind: .codeBlock(language: language), range: range, syntaxRanges: [], contentRange: range)  // indented code
        }
        var syntax = [NSRange(location: firstLine.location, length: min(firstLine.length, range.length))]
        var contentEnd = NSMaxRange(range)
        let lastLine = lineRange(containing: max(NSMaxRange(range) - 1, range.location))
        let fence = firstText.hasPrefix("```") ? "```" : "~~~"
        if lastLine.location > firstLine.location, substring(lastLine).trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
            syntax.append(lastLine)
            contentEnd = max(lastLine.location - 1, NSMaxRange(firstLine))
        }
        let contentStart = min(NSMaxRange(firstLine) + 1, contentEnd)
        return Block(
            kind: .codeBlock(language: language), range: range, syntaxRanges: syntax,
            contentRange: NSRange(location: contentStart, length: contentEnd - contentStart)
        )
    }

    private func listBlocks(_ items: [ListItem], ordered: Bool, depth: Int) -> [Block] {
        var result: [Block] = []
        for item in items {
            guard let itemRange = range(of: item) else { continue }
            let children = Array(item.children)
            var task: TaskState?
            switch item.checkbox {
            case .checked: task = .done
            case .unchecked: task = .open
            case nil: task = nil
            }
            // The item's own block ends with its first paragraph; nested content becomes separate blocks.
            let first = children.first
            let firstRange = first.flatMap { range(of: $0) }
            let markerEnd = firstRange?.location ?? NSMaxRange(itemRange)
            let ownEnd = (first is Paragraph) ? NSMaxRange(firstRange!) : markerEnd
            let own = NSRange(location: itemRange.location, length: max(ownEnd - itemRange.location, 0))
            let syntax = NSRange(location: itemRange.location, length: max(markerEnd - itemRange.location, 0))
            let block = Block(
                kind: .listItem(ordered: ordered, task: task, depth: depth), range: own,
                syntaxRanges: [syntax], contentRange: NSRange(location: markerEnd, length: max(ownEnd - markerEnd, 0))
            )
            // Only a leading paragraph contributes inlines; other children become their own blocks.
            result.append(finish(block, markup: first as? Paragraph))
            for child in children.dropFirst(first is Paragraph ? 1 : 0) {
                result.append(contentsOf: blocks(for: child, listDepth: depth + 1))
            }
        }
        return result
    }

    // MARK: Inlines

    /// Adds inline spans (and tags) to a block.
    private func finish(_ block: Block, markup: Markup?) -> Block {
        guard let markup else { return block }
        var block = block
        var spans: [InlineSpan] = []
        collectInlines(markup, into: &spans)
        // Tags are found over the block text so the "preceded by whitespace" rule sees real neighbors.
        let excluded = spans.filter { span in
            switch span.kind {
            case .inlineCode, .link, .image, .bareURL: true
            default: false
            }
        }.map(\.range)
        let blockText = substring(block.range)
        let local = excluded.map { NSRange(location: $0.location - block.range.location, length: $0.length) }
        // Block-level markers ("# ", "- ") are not tag text.
        let markerLocal = block.syntaxRanges.map { NSRange(location: $0.location - block.range.location, length: $0.length) }
        for tag in TagParser.tags(in: blockText, excluding: local + markerLocal) {
            let range = NSRange(location: tag.range.location + block.range.location, length: tag.range.length)
            spans.append(InlineSpan(kind: .tag(tag.tag), range: range))
        }
        block.inlines = spans.sorted { $0.range.location < $1.range.location }
        return block
    }

    /// The raw range cmark-gfm reported for a styled span and the text inside its markers.
    private typealias StyledParent = (raw: NSRange, inner: NSRange)

    private func collectInlines(_ markup: Markup, into spans: inout [InlineSpan], parent: StyledParent? = nil) {
        for child in markup.children {
            guard let rawRange = range(of: child) else { continue }
            // For `***x***` cmark-gfm reports the same range for the emphasis and the strong inside it;
            // the inner span really starts after the outer span's markers.
            var childRange = rawRange
            if let parent, rawRange == parent.raw, child is Strong || child is Emphasis || child is Strikethrough {
                childRange = parent.inner
            }
            switch child {
            case is Strong:
                let syntax = wrapped(childRange, marker: 2)
                spans.append(InlineSpan(kind: .strong, range: childRange, syntaxRanges: syntax))
                collectInlines(child, into: &spans, parent: (rawRange, innerOf(childRange, marker: 2)))
            case is Emphasis:
                spans.append(InlineSpan(kind: .emphasis, range: childRange, syntaxRanges: wrapped(childRange, marker: 1)))
                collectInlines(child, into: &spans, parent: (rawRange, innerOf(childRange, marker: 1)))
            case is Strikethrough:
                let marker = substring(NSRange(location: childRange.location, length: min(2, childRange.length))) == "~~" ? 2 : 1
                spans.append(InlineSpan(kind: .strikethrough, range: childRange, syntaxRanges: wrapped(childRange, marker: marker)))
                collectInlines(child, into: &spans, parent: (rawRange, innerOf(childRange, marker: marker)))
            case is InlineCode:
                var ticks = 0
                while ticks < childRange.length, full.character(at: childRange.location + ticks) == 0x60 { ticks += 1 }
                spans.append(InlineSpan(kind: .inlineCode, range: childRange, syntaxRanges: wrapped(childRange, marker: max(ticks, 1))))
            case let link as Link:
                if substring(NSRange(location: childRange.location, length: min(1, childRange.length))) == "[" {
                    let textEnd = link.children.reversed().lazy.compactMap { range(of: $0) }.first.map(NSMaxRange) ?? childRange.location + 1
                    let syntax = [
                        NSRange(location: childRange.location, length: 1),
                        NSRange(location: textEnd, length: NSMaxRange(childRange) - textEnd),
                    ]
                    spans.append(InlineSpan(kind: .link(url: link.destination ?? ""), range: childRange, syntaxRanges: syntax))
                } else {
                    spans.append(InlineSpan(kind: .bareURL(substring(childRange)), range: childRange))
                }
            case let image as Image:
                spans.append(InlineSpan(kind: .image(source: image.source ?? ""), range: childRange, syntaxRanges: [childRange]))
            case let text as Text:
                collectBareURLs(in: text.string, range: childRange, into: &spans)
            default:
                collectInlines(child, into: &spans)
            }
        }
    }

    private func innerOf(_ range: NSRange, marker: Int) -> NSRange {
        NSRange(location: range.location + marker, length: max(range.length - marker * 2, 0))
    }

    private func wrapped(_ range: NSRange, marker: Int) -> [NSRange] {
        guard range.length >= marker * 2 else { return [] }
        return [
            NSRange(location: range.location, length: marker),
            NSRange(location: NSMaxRange(range) - marker, length: marker),
        ]
    }

    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>\[\]()]+"#)

    /// Fallback for URLs the Markdown parser left as plain text.
    private func collectBareURLs(in string: String, range: NSRange, into spans: inout [InlineSpan]) {
        // The Text node's own range is the source of truth for offsets; its string may differ (escapes).
        let source = substring(range)
        let ns = source as NSString
        for match in Self.urlPattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            var matched = match.range
            while matched.length > 0, ".,;:!?'\"，。；：！？".contains(ns.character(at: NSMaxRange(matched) - 1).asScalarString) {
                matched.length -= 1
            }
            guard matched.length > 0 else { continue }
            spans.append(InlineSpan(
                kind: .bareURL(ns.substring(with: matched)),
                range: NSRange(location: range.location + matched.location, length: matched.length)
            ))
        }
    }
}

private extension unichar {
    var asScalarString: Character { Character(Unicode.Scalar(self) ?? " ") }
}
