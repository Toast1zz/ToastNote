import Foundation

public enum NoteFileError: Error, Equatable {
    case notUTF8
    case missing
}

public enum NoteFile {
    /// Reads a note as UTF-8, normalizing CRLF and CR line endings to LF.
    public static func read(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            throw NoteFileError.missing
        }
        guard let text = String(data: data, encoding: .utf8) else { throw NoteFileError.notUTF8 }
        return normalizeLineEndings(text)
    }

    /// Atomically writes `text` (LF line endings) and keeps the file's POSIX permissions.
    public static func write(_ text: String, to url: URL) throws {
        let fm = FileManager.default
        let permissions = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
        try Data(normalizeLineEndings(text).utf8).write(to: url, options: .atomic)
        if let permissions {
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    static func normalizeLineEndings(_ text: String) -> String {
        // "\r\n" is a single Character in Swift, so replace it before lone "\r".
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
