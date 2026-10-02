import EditorKit
import Foundation
import Markdown

/// Markdown → one self-contained HTML document for PDF export (spec §10.6).
public enum HTMLRenderer {
    public static func render(markdown: String, notePath: String, vaultRoot: URL, title: String) -> String {
        // Frontmatter is not exported.
        let (_, body) = FrontmatterParser.split(markdown)
        let document = Document(parsing: String(body))
        var rewriter = ImageRewriter(notePath: notePath, vaultRoot: vaultRoot)
        let rewritten = (rewriter.visit(document) as? Document) ?? document
        var writer = HTMLWriter()
        let html = wrapTags(in: writer.visit(rewritten))
        return page(title: title, body: html)
    }

    private static func page(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh-Hans">
        <head>
        <meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static let stylesheet: String = {
        guard let url = Bundle.module.url(forResource: "export", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return css
    }()

    static func escape(_ text: String) -> String { HTMLWriter.escape(text) }

    // MARK: Tags

    private static let htmlTag = try! NSRegularExpression(pattern: "<[^>]*>")
    private static let skippedElements: Set<String> = ["code", "pre", "a", "script", "style"]

    /// Wraps `#tags` in `<span class="tag">`, leaving code and links alone (the editor's tag rule, spec §10.3).
    static func wrapTags(in html: String) -> String {
        let ns = html as NSString
        var result = ""
        var cursor = 0
        var skipDepth = 0
        for match in htmlTag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += decorate(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), skipping: skipDepth > 0)
            let tag = ns.substring(with: match.range)
            result += tag
            let name = tag.drop(while: { $0 == "<" || $0 == "/" }).prefix(while: { $0.isLetter || $0.isNumber }).lowercased()
            if skippedElements.contains(name) {
                if tag.hasPrefix("</") { skipDepth = max(skipDepth - 1, 0) } else if !tag.hasSuffix("/>") { skipDepth += 1 }
            }
            cursor = NSMaxRange(match.range)
        }
        result += decorate(ns.substring(from: cursor), skipping: skipDepth > 0)
        return result
    }

    private static func decorate(_ text: String, skipping: Bool) -> String {
        guard !skipping, text.contains("#") else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for tag in TagParser.tags(in: text) {
            result += ns.substring(with: NSRange(location: cursor, length: tag.range.location - cursor))
            result += "<span class=\"tag\">" + ns.substring(with: tag.range) + "</span>"
            cursor = NSMaxRange(tag.range)
        }
        return result + ns.substring(from: cursor)
    }
}

/// Points images at their files on disk; pictures that cannot be found (or are remote) become plain text.
private struct ImageRewriter: MarkupRewriter {
    let notePath: String
    let vaultRoot: URL

    mutating func visitImage(_ image: Image) -> Markup? {
        let source = image.source ?? ""
        guard let url = ImageResolver.resolve(source, notePath: notePath, vaultRoot: vaultRoot) else {
            return Markdown.Text("![\(image.plainText)](\(source))")
        }
        var copy = image
        copy.source = url.absoluteString
        return copy
    }
}
