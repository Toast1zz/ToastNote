import Foundation

/// The index database of spec §5.3. The index can always be rebuilt from the notes, so a schema version
/// mismatch drops everything and starts over instead of migrating.
public enum IndexSchema {
    public static let version = 1

    public static func migrate(_ db: SQLiteDatabase) throws {
        if try storedVersion(db) != version {
            try dropAll(db)
        }
        try db.transaction {
            try db.execute("""
            CREATE TABLE IF NOT EXISTS notes (
              id    INTEGER PRIMARY KEY,
              path  TEXT NOT NULL UNIQUE,
              title TEXT NOT NULL,
              body  TEXT NOT NULL,
              mtime REAL NOT NULL,
              size  INTEGER NOT NULL
            )
            """)
            try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
              title, body, content='notes', content_rowid='id', tokenize='trigram'
            )
            """)
            try db.execute("""
            CREATE TABLE IF NOT EXISTS tags (
              note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
              tag     TEXT NOT NULL,
              PRIMARY KEY (note_id, tag)
            )
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS tags_tag ON tags(tag COLLATE NOCASE)")
            // Reserved for AI linking (spec §12); written to by nothing in v1.
            try db.execute("""
            CREATE TABLE IF NOT EXISTS embeddings (
              note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
              chunk   INTEGER NOT NULL,
              model   TEXT NOT NULL,
              vector  BLOB NOT NULL,
              PRIMARY KEY (note_id, chunk, model)
            )
            """)
            try db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")

            // Keep the external-content FTS table in step with `notes`.
            try db.execute("""
            CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
              INSERT INTO notes_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
            END
            """)
            try db.execute("""
            CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
              INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
            END
            """)
            try db.execute("""
            CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
              INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
              INSERT INTO notes_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
            END
            """)
            try db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '\(version)')")
        }
    }

    private static func storedVersion(_ db: SQLiteDatabase) throws -> Int? {
        let tables = try db.prepare("SELECT COUNT(*) FROM sqlite_master WHERE name = 'meta'")
        guard try tables.step(), tables.int(at: 0) == 1 else { return nil }
        let statement = try db.prepare("SELECT value FROM meta WHERE key = 'schema_version'")
        return try statement.step() ? Int(statement.text(at: 0)) : nil
    }

    private static func dropAll(_ db: SQLiteDatabase) throws {
        try db.transaction {
            for trigger in ["notes_ai", "notes_ad", "notes_au"] { try db.execute("DROP TRIGGER IF EXISTS \(trigger)") }
            for table in ["notes_fts", "embeddings", "tags", "notes", "meta"] { try db.execute("DROP TABLE IF EXISTS \(table)") }
        }
    }
}
