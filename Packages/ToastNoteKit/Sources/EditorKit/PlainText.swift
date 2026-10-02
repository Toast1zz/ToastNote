import Foundation
import Markdown

/// Markdown reduced to the words a reader sees: syntax disappears, text, code and table cells stay.
/// Shared by the content guard and the block diff so both compare the same thing.
public enum PlainText {
    /// Leading list numbers, bullets and heading marks are syntax once formatted but plain characters in
    /// unformatted notes ("1 上线"), so they are dropped from both sides before comparing.
    private static let leadingMarkers = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:>[ \t]*)*(?:#{1,6}[ \t]+|(?:[-*+•·]|\d+[.)、]?)[ \t]+(?:\[[ xX]\][ \t]+)?)"#,
        options: [.anchorsMatchLines]
    )

    public static func extract(_ markdown: String) -> String {
        var walker = Walker()
        walker.visit(Document(parsing: stripLeadingMarkers(markdown)))
        return walker.text
    }

    static func stripLeadingMarkers(_ markdown: String) -> String {
        let range = NSRange(location: 0, length: (markdown as NSString).length)
        return leadingMarkers.stringByReplacingMatches(in: markdown, range: range, withTemplate: "")
    }

    private struct Walker: MarkupWalker {
        var text = ""

        mutating func visitText(_ text: Markdown.Text) { self.text += text.string }
        mutating func visitInlineCode(_ inlineCode: InlineCode) { text += inlineCode.code }
        mutating func visitCodeBlock(_ codeBlock: CodeBlock) { text += codeBlock.code + "\n" }
        mutating func visitSoftBreak(_ softBreak: SoftBreak) { text += "\n" }
        mutating func visitLineBreak(_ lineBreak: LineBreak) { text += "\n" }
        mutating func visitInlineHTML(_ html: InlineHTML) {}
        mutating func visitHTMLBlock(_ html: HTMLBlock) {}
        mutating func visitParagraph(_ paragraph: Paragraph) { descendInto(paragraph); text += "\n" }
        mutating func visitHeading(_ heading: Heading) { descendInto(heading); text += "\n" }
        mutating func visitTableCell(_ cell: Markdown.Table.Cell) { descendInto(cell); text += "\n" }
    }
}
