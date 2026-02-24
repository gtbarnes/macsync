import Foundation
import SQLite3

class HistoryStore {
    private var db: OpaquePointer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("MacSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("history.db").path

        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            migrate()
        }
    }

    deinit {
        sqlite3_close(db)
    }

    private func migrate() {
        let sql = """
        CREATE TABLE IF NOT EXISTS completed_tasks (
            id TEXT PRIMARY KEY,
            profileName TEXT NOT NULL,
            syncMode TEXT NOT NULL,
            startTime REAL NOT NULL,
            endTime REAL NOT NULL,
            filesTransferred INTEGER NOT NULL,
            bytesTransferred INTEGER NOT NULL,
            errors INTEGER NOT NULL,
            success INTEGER NOT NULL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func save(_ task: CompletedTask) {
        let sql = """
        INSERT OR REPLACE INTO completed_tasks
        (id, profileName, syncMode, startTime, endTime, filesTransferred, bytesTransferred, errors, success)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_bind_text(stmt, 1, task.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, task.profileName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, task.syncMode.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, task.startTime.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, task.endTime.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 6, Int32(task.filesTransferred))
        sqlite3_bind_int64(stmt, 7, task.bytesTransferred)
        sqlite3_bind_int(stmt, 8, Int32(task.errors))
        sqlite3_bind_int(stmt, 9, task.success ? 1 : 0)

        sqlite3_step(stmt)
    }

    func loadHistory(limit: Int = 100) -> [CompletedTask] {
        let sql = "SELECT * FROM completed_tasks ORDER BY endTime DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [CompletedTask] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID()
            let profileName = String(cString: sqlite3_column_text(stmt, 1))
            let syncMode = SyncMode(rawValue: String(cString: sqlite3_column_text(stmt, 2))) ?? .mirror
            let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            let filesTransferred = Int(sqlite3_column_int(stmt, 5))
            let bytesTransferred = sqlite3_column_int64(stmt, 6)
            let errors = Int(sqlite3_column_int(stmt, 7))
            let success = sqlite3_column_int(stmt, 8) != 0

            results.append(CompletedTask(
                id: id, profileName: profileName, syncMode: syncMode,
                startTime: startTime, endTime: endTime,
                filesTransferred: filesTransferred, bytesTransferred: bytesTransferred,
                errors: errors, success: success
            ))
        }
        return results
    }

    func clearHistory() {
        sqlite3_exec(db, "DELETE FROM completed_tasks;", nil, nil, nil)
    }
}
