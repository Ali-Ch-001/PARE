// PareStorage.swift - Transactional SQLite Persistence & Checkpoint State Machine
import Foundation
import SQLite3

public struct PersistedCluster {
    public let clusterId: Int64
    public let heroIdentifier: String
    public let memberIdentifiers: [String]
    public let reclaimableBytes: UInt64
    public let coverageScore: Float
    public let createdAt: Date
}

public final class PareStorage: @unchecked Sendable {
    public static let shared = PareStorage()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.pare.storage.queue", qos: .utility)

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        guard let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let dbURL = docDir.appendingPathComponent("PareStorage.sqlite")

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("[PareStorage] Failed to open SQLite database at \(dbURL.path)")
        } else {
            // Enable Write-Ahead Logging (WAL) for high concurrency and zero reader locks
            var err: UnsafeMutablePointer<CChar>?
            sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, &err)
            sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, &err)
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS assets (
            local_id TEXT PRIMARY KEY,
            hash_w0 INTEGER,
            hash_w1 INTEGER,
            hash_w2 INTEGER,
            hash_w3 INTEGER,
            quality REAL,
            file_bytes INTEGER,
            is_screenshot INTEGER,
            is_burst INTEGER,
            has_valid_visual_hash INTEGER DEFAULT 1,
            creation_date INTEGER,
            scanned_at INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_assets_scanned ON assets(scanned_at);
        CREATE INDEX IF NOT EXISTS idx_assets_creation ON assets(creation_date);

        CREATE TABLE IF NOT EXISTS clusters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hero_id TEXT,
            member_count INTEGER,
            reclaimable_bytes INTEGER,
            coverage_score REAL,
            created_at INTEGER,
            status TEXT DEFAULT 'pending'
        );

        CREATE TABLE IF NOT EXISTS cluster_members (
            cluster_id INTEGER,
            asset_id TEXT,
            is_hero INTEGER DEFAULT 0,
            PRIMARY KEY (cluster_id, asset_id)
        );

        CREATE TABLE IF NOT EXISTS pipeline_checkpoint (
            id INTEGER PRIMARY KEY CHECK(id = 1),
            stage TEXT NOT NULL,
            last_asset_id TEXT,
            total_scanned INTEGER,
            updated_at INTEGER
        );

        CREATE TABLE IF NOT EXISTS telemetry_stats (
            key TEXT PRIMARY KEY,
            num_value INTEGER,
            text_value TEXT
        );
        """
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let err = err {
                print("[PareStorage] Table creation error: \(String(cString: err))")
                sqlite3_free(err)
            }
        }

        // Gracefully migrate existing schemas (only add columns that are genuinely missing)
        migrateColumnIfNeeded("has_valid_visual_hash", "INTEGER DEFAULT 1")
        migrateColumnIfNeeded("creation_date", "INTEGER")
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_assets_scanned ON assets(scanned_at);", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_assets_creation ON assets(creation_date);", nil, nil, nil)
    }

    /// Adds a column to the assets table only if it does not already exist
    private func migrateColumnIfNeeded(_ column: String, _ definition: String) {
        var hasColumn = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(assets);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1), String(cString: name) == column {
                    hasColumn = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)

        if !hasColumn {
            sqlite3_exec(db, "ALTER TABLE assets ADD COLUMN \(column) \(definition);", nil, nil, nil)
        }
    }

    // MARK: - Fast Index Lookups & Hydration for 50K Scaling

    /// Fast lookup of all asset IDs already hashed and persisted in SQLite
    public func knownAssetIdentifiers() -> Set<String> {
        var set = Set<String>()
        queue.sync {
            let sql = "SELECT local_id FROM assets;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(stmt, 0) {
                        set.insert(String(cString: cStr))
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        return set
    }

    /// Hydrates previously hashed candidates directly from SQLite (Zero Vision re-computation)
    public func loadPersistedCandidates() -> [ScannedCandidate] {
        var results: [ScannedCandidate] = []
        queue.sync {
            let sql = """
            SELECT local_id, hash_w0, hash_w1, hash_w2, hash_w3, quality, file_bytes, is_screenshot, is_burst, has_valid_visual_hash, creation_date, scanned_at
            FROM assets;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let idStr = sqlite3_column_text(stmt, 0) else { continue }
                    let localId = String(cString: idStr)
                    let w0 = UInt32(sqlite3_column_int64(stmt, 1))
                    let w1 = UInt32(sqlite3_column_int64(stmt, 2))
                    let w2 = UInt32(sqlite3_column_int64(stmt, 3))
                    let w3 = UInt32(sqlite3_column_int64(stmt, 4))
                    let quality = Float(sqlite3_column_double(stmt, 5))
                    let bytes = UInt64(sqlite3_column_int64(stmt, 6))
                    let isScreenshot = sqlite3_column_int(stmt, 7) == 1
                    let isBurst = sqlite3_column_int(stmt, 8) == 1
                    let hasValidVisual = sqlite3_column_int(stmt, 9) == 1
                    let creationTime = sqlite3_column_int64(stmt, 10)
                    let scannedTime = sqlite3_column_int64(stmt, 11)
                    let date = creationTime > 0
                        ? Date(timeIntervalSince1970: TimeInterval(creationTime))
                        : (scannedTime > 0 ? Date(timeIntervalSince1970: TimeInterval(scannedTime)) : nil)

                    results.append(ScannedCandidate(
                        localIdentifier: localId,
                        hashWords: [w0, w1, w2, w3],
                        qualityScore: quality,
                        fileBytes: bytes,
                        creationDate: date,
                        isScreenshot: isScreenshot,
                        isBurst: isBurst,
                        hasValidVisualHash: hasValidVisual
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }
        return results
    }

    /// Fast indexed lookup of specific candidates by local identifiers
    public func loadPersistedCandidates(for localIdentifiers: [String]) -> [ScannedCandidate] {
        guard !localIdentifiers.isEmpty else { return [] }
        var results: [ScannedCandidate] = []
        queue.sync {
            let sql = """
            SELECT local_id, hash_w0, hash_w1, hash_w2, hash_w3, quality, file_bytes, is_screenshot, is_burst, has_valid_visual_hash, creation_date, scanned_at
            FROM assets WHERE local_id = ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                for id in localIdentifiers {
                    sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        guard let idStr = sqlite3_column_text(stmt, 0) else {
                            sqlite3_reset(stmt)
                            continue
                        }
                        let localId = String(cString: idStr)
                        let w0 = UInt32(sqlite3_column_int64(stmt, 1))
                        let w1 = UInt32(sqlite3_column_int64(stmt, 2))
                        let w2 = UInt32(sqlite3_column_int64(stmt, 3))
                        let w3 = UInt32(sqlite3_column_int64(stmt, 4))
                        let quality = Float(sqlite3_column_double(stmt, 5))
                        let bytes = UInt64(sqlite3_column_int64(stmt, 6))
                        let isScreenshot = sqlite3_column_int(stmt, 7) == 1
                        let isBurst = sqlite3_column_int(stmt, 8) == 1
                        let hasValidVisual = sqlite3_column_int(stmt, 9) == 1
                        let creationTime = sqlite3_column_int64(stmt, 10)
                        let scannedTime = sqlite3_column_int64(stmt, 11)
                        let date = creationTime > 0
                            ? Date(timeIntervalSince1970: TimeInterval(creationTime))
                            : (scannedTime > 0 ? Date(timeIntervalSince1970: TimeInterval(scannedTime)) : nil)

                        results.append(ScannedCandidate(
                            localIdentifier: localId,
                            hashWords: [w0, w1, w2, w3],
                            qualityScore: quality,
                            fileBytes: bytes,
                            creationDate: date,
                            isScreenshot: isScreenshot,
                            isBurst: isBurst,
                            hasValidVisualHash: hasValidVisual
                        ))
                    }
                    sqlite3_reset(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }
        return results
    }

    /// Transactional batch upsert of newly scanned candidates (Flushed before clustering)
    public func upsertAssetHashes(_ candidates: [ScannedCandidate]) {
        guard !candidates.isEmpty else { return }
        queue.sync {
            sqlite3_exec(self.db, "BEGIN TRANSACTION;", nil, nil, nil)
            let sql = """
            INSERT OR REPLACE INTO assets (local_id, hash_w0, hash_w1, hash_w2, hash_w3, quality, file_bytes, is_screenshot, is_burst, has_valid_visual_hash, creation_date, scanned_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                let now = Int64(Date().timeIntervalSince1970)
                for c in candidates {
                    sqlite3_bind_text(stmt, 1, (c.localIdentifier as NSString).utf8String, -1, nil)
                    if c.hashWords.count >= 4 {
                        sqlite3_bind_int64(stmt, 2, Int64(c.hashWords[0]))
                        sqlite3_bind_int64(stmt, 3, Int64(c.hashWords[1]))
                        sqlite3_bind_int64(stmt, 4, Int64(c.hashWords[2]))
                        sqlite3_bind_int64(stmt, 5, Int64(c.hashWords[3]))
                    } else {
                        sqlite3_bind_int64(stmt, 2, 0)
                        sqlite3_bind_int64(stmt, 3, 0)
                        sqlite3_bind_int64(stmt, 4, 0)
                        sqlite3_bind_int64(stmt, 5, 0)
                    }
                    sqlite3_bind_double(stmt, 6, Double(c.qualityScore))
                    sqlite3_bind_int64(stmt, 7, Int64(c.fileBytes))
                    sqlite3_bind_int(stmt, 8, c.isScreenshot ? 1 : 0)
                    sqlite3_bind_int(stmt, 9, c.isBurst ? 1 : 0)
                    sqlite3_bind_int(stmt, 10, c.hasValidVisualHash ? 1 : 0)
                    let cTime = c.creationDate != nil ? Int64(c.creationDate!.timeIntervalSince1970) : 0
                    sqlite3_bind_int64(stmt, 11, cTime)
                    sqlite3_bind_int64(stmt, 12, now)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)
            sqlite3_exec(self.db, "COMMIT;", nil, nil, nil)
        }
    }

    // MARK: - Checkpoint State Machine (For BGProcessingTask Resume)

    public func saveCheckpoint(stage: String, lastAssetId: String?, totalScanned: Int) {
        queue.async {
            let sql = """
            INSERT INTO pipeline_checkpoint (id, stage, last_asset_id, total_scanned, updated_at)
            VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                stage = excluded.stage,
                last_asset_id = excluded.last_asset_id,
                total_scanned = excluded.total_scanned,
                updated_at = excluded.updated_at;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (stage as NSString).utf8String, -1, nil)
                if let lastId = lastAssetId {
                    sqlite3_bind_text(stmt, 2, (lastId as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                sqlite3_bind_int(stmt, 3, Int32(totalScanned))
                sqlite3_bind_int64(stmt, 4, Int64(Date().timeIntervalSince1970))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func loadCheckpoint() -> (stage: String, lastAssetId: String?, totalScanned: Int)? {
        var result: (stage: String, lastAssetId: String?, totalScanned: Int)? = nil
        queue.sync {
            let sql = "SELECT stage, last_asset_id, total_scanned FROM pipeline_checkpoint WHERE id = 1 LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let stage = String(cString: sqlite3_column_text(stmt, 0))
                    let lastId: String? = (sqlite3_column_type(stmt, 1) != SQLITE_NULL)
                        ? String(cString: sqlite3_column_text(stmt, 1))
                        : nil
                    let total = Int(sqlite3_column_int(stmt, 2))
                    result = (stage, lastId, total)
                }
            }
            sqlite3_finalize(stmt)
        }
        return result
    }

    public func clearCheckpoint() {
        queue.async {
            let sql = "DELETE FROM pipeline_checkpoint WHERE id = 1;"
            sqlite3_exec(self.db, sql, nil, nil, nil)
        }
    }

    // MARK: - Asset & Cluster Persistence

    public func saveScannedAssets(_ candidates: [ScannedCandidate]) {
        queue.async {
            sqlite3_exec(self.db, "BEGIN TRANSACTION;", nil, nil, nil)
            let sql = """
            INSERT OR REPLACE INTO assets (local_id, hash_w0, hash_w1, hash_w2, hash_w3, quality, file_bytes, is_screenshot, is_burst, has_valid_visual_hash, creation_date, scanned_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                let now = Int64(Date().timeIntervalSince1970)
                for c in candidates {
                    sqlite3_bind_text(stmt, 1, (c.localIdentifier as NSString).utf8String, -1, nil)
                    if c.hashWords.count >= 4 {
                        sqlite3_bind_int64(stmt, 2, Int64(c.hashWords[0]))
                        sqlite3_bind_int64(stmt, 3, Int64(c.hashWords[1]))
                        sqlite3_bind_int64(stmt, 4, Int64(c.hashWords[2]))
                        sqlite3_bind_int64(stmt, 5, Int64(c.hashWords[3]))
                    } else {
                        sqlite3_bind_int64(stmt, 2, 0)
                        sqlite3_bind_int64(stmt, 3, 0)
                        sqlite3_bind_int64(stmt, 4, 0)
                        sqlite3_bind_int64(stmt, 5, 0)
                    }
                    sqlite3_bind_double(stmt, 6, Double(c.qualityScore))
                    sqlite3_bind_int64(stmt, 7, Int64(c.fileBytes))
                    sqlite3_bind_int(stmt, 8, c.isScreenshot ? 1 : 0)
                    sqlite3_bind_int(stmt, 9, c.isBurst ? 1 : 0)
                    sqlite3_bind_int(stmt, 10, c.hasValidVisualHash ? 1 : 0)
                    let cTime = c.creationDate != nil ? Int64(c.creationDate!.timeIntervalSince1970) : 0
                    sqlite3_bind_int64(stmt, 11, cTime)
                    sqlite3_bind_int64(stmt, 12, now)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)
            sqlite3_exec(self.db, "COMMIT;", nil, nil, nil)
        }
    }

    /// Purges deleted asset IDs from the SQLite WAL index so they can never be re-hydrated or re-clustered
    public func removeAssets(localIdentifiers: [String]) {
        guard !localIdentifiers.isEmpty else { return }
        queue.sync {
            sqlite3_exec(self.db, "BEGIN TRANSACTION;", nil, nil, nil)
            let sql = "DELETE FROM assets WHERE local_id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                for id in localIdentifiers {
                    sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)
            sqlite3_exec(self.db, "COMMIT;", nil, nil, nil)
        }
    }

    public func saveCluster(
        heroIdentifier: String,
        memberIdentifiers: [String],
        reclaimableBytes: UInt64,
        coverageScore: Float
    ) -> Int64 {
        var clusterId: Int64 = -1
        queue.sync {
            let sql = """
            INSERT INTO clusters (hero_id, member_count, reclaimable_bytes, coverage_score, created_at, status)
            VALUES (?, ?, ?, ?, ?, 'pending');
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (heroIdentifier as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 2, Int32(memberIdentifiers.count))
                sqlite3_bind_int64(stmt, 3, Int64(reclaimableBytes))
                sqlite3_bind_double(stmt, 4, Double(coverageScore))
                sqlite3_bind_int64(stmt, 5, Int64(Date().timeIntervalSince1970))

                if sqlite3_step(stmt) == SQLITE_DONE {
                    clusterId = sqlite3_last_insert_rowid(self.db)
                }
            }
            sqlite3_finalize(stmt)

            if clusterId > 0 {
                let memberSql = "INSERT INTO cluster_members (cluster_id, asset_id, is_hero) VALUES (?, ?, ?);"
                var mStmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, memberSql, -1, &mStmt, nil) == SQLITE_OK {
                    for memberId in memberIdentifiers {
                        sqlite3_bind_int64(mStmt, 1, clusterId)
                        sqlite3_bind_text(mStmt, 2, (memberId as NSString).utf8String, -1, nil)
                        sqlite3_bind_int(mStmt, 3, (memberId == heroIdentifier) ? 1 : 0)
                        sqlite3_step(mStmt)
                        sqlite3_reset(mStmt)
                    }
                }
                sqlite3_finalize(mStmt)
            }
        }
        return clusterId
    }

    public func fetchPendingClusters() -> [PersistedCluster] {
        var clusters: [PersistedCluster] = []
        queue.sync {
            let sql = "SELECT id, hero_id, member_count, reclaimable_bytes, coverage_score, created_at FROM clusters WHERE status = 'pending' ORDER BY reclaimable_bytes DESC;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let cid = sqlite3_column_int64(stmt, 0)
                    let hero = String(cString: sqlite3_column_text(stmt, 1))
                    let bytes = UInt64(sqlite3_column_int64(stmt, 3))
                    let score = Float(sqlite3_column_double(stmt, 4))
                    let created = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5)))

                    clusters.append(PersistedCluster(
                        clusterId: cid,
                        heroIdentifier: hero,
                        memberIdentifiers: [],
                        reclaimableBytes: bytes,
                        coverageScore: score,
                        createdAt: created
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }
        return clusters
    }

    public func markClusterResolved(clusterId: Int64, status: String = "resolved") {
        queue.async {
            let sql = "UPDATE clusters SET status = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (status as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(stmt, 2, clusterId)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Lifetime Storage Statistics

    public func getTotalReclaimedBytes() -> Int64 {
        var total: Int64 = 0
        queue.sync {
            let sql = "SELECT num_value FROM telemetry_stats WHERE key = 'total_reclaimed_bytes' LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    total = sqlite3_column_int64(stmt, 0)
                }
            }
            sqlite3_finalize(stmt)
        }
        return total
    }

    public func addReclaimedBytes(_ bytes: Int64) {
        queue.async {
            let sql = """
            INSERT INTO telemetry_stats (key, num_value) VALUES ('total_reclaimed_bytes', ?)
            ON CONFLICT(key) DO UPDATE SET num_value = num_value + excluded.num_value;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, bytes)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func addCategoryReclaimedBytes(category: String, bytes: Int64) {
        queue.async {
            let key = "reclaimed_" + category.lowercased()
            let sql = """
            INSERT INTO telemetry_stats (key, num_value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET num_value = num_value + excluded.num_value;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(stmt, 2, bytes)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func getCategoryBreakdown() -> [String: Int64] {
        var breakdown: [String: Int64] = [:]
        queue.sync {
            let sql = "SELECT key, num_value FROM telemetry_stats WHERE key LIKE 'reclaimed_%';"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let k = sqlite3_column_text(stmt, 0) {
                        let keyStr = String(cString: k).replacingOccurrences(of: "reclaimed_", with: "")
                        let val = sqlite3_column_int64(stmt, 1)
                        breakdown[keyStr] = val
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        return breakdown
    }

    public func addCleanedItemsCount(_ count: Int) {
        queue.async {
            let sql = """
            INSERT INTO telemetry_stats (key, num_value) VALUES ('cleaned_items_count', ?)
            ON CONFLICT(key) DO UPDATE SET num_value = num_value + excluded.num_value;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(count))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func getCleanedItemsCount() -> Int64 {
        var total: Int64 = 0
        queue.sync {
            let sql = "SELECT num_value FROM telemetry_stats WHERE key = 'cleaned_items_count' LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    total = sqlite3_column_int64(stmt, 0)
                }
            }
            sqlite3_finalize(stmt)
        }
        return total
    }

    /// Resets lifetime storage telemetry back to zero
    public func resetReclaimedStats() {
        queue.sync {
            _ = sqlite3_exec(self.db, "DELETE FROM telemetry_stats WHERE key LIKE 'reclaimed_%' OR key IN ('total_reclaimed_bytes', 'cleaned_items_count');", nil, nil, nil)
        }
    }
}
