import AppKit
import Foundation

/// What a blank line sits next to. A heading has no space of its own in front (a `paragraphSpacingBefore`
/// would come and go with its hidden `#` marker and make the text jump), so the blank line in front of it
/// carries that space; boxed blocks (code, tables) get the same air above and below.
public enum BlankLine: Hashable, Sendable {
    case plain, besideBox
    /// After a code block or table the heading also gets the air a box keeps below itself.
    case beforeHeading(Int, afterBox: Bool = false)
}

public struct TextStyle: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case body, heading(Int), codeInline, codeBlock, quote, link, tag, marker, taskDone, frontmatterSummary, imagePlaceholder
        /// Invisible one-character stand-ins that give a hidden block its own line (a paragraph of only hidden
        /// glyphs gets no line fragment), and the inner table pipes the view widens to the column width.
        case rulePlaceholder, frontmatterPlaceholder, tableSpacer
    }

    public var role: Role
    public var bold = false
    public var italic = false
    public var strikethrough = false
    /// Bullet and task items reserve a gutter (one per nesting level) in front of the text for the drawn bullet or checkbox.
    public var listDepth: Int?
    /// List items sit closer together than paragraphs.
    public var tightSpacing = false
    /// A blank line between blocks; kept short so it does not double the paragraph gap.
    public var blankLine: BlankLine?
    /// A row of a rendered table: padded on the left and evenly spaced.
    public var tableRow = false
    /// The source in front of an edited list item's text (indentation and marker). It hangs in the gutter, so
    /// the text starts where it does while the bullet is drawn instead.
    public var hangingPrefix: String?

    public init(
        role: Role, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false,
        listDepth: Int? = nil, tightSpacing: Bool = false, blankLine: BlankLine? = nil, tableRow: Bool = false,
        hangingPrefix: String? = nil
    ) {
        self.role = role
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.listDepth = listDepth
        self.tightSpacing = tightSpacing
        self.blankLine = blankLine
        self.tableRow = tableRow
        self.hangingPrefix = hangingPrefix
    }
}

public struct EditorTheme: Sendable, Equatable {
    /// 13...20, spec §9.3.
    public var bodySize: CGFloat = 15
    /// The widest the text column grows, 600...1200. It follows the window up to this cap (see `horizontalInset`).
    public var maxContentWidth: CGFloat = 960

    /// With the system's "Increase contrast" setting, secondary text uses the primary label color (spec §9.7).
    public var increasedContrast = false

    public static let `default` = EditorTheme()

    public init(bodySize: CGFloat = 15, maxContentWidth: CGFloat = 960, increasedContrast: Bool = false) {
        self.bodySize = min(max(bodySize, 13), 20)
        self.maxContentWidth = min(max(maxContentWidth, 600), 1200)
        self.increasedContrast = increasedContrast
    }

    private var secondaryColor: NSColor { increasedContrast ? .labelColor : .secondaryLabelColor }

    /// Space on each side of the text column for a view `width` points wide. The sides are 12% of the width, so
    /// the column grows with the window; wide windows stop at `maxContentWidth` and center the column, and
    /// narrow ones keep at least 48 pt (spec §9.3, made adaptive).
    public func horizontalInset(forWidth width: CGFloat) -> CGFloat {
        let proportional = max(48, (0.12 * width).rounded(.down))
        return max(proportional, ((width - maxContentWidth) / 2).rounded(.down))
    }

    private var scale: CGFloat { bodySize / 15 }

    /// 28/22/19/16/16/16 scaled by bodySize / 15.
    public func headingSize(_ level: Int) -> CGFloat {
        let sizes: [CGFloat] = [28, 22, 19, 16, 16, 16]
        return sizes[min(max(level, 1), 6) - 1] * scale
    }

    private var codeSize: CGFloat { 13 * scale }

    /// Attributes for a style. `.marker` only sets a color so it layers over the block's font.
    public func attributes(for style: TextStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        switch style.role {
        case .body:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = NSColor.labelColor
        case .heading(let level):
            let weight: NSFont.Weight = level == 1 ? .bold : .semibold
            attributes[.font] = font(size: headingSize(level), weight: weight, style: style)
            attributes[.foregroundColor] = NSColor.labelColor
            if level == 1 { attributes[.kern] = -0.01 * headingSize(1) }  // -0.01 em, spec §9.3
        case .codeInline, .codeBlock:
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: codeSize, weight: style.bold ? .bold : .regular)
            attributes[.foregroundColor] = NSColor.labelColor
        case .quote:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = secondaryColor
        case .link, .tag:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = NSColor.controlAccentColor
            // A tag or link inside a done task keeps its pill or color legible.
            attributes[.strikethroughStyle] = 0
        case .marker:
            attributes[.foregroundColor] = secondaryColor
        case .taskDone:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = secondaryColor
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        case .frontmatterSummary:
            attributes[.font] = NSFont.systemFont(ofSize: bodySize)
            attributes[.foregroundColor] = secondaryColor
        case .imagePlaceholder, .rulePlaceholder, .frontmatterPlaceholder:
            // The picture, rule or summary is drawn over this character's line; the character itself must not show.
            attributes[.font] = NSFont.systemFont(ofSize: 1)
            attributes[.foregroundColor] = NSColor.clear
        case .tableSpacer:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = NSColor.clear
        }
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        // Markers inherit the paragraph style of the content they sit next to.
        if style.role != .marker { attributes[.paragraphStyle] = paragraphStyle(for: style) }
        return attributes
    }

    /// Width reserved in front of bullet and task items.
    var listGutter: CGFloat { 1.5 * bodySize }
    /// Inner padding of code blocks and left indent of quotes (spec §9.3).
    var codePadding: CGFloat { 12 }
    var quoteIndent: CGFloat { 16 }

    /// Line height and spacing live in NSParagraphStyle, never in extra blank lines (spec §9.3).
    func paragraphStyle(for style: TextStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        if let blank = style.blankLine {
            let height: CGFloat = switch blank {
            case .plain: 0.5 * bodySize
            case .beforeHeading(let level, let afterBox): headingSpacing(level).before * headingSize(level) + (afterBox ? 0.6 * bodySize : 0)
            case .besideBox: 1.3 * bodySize
            }
            paragraph.minimumLineHeight = height
            paragraph.maximumLineHeight = height
            return paragraph
        }
        switch style.role {
        case .heading(let level):
            let after = headingSpacing(level).after
            let size = headingSize(level)
            setLineHeight(paragraph, 1.35 * size)
            // No `paragraphSpacingBefore`: the blank line in front carries the gap (see `BlankLine`). A heading's
            // own gap would only apply while its `#` is visible (or after a relayout), so the text would jump
            // every time the caret enters or leaves a heading.
            paragraph.paragraphSpacing = after * size
        case .codeBlock:
            setLineHeight(paragraph, 1.5 * codeSize)
            paragraph.firstLineHeadIndent = codePadding
            paragraph.headIndent = codePadding
            paragraph.tailIndent = -codePadding
        case .codeInline:
            setLineHeight(paragraph, 1.5 * codeSize)
        case .rulePlaceholder:
            setLineHeight(paragraph, 1.5 * bodySize)
        case .frontmatterPlaceholder:
            setLineHeight(paragraph, 1.75 * bodySize)
            paragraph.paragraphSpacing = 1.2 * bodySize
        case _ where style.tableRow:
            setLineHeight(paragraph, 2 * bodySize)
            paragraph.firstLineHeadIndent = codePadding
            paragraph.headIndent = codePadding
        case .quote:
            setLineHeight(paragraph, 1.75 * bodySize)
            paragraph.paragraphSpacing = style.tightSpacing ? 0 : 0.6 * bodySize
            paragraph.firstLineHeadIndent = quoteIndent
            paragraph.headIndent = quoteIndent
        default:
            setLineHeight(paragraph, 1.75 * bodySize)
            // List items sit right under each other. (A gap would only show while the next item is edited: when
            // hidden, that item's marker rides on the line before and swallows the gap, so the text would jump.)
            paragraph.paragraphSpacing = style.tightSpacing ? 0 : 0.6 * bodySize
            if let depth = style.listDepth {
                let indent = listGutter * CGFloat(depth + 1)
                let prefix = style.hangingPrefix.map { hangingPrefixWidth($0, depth: depth) } ?? 0
                paragraph.firstLineHeadIndent = max(indent - prefix, 0)
                paragraph.headIndent = indent
            }
        }
        return paragraph
    }

    /// Width of an edited list item's source prefix as laid out, after `hangingPrefixKern` tightened it.
    func hangingPrefixWidth(_ prefix: String, depth: Int) -> CGFloat {
        min(naturalWidth(of: prefix), listGutter * CGFloat(depth + 1))
    }

    private func naturalWidth(of prefix: String) -> CGFloat {
        (prefix as NSString).size(withAttributes: [.font: font(size: bodySize, weight: .regular, style: TextStyle(role: .body))]).width
    }

    /// Kerning for each character of a prefix that is wider than its gutter (`- [ ] ` is), so it fits and the
    /// item's text keeps its place; nil when it already fits.
    func hangingPrefixKern(_ prefix: String, depth: Int) -> CGFloat? {
        let natural = naturalWidth(of: prefix)
        let fitted = hangingPrefixWidth(prefix, depth: depth)
        let count = (prefix as NSString).length
        guard natural > fitted + 0.5, count > 0 else { return nil }
        return (fitted - natural) / CGFloat(count)
    }

    /// Space before and after a heading, in ems of its own size (spec §9.3).
    func headingSpacing(_ level: Int) -> (before: CGFloat, after: CGFloat) {
        switch level {
        case 1: (1.2, 0.4)
        case 2: (1.1, 0.35)
        case 3: (1.0, 0.3)
        default: (0.9, 0.25)
        }
    }

    /// Spec §9.3 gives line height as a multiple of the font size (CSS style). `lineHeightMultiple` would scale the
    /// font's natural height instead, which for CJK fallback fonts is already about 1.4x the size, so a fixed
    /// height is used.
    private func setLineHeight(_ paragraph: NSMutableParagraphStyle, _ height: CGFloat) {
        paragraph.minimumLineHeight = height
        paragraph.maximumLineHeight = height
    }

    private func font(size: CGFloat, weight: NSFont.Weight, style: TextStyle) -> NSFont {
        var base = NSFont.systemFont(ofSize: size, weight: style.bold ? .bold : weight)
        if style.italic {
            let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
            base = NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }
}
