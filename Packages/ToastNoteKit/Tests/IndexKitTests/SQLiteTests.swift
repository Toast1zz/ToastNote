import Foundation
import Testing
@testable import IndexKit

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("tn-index-\(UUID().uuidString).sqlite")
}

private func scalarText(_ db: SQLiteDatabase, _ sql: String) throws -> String? {
    let statement = try db.prepare(sql)
    return try statement.step() ? statement.text(at: 0) : nil
}

private func scalarInt(_ db: SQLiteDatabase, _ sql: String) throws -> Int64 {
    let statement = try db.prepare(sql)
    return try statement.step() ? statement.int(at: 0) : 0
}

@Suite struct SQLiteTests {
    @Test func bindsAndReadsEveryValueType() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try db.execute("CREATE TABLE t (i INTEGER, r REAL, s TEXT, b BLOB, n TEXT)")
        let insert = try db.prepare("INSERT INTO t VALUES (?, ?, ?, ?, ?)")
        try insert.bind([.int(7), .real(2.5), .text("中文 😀"), .blob(Data([1, 2, 3])), .null])
        _ = try insert.step()

        let select = try db.prepare("SELECT i, r, s, b, n FROM t")
        #expect(try select.step())
        #expect(select.int(at: 0) == 7)
        #expect(select.real(at: 1) == 2.5)
        #expect(select.text(at: 2) == "中文 😀")
        #expect(select.blob(at: 3) == Data([1, 2, 3]))
        #expect(select.isNull(at: 4))
        #expect(try select.step() == false)
    }

    @Test func resetAllowsReuse() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try db.execute("CREATE TABLE t (v INTEGER)")
        let insert = try db.prepare("INSERT INTO t VALUES (?)")
        for value in 1...3 {
            try insert.bind([.int(Int64(value))])
            _ = try insert.step()
            insert.reset()
        }
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM t") == 3)
        #expect(db.lastInsertRowID == 3)
    }

    @Test func transactionCommitsAndRollsBack() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try db.execute("CREATE TABLE t (v INTEGER)")
        try db.transaction { try db.execute("INSERT INTO t VALUES (1)") }
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try db.transaction {
                try db.execute("INSERT INTO t VALUES (2)")
                throw Boom()
            }
        }
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM t") == 1)
    }

    @Test func errorsCarryTheSQLiteMessage() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        do {
            try db.execute("SELECT * FROM missing_table")
            Issue.record("expected an error")
        } catch let error as SQLiteError {
            #expect(error.message.contains("missing_table"))
        }
    }
}

@Suite struct IndexSchemaTests {
    @Test func createsSchema() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try IndexSchema.migrate(db)
        for table in ["notes", "notes_fts", "tags", "embeddings", "meta"] {
            let found = try scalarInt(db, "SELECT COUNT(*) FROM sqlite_master WHERE name = '\(table)'")
            #expect(found == 1, "missing table \(table)")
        }
        #expect(try scalarText(db, "PRAGMA journal_mode")?.lowercased() == "wal")
        #expect(try scalarInt(db, "PRAGMA foreign_keys") == 1)
        #expect(try scalarText(db, "SELECT value FROM meta WHERE key = 'schema_version'") == "\(IndexSchema.version)")
    }

    @Test func ftsTriggersSync() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try IndexSchema.migrate(db)
        try db.execute("INSERT INTO notes (path, title, body, mtime, size) VALUES ('a.md', '调研', '这是设计系统调研的正文', 0, 0)")
        #expect(try scalarText(db, "SELECT notes.path FROM notes_fts JOIN notes ON notes.id = notes_fts.rowid WHERE notes_fts MATCH '设计系统'") == "a.md")

        try db.execute("UPDATE notes SET body = '换成了别的内容' WHERE path = 'a.md'")
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM notes_fts WHERE notes_fts MATCH '设计系统'") == 0)
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM notes_fts WHERE notes_fts MATCH '别的内容'") == 1)

        try db.execute("DELETE FROM notes WHERE path = 'a.md'")
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM notes_fts WHERE notes_fts MATCH '别的内容'") == 0)
    }

    @Test func tagsAreRemovedWithTheirNote() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try IndexSchema.migrate(db)
        try db.execute("INSERT INTO notes (path, title, body, mtime, size) VALUES ('a.md', 'a', 'b', 0, 0)")
        try db.execute("INSERT INTO tags (note_id, tag) VALUES (1, '工作')")
        try db.execute("DELETE FROM notes WHERE id = 1")
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM tags") == 0)
    }

    @Test func versionMismatchRebuilds() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try IndexSchema.migrate(db)
        try db.execute("INSERT INTO notes (path, title, body, mtime, size) VALUES ('a.md', 'a', 'b', 0, 0)")
        try db.execute("UPDATE meta SET value = '0' WHERE key = 'schema_version'")

        try IndexSchema.migrate(db)
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM notes") == 0)
        #expect(try scalarText(db, "SELECT value FROM meta WHERE key = 'schema_version'") == "\(IndexSchema.version)")
    }

    @Test func migratingTwiceKeepsTheData() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        try IndexSchema.migrate(db)
        try db.execute("INSERT INTO notes (path, title, body, mtime, size) VALUES ('a.md', 'a', 'b', 0, 0)")
        try IndexSchema.migrate(db)
        #expect(try scalarInt(db, "SELECT COUNT(*) FROM notes") == 1)
    }
}
