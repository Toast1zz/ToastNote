import CryptoKit
import Foundation

public enum VaultIdentity {
    /// First 16 hex characters of the SHA-256 of the vault's standardized absolute path.
    public static func id(for root: URL) -> String {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// `<base>/ToastNote/Vaults/<id>/`, created on demand. `base` defaults to Application Support.
    public static func supportDirectory(for root: URL, base: URL = applicationSupport) -> URL {
        let dir = base
            .appendingPathComponent("ToastNote", isDirectory: true)
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(id(for: root), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}
