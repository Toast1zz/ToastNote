import Foundation
import Markdown

/// Turns a Markdown tree into HTML. swift-markdown's own `HTMLFormatter` writes code and raw HTML through
/// unescaped and wraps every list item in a paragraph, so the export uses this writer instead (spec §14).
/// Raw HTML in a note is never passed through: it is shown as text.
struct HTMLWriter: MarkupVisitor {
    typealias Result = String

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private mutating func children(of markup: Markup) -> String {
        var result = ""
        for child in markup.children { result += visit(child) }
        return result
    }

    mutating func defaultVisit(_ markup: Markup) -> String { children(of: markup) }

    mutating func visitDocument(_ document: Document) -> String { children(of: document) }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        return "<h\(level)>\(children(of: heading))</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String { "<p>\(children(of: paragraph))</p>\n" }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String { "<blockquote>\n\(children(of: blockQuote))</blockquote>\n" }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String { "<hr>\n" }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let language = codeBlock.language.flatMap { $0.isEmpty ? nil : " class=\"language-\(Self.escape($0))\"" } ?? ""
        return "<pre><code\(language)>\(Self.escape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String { "<p>\(Self.escape(html.rawHTML))</p>\n" }

    // MARK: Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> String { "<ul>\n\(children(of: list))</ul>\n" }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
        return "<ol\(start)>\n\(children(of: list))</ol>\n"
    }

    mutating func visitListItem(_ item: ListItem) -> String {
        var result = "<li>"
        switch item.checkbox {
        case .checked?: result += "<input type=\"checkbox\" checked disabled> "
        case .unchecked?: result += "<input type=\"checkbox\" disabled> "
        case nil: break
        }
        for child in item.children {
            // Items render tight: their paragraph is inline content, not a block.
            if let paragraph = child as? Paragraph { result += children(of: paragraph) } else { result += "\n" + visit(child) }
        }
        return result + "</li>\n"
    }

    // MARK: Tables

    mutating func visitTable(_ table: Markdown.Table) -> String {
        let alignments = table.columnAlignments
        func cells(_ row: Markup, tag: String) -> String {
            var html = "<tr>"
            for (index, cell) in row.children.enumerated() {
                let align: String
                switch index < alignments.count ? alignments[index] : nil {
                case .left?: align = " style=\"text-align: left\""
                case .center?: align = " style=\"text-align: center\""
                case .right?: align = " style=\"text-align: right\""
                case nil: align = ""
                }
                html += "<\(tag)\(align)>\(children(of: cell))</\(tag)>"
            }
            return html + "</tr>\n"
        }
        var html = "<table>\n<thead>\n" + cells(table.head, tag: "th") + "</thead>\n<tbody>\n"
        for row in table.body.children { html += cells(row, tag: "td") }
        return html + "</tbody>\n</table>\n"
    }

    // MARK: Inlines

    mutating func visitText(_ text: Markdown.Text) -> String { Self.escape(text.string) }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }
    mutating func visitStrong(_ strong: Strong) -> String { "<strong>\(children(of: strong))</strong>" }
    mutating func visitEmphasis(_ emphasis: Emphasis) -> String { "<em>\(children(of: emphasis))</em>" }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String { "<del>\(children(of: strikethrough))</del>" }
    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String { "<code>\(Self.escape(inlineCode.code))</code>" }
    mutating func visitInlineHTML(_ html: InlineHTML) -> String { Self.escape(html.rawHTML) }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        "<a href=\"\(Self.escape(link.destination ?? ""))\">\(children(of: link))</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        "<img src=\"\(Self.escape(image.source ?? ""))\" alt=\"\(Self.escape(image.plainText))\">"
    }
}
