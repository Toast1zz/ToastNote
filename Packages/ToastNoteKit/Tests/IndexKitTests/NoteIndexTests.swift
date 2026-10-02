import Foundation
import Testing
import VaultKit
@testable import IndexKit

private struct TestVault {
    let root: URL
    let databaseURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tn-vault-\(UUID().uuidString)", isDirectory: true)
        databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("tn-db-\(UUID().uuidString).sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: databaseURL)
    }

    func index() throws -> NoteIndex { try NoteIndex(databaseURL: databaseURL, vaultRoot: root) }
}

@Suite struct NoteIndexTests {
    @Test func indexesAndSearchesChinese() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("调研.md", "# 设计系统调研\n\n这是关于设计系统的一些想法。")
        try vault.write("其他.md", "完全无关的内容。")
        let index = try vault.index()
        try await index.sync()

        let hits = try await index.search("设计系统")
        #expect(hits.map(\.path) == ["调研.md"])
        #expect(hits[0].title == "调研")
        #expect(hits[0].snippet.contains("["))
    }

    @Test func shortQueryUsesLike() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "设计稿已经完成")
        try vault.write("b.md", "无关")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("设计").map(\.path) == ["a.md"])
        #expect(try await index.search("计").map(\.path) == ["a.md"])
        #expect(try await index.search("完成").first?.snippet.contains("[完成]") == true)
    }

    @Test func titleMatchesToo() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("读书笔记.md", "正文里没有那个词")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("读书笔记").map(\.path) == ["读书笔记.md"])
        #expect(try await index.search("读书").map(\.path) == ["读书笔记.md"])
    }

    @Test func englishSearchIsCaseInsensitive() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "The Quick Brown Fox")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("quick brown").map(\.path) == ["a.md"])
    }

    @Test func tagFilterInQuery() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "本周周报内容 #工作")
        try vault.write("b.md", "另一份周报 #生活")
        try vault.write("c.md", "没有标签的周报")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("#工作 周报").map(\.path) == ["a.md"])
        #expect(try await index.search("#生活").map(\.path) == ["b.md"])
    }

    @Test func markdownSyntaxDoesNotBlockSearch() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "这是**粗体文字**和[链接文字](https://x.y)")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("粗体文字").count == 1)
        #expect(try await index.search("链接文字").count == 1)
    }

    @Test func frontmatterIsNotSearchable() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "---\nsecretkey: hidden-value\n---\n正文")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("hidden-value").isEmpty)
    }

    @Test func incrementalSkipsUnchanged() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "一")
        try vault.write("b.md", "二")
        let index = try vault.index()
        try await index.sync()
        let afterFirst = await index.writeCount
        #expect(afterFirst == 2)
        try await index.sync()
        #expect(await index.writeCount == afterFirst)

        try vault.write("a.md", "改动了的内容")
        try await index.sync()
        #expect(await index.writeCount == afterFirst + 1)
    }

    @Test func removedFilesDropped() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "独特内容甲乙丙")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("独特内容").count == 1)
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("a.md"))
        try await index.sync()
        #expect(try await index.search("独特内容").isEmpty)
    }

    @Test func nestedTagCounts() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "写周报 #工作/周报")
        try vault.write("b.md", "写计划 #工作")
        try vault.write("c.md", "随手记 #生活")
        let index = try vault.index()
        try await index.sync()

        let tags = try await index.tags()
        #expect(tags.first { $0.tag == "工作" }?.count == 2)
        #expect(tags.first { $0.tag == "工作/周报" }?.count == 1)
        #expect(tags.first { $0.tag == "生活" }?.count == 1)
        #expect(try await index.notes(taggedWith: "工作").count == 2)
        #expect(try await index.notes(taggedWith: "工作/周报") == ["a.md"])
    }

    @Test func frontmatterTagsIndexed() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "---\ntags: [阅读, 笔记]\n---\n正文")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.notes(taggedWith: "阅读") == ["a.md"])
        #expect(try await index.tags().map(\.tag).contains("笔记"))
    }

    @Test func tagsInCodeAreNotIndexed() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "`#nottag` 和\n\n```\n#alsonot\n```\n\n真标签 #real")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.tags().map(\.tag) == ["real"])
    }

    @Test func tagComparisonIgnoresCase() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("a.md", "内容 #Swift")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.notes(taggedWith: "swift") == ["a.md"])
    }

    @Test func nonUTF8FileSkipped() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try Data([0xC3, 0x28]).write(to: vault.root.appendingPathComponent("bad.md"))
        try vault.write("ok.md", "正常内容在这里")
        let index = try vault.index()
        try await index.sync()
        #expect(try await index.search("正常内容").count == 1)
        #expect(try await index.search("bad").isEmpty)
    }

    @Test func applyHandlesCreateModifyRemoveAndRename() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        let index = try vault.index()
        try await index.sync()

        try vault.write("a.md", "新建的内容甲乙丙")
        try await index.apply([.created("a.md")])
        #expect(try await index.search("新建的内容").count == 1)

        try vault.write("a.md", "改过之后的内容丁戊己")
        try await index.apply([.modified("a.md")])
        #expect(try await index.search("新建的内容").isEmpty)
        #expect(try await index.search("改过之后").count == 1)

        try FileManager.default.moveItem(at: vault.root.appendingPathComponent("a.md"), to: vault.root.appendingPathComponent("b.md"))
        try await index.apply([.renamed(from: "a.md", to: "b.md")])
        #expect(try await index.search("改过之后").map(\.path) == ["b.md"])

        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("b.md"))
        try await index.apply([.removed("b.md")])
        #expect(try await index.search("改过之后").isEmpty)
    }

    @Test func folderRenameReindexesEverythingInside() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        try vault.write("旧/a.md", "文件夹里的内容甲乙丙")
        let index = try vault.index()
        try await index.sync()
        try FileManager.default.moveItem(at: vault.root.appendingPathComponent("旧"), to: vault.root.appendingPathComponent("新"))
        try await index.apply([.renamed(from: "旧", to: "新")])
        #expect(try await index.search("文件夹里的内容").map(\.path) == ["新/a.md"])
    }

    @Test func thousandNotesUnderFiveSeconds() async throws {
        let vault = try TestVault()
        defer { vault.remove() }
        for i in 0..<1000 {
            let folder = "文件夹\(i % 20)"
            let body = "# 笔记 \(i)\n\n这是第 \(i) 篇笔记的正文，包含 **粗体**、`代码` 和 #标签\(i % 30)。\n\n" + String(repeating: "一些用来凑长度的中文内容。English filler text here. ", count: 15)
            try vault.write("\(folder)/笔记 \(i).md", body)
        }
        let index = try vault.index()
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { try await index.sync() }
        print("PERF index 1000 notes:", elapsed)
        #expect(elapsed < .seconds(5), "indexing took \(elapsed)")
        #expect(try await index.search("第 500 篇").count >= 1)
    }
}
