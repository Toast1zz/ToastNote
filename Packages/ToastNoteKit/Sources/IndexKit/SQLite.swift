import Foundation
import SQLite3

/// SQLite's destructor flag that makes it copy bound text and blobs.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

public enum SQLiteValue: Equatable, Sendable {
    case int(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null
}

/// A thin wrapper over the system `libsqlite3`; no third-party SQLite library (spec §5.3).
/// Not thread-safe: `NoteIndex` owns one and confines it to its actor.
public final class SQLiteDatabase {
    fileprivate var handle: OpaquePointer?

    public init(url: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let error = SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
            sqlite3_close(handle)
            throw error
        }
        // Rebuildable data, so favor speed and keep readers from blocking the writer.
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastError: SQLiteError {
        SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }

    public func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &message)
        guard status == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            throw SQLiteError(code: status, message: text)
        }
    }

    public func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError
        }
        return SQLiteStatement(statement: statement, database: self)
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Runs `body` in a transaction: committed when it returns, rolled back when it throws.
    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}

public final class SQLiteStatement {
    private let statement: OpaquePointer
    private unowned let database: SQLiteDatabase

    fileprivate init(statement: OpaquePointer, database: SQLiteDatabase) {
        self.statement = statement
        self.database = database
    }

    deinit {
        sqlite3_finalize(statement)
    }

    /// Binds positional parameters (1-based in SQLite, 0-based here).
    public func bind(_ values: [SQLiteValue]) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .int(let number): status = sqlite3_bind_int64(statement, index, number)
            case .real(let number): status = sqlite3_bind_double(statement, index, number)
            case .text(let text): status = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case .blob(let data):
                status = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), sqliteTransient) }
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw database.lastError }
        }
    }

    /// Advances to the next row; false when there are no more (or the statement was a write that finished).
    @discardableResult
    public func step() throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw database.lastError
        }
    }

    public func reset() {
        sqlite3_reset(statement)
    }

    public func int(at column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    public func real(at column: Int32) -> Double { sqlite3_column_double(statement, column) }
    public func isNull(at column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }

    public func text(at column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    public func blob(at column: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
    }
}
