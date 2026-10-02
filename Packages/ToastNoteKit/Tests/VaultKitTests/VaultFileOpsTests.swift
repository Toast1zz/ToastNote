import Foundation
import Testing
@testable import VaultKit

@Suite struct VaultFileOpsTests {
    @Test func createNoteNamesUntitled() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let ops = VaultFileOps(root: root)
        #expect(try ops.createNote(inFolder: "").path == "未命名.md")
        #expect(try ops.createNote(inFolder: "").path == "未命名 2.md")
        let third = try ops.createNote(inFolder: "")
        #expect(third.path == "未命名 3.md")
        #expect(third.title == "未命名 3")
    }

    @Test func createNoteInSubfolder() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let ops = VaultFileOps(root: root)
        let folder = try ops.createFolder(named: "工作", inFolder: "")
        #expect(folder == "工作")
        #expect(try ops.createNote(inFolder: folder).path == "工作/未命名.md")
    }

    @Test func renameKeepsFolderAndExtension() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "工作/a.md", "x")
        let ops = VaultFileOps(root: root)
        #expect(try ops.rename(path: "工作/a.md", to: "b") == "工作/b.md")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("工作/b.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("工作/a.md").path))
    }

    @Test func renameRefusesCollision() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "a.md")
        try touch(root, "b.md")
        let ops = VaultFileOps(root: root)
        #expect(throws: (any Error).self) { try ops.rename(path: "a.md", to: "b") }
    }

    @Test func moveIntoFolder() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "a.md")
        try touch(root, "f/keep.md")
        let ops = VaultFileOps(root: root)
        #expect(try ops.move(path: "a.md", toFolder: "f") == "f/a.md")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("f/a.md").path))
    }

    @Test func moveRefusesCollision() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root, "a.md")
        try touch(root, "f/a.md")
        let ops = VaultFileOps(root: root)
        #expect(throws: (any Error).self) { try ops.move(path: "a.md", toFolder: "f") }
    }
}
