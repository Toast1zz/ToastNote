import Foundation
import Testing
@testable import VaultKit

@Suite struct WorkspaceFilesTests {
    @Test func idIsStableAnd16Hex() {
        let root = URL(fileURLWithPath: "/tmp/some-vault")
        let id = VaultIdentity.id(for: root)
        #expect(id == VaultIdentity.id(for: root))
        #expect(id.count == 16)
        #expect(id.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(id != VaultIdentity.id(for: URL(fileURLWithPath: "/tmp/other-vault")))
    }

    @Test func supportDirIsUnderApplicationSupport() throws {
        let base = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = URL(fileURLWithPath: "/tmp/some-vault")
        let dir = VaultIdentity.supportDirectory(for: root, base: base)
        #expect(dir.path == base.appendingPathComponent("ToastNote/Vaults/\(VaultIdentity.id(for: root))").path)
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func pinnedRoundTrip() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let pinned = PinnedFile(pinned: ["a.md", "工作/b.md"])
        try WorkspaceFiles.save(pinned, vault: vault)
        #expect(WorkspaceFiles.loadPinned(vault: vault) == pinned)
        let raw = try String(contentsOf: vault.appendingPathComponent(".toastnote/workspace.json"), encoding: .utf8)
        #expect(raw.contains("\"version\":1"))
    }

    @Test func missingPinnedYieldsEmpty() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        #expect(WorkspaceFiles.loadPinned(vault: vault) == PinnedFile(pinned: []))
    }

    @Test func sessionRoundTrip() throws {
        let vault = try makeTempVault()
        let base = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault); try? FileManager.default.removeItem(at: base) }
        let session = SessionFile(open: ["a.md", "b.md"], current: "b.md", collapsedSections: ["标签"])
        try WorkspaceFiles.save(session, vault: vault, base: base)
        #expect(WorkspaceFiles.loadSession(vault: vault, base: base) == session)
    }

    @Test func sessionDecodesWithoutRecent() throws {
        // Session files written before quick open existed have no "recent" key.
        let json = #"{"open":["a.md"],"current":"a.md","collapsedSections":["标签"]}"#
        let session = try JSONDecoder().decode(SessionFile.self, from: Data(json.utf8))
        #expect(session.recent.isEmpty)
        #expect(session.open == ["a.md"])
    }

    @Test func recentRoundTrips() throws {
        let vault = try makeTempVault()
        let base = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault); try? FileManager.default.removeItem(at: base) }
        let session = SessionFile(open: [], current: nil, collapsedSections: [], recent: ["x.md", "y.md"])
        try WorkspaceFiles.save(session, vault: vault, base: base)
        #expect(WorkspaceFiles.loadSession(vault: vault, base: base).recent == ["x.md", "y.md"])
    }

    @Test func corruptSessionYieldsEmpty() throws {
        let vault = try makeTempVault()
        let base = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault); try? FileManager.default.removeItem(at: base) }
        let dir = VaultIdentity.supportDirectory(for: vault, base: base)
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("session.json"))
        #expect(WorkspaceFiles.loadSession(vault: vault, base: base) == SessionFile(open: [], current: nil, collapsedSections: []))
    }
}
