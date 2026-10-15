import Foundation
import SQLite3

enum CursorTokenError: Error {
    case notFound
    case unreadable
}

enum CursorStateDatabase {
    /// Logged-in Cursor access token.
    /// `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
    /// table `ItemTable`, key `cursorAuth/accessToken`.
    static func readAccessToken(databaseURL: URL = defaultDatabaseURL()) throws -> String {
        let path = databaseURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw CursorTokenError.notFound
        }

        var db: OpaquePointer?
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, let opened = db else {
            sqlite3_close(db)
            throw CursorTokenError.unreadable
        }
        defer { sqlite3_close(opened) }
        sqlite3_busy_timeout(opened, 1500)

        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(opened, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CursorTokenError.unreadable
        }
        defer { sqlite3_finalize(statement) }

        let key = "cursorAuth/accessToken"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bindStatus = key.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, transient)
        }
        guard bindStatus == SQLITE_OK else {
            throw CursorTokenError.unreadable
        }

        let step = sqlite3_step(statement)
        if step == SQLITE_DONE {
            throw CursorTokenError.notFound
        }
        guard step == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw step == SQLITE_ROW ? CursorTokenError.notFound : CursorTokenError.unreadable
        }

        let token = TokenText.normalize(String(cString: text))
        if token.isEmpty {
            throw CursorTokenError.notFound
        }
        return token
    }

    static func defaultDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }
}
