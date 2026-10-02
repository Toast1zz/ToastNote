import AppKit
import Foundation

public struct TextStyle: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case body, heading(Int), codeInline, codeBlock, quote, link, tag, marker, taskDone, frontmatterSummary
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
    public var blankLine = false

    public init(
        role: Role, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false,
        listDepth: Int? = nil, tightSpacing: Bool = false, blankLine: Bool = false
    ) {
        self.role = role
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.listDepth = listDepth
        self.tightSpacing = tightSpacing
        self.blankLine = blankLine
    }
}

public struct EditorTheme: Sendable {
    /// 13...20, spec §9.3.
    public var bodySize: CGFloat = 15
    /// 600...900.
    public var maxContentWidth: CGFloat = 720

    public static let `default` = EditorTheme()

    public init(bodySize: CGFloat = 15, maxContentWidth: CGFloat = 720) {
        self.bodySize = min(max(bodySize, 13), 20)
        self.maxContentWidth = min(max(maxContentWidth, 600), 900)
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
        case .codeInline, .codeBlock:
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: codeSize, weight: style.bold ? .bold : .regular)
            attributes[.foregroundColor] = NSColor.labelColor
        case .quote:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        case .link, .tag:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = NSColor.controlAccentColor
        case .marker:
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        case .taskDone:
            attributes[.font] = font(size: bodySize, weight: .regular, style: style)
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        case .frontmatterSummary:
            attributes[.font] = NSFont.systemFont(ofSize: bodySize)
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        // CJK fonts have no italic face, so slant the glyphs synthetically.
        if style.italic { attributes[.obliqueness] = 0.2 }
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
        if style.blankLine {
            paragraph.minimumLineHeight = 0.5 * bodySize
            paragraph.maximumLineHeight = 0.5 * bodySize
            return paragraph
        }
        switch style.role {
        case .heading(let level):
            let (before, after): (CGFloat, CGFloat) = switch level {
            case 1: (1.2, 0.4)
            case 2: (1.1, 0.35)
            case 3: (1.0, 0.3)
            default: (0.9, 0.25)
            }
            let size = headingSize(level)
            paragraph.lineHeightMultiple = 1.35
            paragraph.paragraphSpacingBefore = before * size
            paragraph.paragraphSpacing = after * size
        case .codeBlock:
            paragraph.lineHeightMultiple = 1.5
            paragraph.firstLineHeadIndent = codePadding
            paragraph.headIndent = codePadding
            paragraph.tailIndent = -codePadding
        case .codeInline:
            paragraph.lineHeightMultiple = 1.5
        case .quote:
            paragraph.lineHeightMultiple = 1.75
            paragraph.paragraphSpacing = 0.6 * bodySize
            paragraph.firstLineHeadIndent = quoteIndent
            paragraph.headIndent = quoteIndent
        default:
            paragraph.lineHeightMultiple = 1.75
            paragraph.paragraphSpacing = (style.tightSpacing ? 0.2 : 0.6) * bodySize
            if let depth = style.listDepth {
                paragraph.firstLineHeadIndent = listGutter * CGFloat(depth + 1)
                paragraph.headIndent = listGutter * CGFloat(depth + 1)
            }
        }
        return paragraph
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
