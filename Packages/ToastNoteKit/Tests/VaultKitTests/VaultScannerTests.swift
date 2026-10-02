import Foundation
import Testing
@testable import VaultKit

func makeTempVault() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tn-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func touch(_ root: URL, _ relative: String, _ contents: String = "") throws {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

@Suite struct VaultScannerTests {
    @Test func listsOnlyMarkdownFiles() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.md", "b.markdown", "c.txt", "d.png"] { try touch(root, name) }
        let tree = try VaultScanner.scan(root: root)
        #expect(tree.notes.map(\.title) == ["a", "b"])
    }

    @Test func ignoresDotEntries() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, ".obsidian/x.md")
        try touch(root, ".toastnote/workspace.json")
        try touch(root, ".hidden.md")
        let tree = try VaultScanner.scan(root: root)
        #expect(tree.notes.isEmpty)
        #expect(tree.folders.isEmpty)
    }

    @Test func nestedFolders() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "工作/周报.md")
        let tree = try VaultScanner.scan(root: root)
        #expect(tree.folders[0].name == "工作")
        #expect(tree.folders[0].path == "工作")
        #expect(tree.folders[0].notes[0].path == "工作/周报.md")
    }

    @Test func sortsLikeFinder() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "笔记 10.md")
        try touch(root, "笔记 2.md")
        let tree = try VaultScanner.scan(root: root)
        #expect(tree.notes.map(\.title) == ["笔记 2", "笔记 10"])
    }

    @Test func titleStripsExtension() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "设计.系统.md")
        let tree = try VaultScanner.scan(root: root)
        #expect(tree.notes[0].title == "设计.系统")
    }

    @Test func allNotesFlattensTree() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "a.md")
        try touch(root, "f/b.md")
        try touch(root, "f/g/c.md")
        let tree = try VaultScanner.scan(root: root)
        #expect(Set(tree.allNotes().map(\.path)) == ["a.md", "f/b.md", "f/g/c.md"])
    }
}
