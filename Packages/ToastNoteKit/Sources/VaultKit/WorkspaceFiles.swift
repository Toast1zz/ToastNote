import Foundation

/// Pinned notes; lives in the vault so it follows the vault between devices.
public struct PinnedFile: Codable, Equatable, Sendable {
    public var version = 1
    public var pinned: [String]

    public init(pinned: [String]) {
        self.pinned = pinned
    }
}

/// Per-device session state; lives in Application Support.
public struct SessionFile: Codable, Equatable, Sendable {
    public var open: [String]
    public var current: String?
    public var collapsedSections: Set<String>

    public init(open: [String], current: String?, collapsedSections: Set<String>) {
        self.open = open
        self.current = current
        self.collapsedSections = collapsedSections
    }
}

public enum WorkspaceFiles {
    public static func loadPinned(vault: URL) -> PinnedFile {
        load(PinnedFile.self, from: pinnedURL(vault)) ?? PinnedFile(pinned: [])
    }

    public static func save(_ file: PinnedFile, vault: URL) throws {
        let url = pinnedURL(vault)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(file).write(to: url, options: .atomic)
    }

    public static func loadSession(vault: URL, base: URL = VaultIdentity.applicationSupport) -> SessionFile {
        load(SessionFile.self, from: sessionURL(vault, base)) ?? SessionFile(open: [], current: nil, collapsedSections: [])
    }

    public static func save(_ file: SessionFile, vault: URL, base: URL = VaultIdentity.applicationSupport) throws {
        try encode(file).write(to: sessionURL(vault, base), options: .atomic)
    }

    private static func pinnedURL(_ vault: URL) -> URL {
        vault.appendingPathComponent(".toastnote/workspace.json")
    }

    private static func sessionURL(_ vault: URL, _ base: URL) -> URL {
        VaultIdentity.supportDirectory(for: vault, base: base).appendingPathComponent("session.json")
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Missing or corrupt files yield nil so callers fall back to defaults.
    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
