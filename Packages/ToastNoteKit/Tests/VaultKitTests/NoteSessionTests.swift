import Foundation
import Testing
@testable import VaultKit

@MainActor
private func makeSession(
    contents: String = "hello", bytes: Data? = nil
) throws -> (NoteSession, URL, SelfWriteRegistry) {
    let root = try makeTempVault()
    let file = root.appendingPathComponent("a.md")
    if let bytes { try bytes.write(to: file) } else { try contents.write(to: file, atomically: true, encoding: .utf8) }
    let registry = SelfWriteRegistry()
    let session = NoteSession(root: root, path: "a.md", registry: registry, autosaveDelay: .milliseconds(50))
    session.load()
    return (session, root, registry)
}

private func diskText(_ root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8)
}

@MainActor @Suite struct NoteSessionTests {
    @Test func loadsFileText() throws {
        let (session, root, _) = try makeSession(contents: "你好")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(session.text == "你好")
        #expect(session.isDirty == false)
        #expect(session.loadError == nil)
    }

    @Test func autosavesAfterDelay() async throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.userEdited("x")
        #expect(session.isDirty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try diskText(root) == "x")
        #expect(session.isDirty == false)
    }

    @Test func doesNotWriteWhenUnchanged() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.md")
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.05)
        session.saveNow()
        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(before == after)
    }

    @Test func saveRecordsSelfWrite() throws {
        let (session, root, registry) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.userEdited("changed")
        session.saveNow()
        let url = root.appendingPathComponent("a.md")
        let mtime = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        #expect(registry.isSelfWrite(path: "a.md", modificationDate: mtime))
    }

    @Test func externalChangeReloadsWhenClean() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        try "from elsewhere".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        session.handle(.modified("a.md"))
        #expect(session.text == "from elsewhere")
        #expect(session.banner == nil)
    }

    @Test func createdEventForOpenPathReloadsLikeModified() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        try "replaced".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        session.handle(.created("a.md"))
        #expect(session.text == "replaced")
    }

    @Test func externalChangeShowsBannerWhenDirty() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.userEdited("mine")
        session.handle(.modified("a.md"))
        #expect(session.banner == .modifiedExternally)
        #expect(session.text == "mine")
    }

    @Test func bannerBlocksAutosaveUntilResolved() async throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.userEdited("mine")
        session.handle(.modified("a.md"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(try diskText(root) == "hello")
    }

    @Test func keepMineOverwritesOnNextSave() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.userEdited("mine")
        try "theirs".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        session.handle(.modified("a.md"))
        session.resolveBanner(.keepMine)
        #expect(session.banner == nil)
        session.saveNow()
        #expect(try diskText(root) == "mine")
    }

    @Test func loadTheirsDiscardsLocalEdits() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.userEdited("mine")
        try "theirs".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        session.handle(.modified("a.md"))
        session.resolveBanner(.loadTheirs)
        #expect(session.text == "theirs")
        #expect(session.isDirty == false)
        #expect(session.banner == nil)
    }

    @Test func deletionShowsBanner() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.handle(.removed("a.md"))
        #expect(session.banner == .deletedExternally)
    }

    @Test func resaveWritesFileAgainAfterDeletion() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.md"))
        session.handle(.removed("a.md"))
        session.resolveBanner(.resave)
        #expect(try diskText(root) == "hello")
        #expect(session.banner == nil)
    }

    @Test func closeInvokesOnClose() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        var closed = false
        session.onClose = { closed = true }
        session.handle(.removed("a.md"))
        session.resolveBanner(.close)
        #expect(closed)
    }

    @Test func nonUTF8FileIsNeverSaved() throws {
        let bytes = Data([0xC3, 0x28])
        let (session, root, _) = try makeSession(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(session.loadError == .notUTF8)
        session.userEdited("x")
        session.saveNow()
        #expect(try Data(contentsOf: root.appendingPathComponent("a.md")) == bytes)
    }

    @Test func renameFollowsPath() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.handle(.renamed(from: "a.md", to: "b.md"))
        #expect(session.path == "b.md")
    }

    @Test func unrelatedChangesAreIgnored() throws {
        let (session, root, _) = try makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        session.handle(.removed("other.md"))
        session.handle(.modified("other.md"))
        #expect(session.banner == nil)
    }
}
