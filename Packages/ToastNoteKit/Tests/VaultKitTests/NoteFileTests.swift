import Foundation
import Testing
@testable import VaultKit

@Suite struct NoteFileTests {
    @Test func readNormalizesLineEndings() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.md")
        try Data("a\r\nb\rc".utf8).write(to: url)
        #expect(try NoteFile.read(url) == "a\nb\nc")
    }

    @Test func readRejectsNonUTF8() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.md")
        try Data([0xC3, 0x28]).write(to: url)
        #expect(throws: NoteFileError.notUTF8) { try NoteFile.read(url) }
    }

    @Test func readMissingFileThrowsMissing() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: NoteFileError.missing) { try NoteFile.read(root.appendingPathComponent("nope.md")) }
    }

    @Test func writePreservesPermissions() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.md")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try NoteFile.write("new", to: url)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(try String(contentsOf: url, encoding: .utf8) == "new")
    }

    @Test func writeNormalizesToLF() throws {
        let root = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.md")
        try NoteFile.write("a\r\nb", to: url)
        #expect(try Data(contentsOf: url) == Data("a\nb".utf8))
    }

    @Test func selfWriteIsConsumedOnce() {
        let registry = SelfWriteRegistry()
        let date = Date()
        registry.record(path: "a.md", modificationDate: date)
        #expect(registry.isSelfWrite(path: "a.md", modificationDate: date) == true)
        #expect(registry.isSelfWrite(path: "a.md", modificationDate: date) == false)
    }

    @Test func selfWriteWithDifferentDateIsNotSelf() {
        let registry = SelfWriteRegistry()
        registry.record(path: "a.md", modificationDate: Date(timeIntervalSince1970: 100))
        #expect(registry.isSelfWrite(path: "a.md", modificationDate: Date(timeIntervalSince1970: 200)) == false)
    }
}
