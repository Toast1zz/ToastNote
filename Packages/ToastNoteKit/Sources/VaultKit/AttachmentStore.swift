import AppKit
import Foundation
import UniformTypeIdentifiers

public enum AttachmentError: Error, Equatable {
    case unreadableImage
    case couldNotWrite
}

/// Stores pasted and dropped images in `<vault>/attachments/` as `yyyyMMdd-HHmmss-xxxx.<ext>` (spec §10.5)
/// and returns the vault-relative path to put into the note.
public struct AttachmentStore: Sendable {
    private let vaultRoot: URL
    private static let folder = "attachments"

    public init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
    }

    /// Saves image bytes. TIFF (what the system pasteboard usually holds for screenshots) becomes PNG;
    /// other formats are stored as they are.
    public func save(imageData: Data, uti: UTType, date: Date = .now) throws -> String {
        var data = imageData
        var type = uti
        if uti.conforms(to: .tiff) {
            guard let rep = NSBitmapImageRep(data: imageData), let png = rep.representation(using: .png, properties: [:]) else {
                throw AttachmentError.unreadableImage
            }
            data = png
            type = .png
        }
        let ext = type.preferredFilenameExtension ?? "png"
        return try write(ext: ext, date: date) { try data.write(to: $0, options: .atomic) }
    }

    /// Copies an image file into the vault, keeping its format (the extension is lowercased).
    public func importFile(_ url: URL, date: Date = .now) throws -> String {
        let ext = url.pathExtension.lowercased()
        return try write(ext: ext.isEmpty ? "png" : ext, date: date) { try FileManager.default.copyItem(at: url, to: $0) }
    }

    private func write(ext: String, date: Date, _ body: (URL) throws -> Void) throws -> String {
        let directory = vaultRoot.appendingPathComponent(Self.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)

        // Four random characters make names unique; retry on the rare clash with an existing file.
        for _ in 0..<50 {
            let name = "\(stamp)-\(Self.randomSuffix()).\(ext)"
            let target = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try body(target)
            return "\(Self.folder)/\(name)"
        }
        throw AttachmentError.couldNotWrite
    }

    private static func randomSuffix() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }
}
