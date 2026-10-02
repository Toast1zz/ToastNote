import Foundation
import Testing
@testable import ExportKit

private let vault = URL(fileURLWithPath: "/tmp/tn-export-test-vault", isDirectory: true)

private func render(_ markdown: String, notePath: String = "笔记.md") -> String {
    HTMLRenderer.render(markdown: markdown, notePath: notePath, vaultRoot: vault, title: "笔记")
}

@Suite struct HTMLRendererTests {
    @Test func headingsAndLists() {
        let html = render("# 标题\n\n## 小节\n\n- 甲\n- 乙\n\n1. 一\n2. 二")
        #expect(html.contains("<h1>标题</h1>"))
        #expect(html.contains("<h2>小节</h2>"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>甲</li>"))
        #expect(html.contains("<ol>"))
    }

    @Test func fullDocumentWithTitleAndUTF8() {
        let html = render("正文")
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(html.contains("<title>笔记</title>"))
        #expect(html.contains("<p>正文</p>"))
    }

    @Test func titleIsEscaped() {
        let html = HTMLRenderer.render(markdown: "x", notePath: "a.md", vaultRoot: vault, title: "A <b> & \"c\"")
        #expect(html.contains("<title>A &lt;b&gt; &amp; &quot;c&quot;</title>"))
    }

    @Test func frontmatterRemoved() {
        let html = render("---\ntags: [secret-tag]\ntitle: frontmatter-title\n---\n正文在这里")
        #expect(!html.contains("secret-tag"))
        #expect(!html.contains("frontmatter-title"))
        #expect(html.contains("正文在这里"))
    }

    @Test func codeEscaped() {
        let html = render("```html\n<div class=\"a\">&</div>\n```\n\n行内 `a < b`")
        #expect(html.contains("&lt;div class=&quot;a&quot;&gt;&amp;&lt;/div&gt;"))
        #expect(html.contains("<code>a &lt; b</code>"))
        #expect(!html.contains("<div class=\"a\">"))
    }

    @Test func imageResolvedToFileURL() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tn-html-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("attachments/图 1.png"))
        let html = HTMLRenderer.render(markdown: "![说明](attachments/图%201.png)", notePath: "n.md", vaultRoot: root, title: "n")
        let expected = root.appendingPathComponent("attachments/图 1.png").standardizedFileURL.absoluteString
        #expect(html.contains("src=\"\(expected)\""), "html: \(html)")
        #expect(html.contains("alt=\"说明\""))
    }

    @Test func missingImageIsLeftAsText() {
        let html = render("![x](attachments/gone.png)")
        #expect(!html.contains("<img"))
        #expect(html.contains("gone.png"))
    }

    @Test func remoteImagesAreNotLoaded() {
        let html = render("![x](https://example.com/a.png)")
        #expect(!html.contains("<img"))
    }

    @Test func taskCheckboxes() {
        let html = render("- [ ] 待办\n- [x] 完成")
        #expect(html.contains("<input type=\"checkbox\" disabled> 待办"))
        #expect(html.contains("<input type=\"checkbox\" checked disabled> 完成"))
    }

    @Test func rawHTMLInANoteIsShownNotExecuted() {
        let html = render("<script>alert(1)</script>\n\n文字 <b>粗</b>")
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<b>粗</b>"))
    }

    @Test func tableAlignmentIsKept() {
        let html = render("| 左 | 中 | 右 |\n|:--|:-:|--:|\n| a | b | c |")
        #expect(html.contains("text-align: center"))
        #expect(html.contains("text-align: right"))
    }

    @Test func orderedListKeepsItsStartNumber() {
        #expect(render("3. 三\n4. 四").contains("<ol start=\"3\">"))
    }

    @Test func tagsWrapped() {
        let html = render("看 #工作/周报 和 #待办。")
        #expect(html.contains("<span class=\"tag\">#工作/周报</span>"))
        #expect(html.contains("<span class=\"tag\">#待办</span>"))
    }

    @Test func tagsInCodeAndLinksAreLeftAlone() {
        let html = render("`#nottag` 与 [#链接文字](https://a.b) 和\n\n```\n#alsonot\n```")
        #expect(!html.contains("class=\"tag\""))
    }

    @Test func headingsAreNotTags() {
        #expect(!render("# 标题").contains("class=\"tag\""))
    }

    @Test func tablesAndQuotes() {
        let html = render("| a | b |\n|---|---|\n| 1 | 2 |\n\n> 引用")
        #expect(html.contains("<table>"))
        #expect(html.contains("<blockquote>"))
    }

    @Test func cssLinked() {
        let html = render("正文")
        #expect(html.contains("@page { size: A4; margin: 20mm }"))
        #expect(html.contains("break-inside: avoid"))
        #expect(html.contains("color-scheme: light"))
        // Tags never break across lines, and their pill backgrounds are printed.
        #expect(html.contains("white-space: nowrap"))
        #expect(html.contains("print-color-adjust: exact"))
    }

    @Test func chineseAndEmojiSurvive() {
        let html = render("**粗体** 😀 中文，标点。")
        #expect(html.contains("<strong>粗体</strong>"))
        #expect(html.contains("😀"))
    }
}
