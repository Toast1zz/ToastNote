import EditorKit
import Foundation
import VaultKit

public struct SearchHit: Equatable, Sendable {
    public var path: String
    public var title: String
    /// A short excerpt around the match, with the matched text wrapped in "[" and "]".
    public var snippet: String
}

public struct TagCount: Equatable, Sendable {
    public var tag: String
    public var count: Int
}

/// Tags and full-text search over a vault (spec §5.3, §10.3, §10.4). Lives in Application Support and can
/// always be rebuilt from the notes. All database work happens on this actor, off the main thread.
public actor NoteIndex {
    private let db: SQLiteDatabase
    private let root: URL
    /// Number of notes (re)written; lets tests prove an unchanged vault costs nothing.
    public private(set) var writeCount = 0

    public init(databaseURL: URL, vaultRoot: URL) throws {
        db = try SQLiteDatabase(url: databaseURL)
        root = vaultRoot
        try IndexSchema.migrate(db)
    }

    // MARK: Indexing

    /// Scans the vault and reindexes only notes whose modification time or size changed; forgets deleted ones.
    public func sync() async throws {
        let notes = try VaultScanner.scan(root: root).allNotes()
        var known: [String: (mtime: Double, size: Int64)] = [:]
        let rows = try db.prepare("SELECT path, mtime, size FROM notes")
        while try rows.step() { known[rows.text(at: 0)] = (rows.real(at: 1), rows.int(at: 2)) }

        try db.transaction {
            var seen = Set<String>()
            for note in notes {
                seen.insert(note.path)
                guard let attributes = fileAttributes(note.path) else { continue }
                if let row = known[note.path], row.mtime == attributes.mtime, row.size == attributes.size { continue }
                try index(path: note.path, title: note.title, attributes: attributes)
            }
            for path in known.keys where !seen.contains(path) { try delete(path: path) }
        }
    }

    /// Applies watcher events without a full scan.
    public func apply(_ changes: [VaultChange]) async throws {
        var needsFullSync = false
        try db.transaction {
            for change in changes {
                switch change {
                case .created(let path), .modified(let path):
                    if isNote(path) { try reindex(path) } else { needsFullSync = true }
                case .removed(let path):
                    try delete(path: path, includingFolderContents: true)
                case .renamed(let from, let to):
                    try delete(path: from, includingFolderContents: true)
                    if isNote(to) { try reindex(to) } else { needsFullSync = true }
                }
            }
        }
        if needsFullSync { try await sync() }
    }

    private func isNote(_ path: String) -> Bool {
        ["md", "markdown"].contains((path as NSString).pathExtension.lowercased())
    }

    private func fileAttributes(_ path: String) -> (mtime: Double, size: Int64)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path),
              let date = attributes[.modificationDate] as? Date, let size = attributes[.size] as? NSNumber else { return nil }
        return (date.timeIntervalSince1970, size.int64Value)
    }

    private func reindex(_ path: String) throws {
        guard let attributes = fileAttributes(path) else { return try delete(path: path) }
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        try index(path: path, title: title, attributes: attributes)
    }

    private func index(path: String, title: String, attributes: (mtime: Double, size: Int64)) throws {
        let text: String
        do {
            text = try NoteFile.read(root.appendingPathComponent(path))
        } catch {
            // Unreadable or non-UTF-8 files are listed in the sidebar but never searched.
            return try delete(path: path)
        }
        let (_, body) = FrontmatterParser.split(text)
        let plain = PlainText.extract(String(body))
        var tags = FrontmatterParser.tags(in: text)
        for block in BlockParser.parse(text) {
            for span in block.inlines { if case .tag(let tag) = span.kind { tags.append(tag) } }
        }

        let upsert = try db.prepare("""
        INSERT INTO notes (path, title, body, mtime, size) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET title = excluded.title, body = excluded.body, mtime = excluded.mtime, size = excluded.size
        """)
        try upsert.bind([.text(path), .text(title), .text(plain), .real(attributes.mtime), .int(attributes.size)])
        try upsert.step()

        let lookup = try db.prepare("SELECT id FROM notes WHERE path = ?")
        try lookup.bind([.text(path)])
        guard try lookup.step() else { return }
        let id = lookup.int(at: 0)

        let clear = try db.prepare("DELETE FROM tags WHERE note_id = ?")
        try clear.bind([.int(id)])
        try clear.step()
        let insertTag = try db.prepare("INSERT OR IGNORE INTO tags (note_id, tag) VALUES (?, ?)")
        for tag in Set(tags) {
            try insertTag.bind([.int(id), .text(tag)])
            try insertTag.step()
        }
        writeCount += 1
    }

    private func delete(path: String, includingFolderContents: Bool = false) throws {
        let statement = try db.prepare(includingFolderContents ? "DELETE FROM notes WHERE path = ? OR path LIKE ? ESCAPE '\\'" : "DELETE FROM notes WHERE path = ?")
        try statement.bind(includingFolderContents ? [.text(path), .text(Self.escapeLike(path) + "/%")] : [.text(path)])
        try statement.step()
    }

    // MARK: Search

    /// Full-text search. Queries of three or more characters use FTS5 (trigram, ranked by bm25); shorter terms
    /// use LIKE, because trigrams cannot match one or two characters. `#tag` words filter by tag.
    public func search(_ query: String, limit: Int = 100) async throws -> [SearchHit] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let tags = words.filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
        let terms = words.filter { !($0.hasPrefix("#") && $0.count > 1) }
        if terms.isEmpty && tags.isEmpty { return [] }

        var params: [SQLiteValue] = []
        var tagClauses = ""
        for tag in tags {
            tagClauses += " AND n.id IN (SELECT note_id FROM tags WHERE tag = ? COLLATE NOCASE OR tag LIKE ? ESCAPE '\\' COLLATE NOCASE)"
            params.append(contentsOf: [.text(tag), .text(Self.escapeLike(tag) + "/%")])
        }

        var hits: [SearchHit] = []
        if terms.isEmpty {
            let statement = try db.prepare("SELECT n.path, n.title, substr(n.body, 1, 60) FROM notes n WHERE 1 = 1\(tagClauses) ORDER BY n.title LIMIT ?")
            try statement.bind(params + [.int(Int64(limit))])
            while try statement.step() { hits.append(SearchHit(path: statement.text(at: 0), title: statement.text(at: 1), snippet: statement.text(at: 2))) }
        } else if terms.allSatisfy({ $0.count >= 3 }) {
            let match = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
            let statement = try db.prepare("""
            SELECT n.path, n.title, snippet(notes_fts, 1, '[', ']', '…', 12)
            FROM notes_fts JOIN notes n ON n.id = notes_fts.rowid
            WHERE notes_fts MATCH ?\(tagClauses)
            ORDER BY bm25(notes_fts) LIMIT ?
            """)
            try statement.bind([.text(match)] + params + [.int(Int64(limit))])
            while try statement.step() { hits.append(SearchHit(path: statement.text(at: 0), title: statement.text(at: 1), snippet: statement.text(at: 2))) }
        } else {
            var likeClauses = ""
            var likeParams: [SQLiteValue] = []
            for term in terms {
                likeClauses += " AND (n.title LIKE ? ESCAPE '\\' OR n.body LIKE ? ESCAPE '\\')"
                let pattern = "%" + Self.escapeLike(term) + "%"
                likeParams.append(contentsOf: [.text(pattern), .text(pattern)])
            }
            let statement = try db.prepare("SELECT n.path, n.title, n.body FROM notes n WHERE 1 = 1\(likeClauses)\(tagClauses) ORDER BY n.title LIMIT ?")
            try statement.bind(likeParams + params + [.int(Int64(limit))])
            while try statement.step() {
                hits.append(SearchHit(path: statement.text(at: 0), title: statement.text(at: 1), snippet: Self.snippet(in: statement.text(at: 2), around: terms)))
            }
        }
        return hits
    }

    /// An excerpt of about 40 characters around the first match, the matched text in brackets.
    static func snippet(in body: String, around terms: [String]) -> String {
        for term in terms {
            guard let range = body.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let start = body.index(range.lowerBound, offsetBy: -20, limitedBy: body.startIndex) ?? body.startIndex
            let end = body.index(range.upperBound, offsetBy: 20, limitedBy: body.endIndex) ?? body.endIndex
            let before = String(body[start..<range.lowerBound]).replacingOccurrences(of: "\n", with: " ")
            let after = String(body[range.upperBound..<end]).replacingOccurrences(of: "\n", with: " ")
            return (start > body.startIndex ? "…" : "") + before + "[" + body[range] + "]" + after + (end < body.endIndex ? "…" : "")
        }
        return String(body.prefix(60)).replacingOccurrences(of: "\n", with: " ")
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: Tags

    /// Every tag with the number of notes carrying it or one of its sub-tags (`工作` counts `工作/周报` too).
    public func tags() async throws -> [TagCount] {
        var perNote: [Int64: Set<String>] = [:]
        let statement = try db.prepare("SELECT note_id, tag FROM tags")
        while try statement.step() {
            let id = statement.int(at: 0)
            let tag = statement.text(at: 1)
            var parts = tag.split(separator: "/").map(String.init)
            while !parts.isEmpty {
                perNote[id, default: []].insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }
        var counts: [String: Int] = [:]
        for tags in perNote.values { for tag in tags { counts[tag, default: 0] += 1 } }
        return counts.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    /// Paths of notes tagged `tag` or one of its sub-tags, sorted by title.
    public func notes(taggedWith tag: String) async throws -> [String] {
        let statement = try db.prepare("""
        SELECT n.path FROM notes n
        WHERE n.id IN (SELECT note_id FROM tags WHERE tag = ? COLLATE NOCASE OR tag LIKE ? ESCAPE '\\' COLLATE NOCASE)
        ORDER BY n.title
        """)
        try statement.bind([.text(tag), .text(Self.escapeLike(tag) + "/%")])
        var paths: [String] = []
        while try statement.step() { paths.append(statement.text(at: 0)) }
        return paths
    }
}
