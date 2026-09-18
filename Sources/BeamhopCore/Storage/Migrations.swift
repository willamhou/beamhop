import Foundation
import GRDB

/// Schema migrations (spec §8.1 + §12.1). The provenance columns are part of the v1 table
/// (created NOT NULL with defaults) rather than tacked on via ALTER.
enum Migrations {
    static func migrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        // During development, allow erasing on an incompatible schema change.
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = false  // keep false: we test corruption recovery explicitly
        #endif

        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE captures (
                    id              TEXT PRIMARY KEY,
                    created_at      INTEGER NOT NULL,
                    source          TEXT NOT NULL,
                    app_bundle_id   TEXT NOT NULL,
                    app_name        TEXT NOT NULL,
                    window_title    TEXT,
                    url             TEXT,
                    selected_text   TEXT,
                    extracted_body  TEXT,
                    domain_hint     TEXT,
                    user_note       TEXT,
                    screenshot_path TEXT,
                    deleted_at      INTEGER,
                    -- provenance (§12.1)
                    pid                 INTEGER NOT NULL,
                    app_version         TEXT,
                    os_version          TEXT NOT NULL,
                    beamhop_version     TEXT NOT NULL,
                    ax_tree_snapshot    TEXT,
                    capture_method      TEXT NOT NULL,
                    extension_version   TEXT,
                    is_private          INTEGER NOT NULL DEFAULT 0,
                    truncated           INTEGER NOT NULL DEFAULT 0,
                    capture_duration_ms INTEGER
                );
                """)

            try db.execute(sql: """
                CREATE TABLE deliveries (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    capture_id    TEXT NOT NULL REFERENCES captures(id),
                    target        TEXT NOT NULL,
                    delivered_at  INTEGER NOT NULL,
                    status        TEXT NOT NULL,
                    error_message TEXT
                );
                """)

            try db.execute(sql: "CREATE INDEX idx_captures_created ON captures(created_at DESC);")
            try db.execute(sql: "CREATE INDEX idx_deliveries_capture ON deliveries(capture_id);")

            // Dual FTS5 (spec §8.1): unicode61 for word-level, trigram for CJK substring.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE captures_fts USING fts5(
                    window_title, url, selected_text, extracted_body, user_note,
                    content='captures', content_rowid='rowid',
                    tokenize = 'unicode61 remove_diacritics 2'
                );
                """)
            try db.execute(sql: """
                CREATE VIRTUAL TABLE captures_fts_cjk USING fts5(
                    window_title, selected_text, extracted_body, user_note,
                    content='captures', content_rowid='rowid',
                    tokenize = 'trigram'
                );
                """)

            // External-content FTS sync triggers (codex review): INSERT, DELETE (via 'delete'
            // command), UPDATE (delete old row then insert new). Keep both FTS tables in sync.
            try db.execute(sql: """
                CREATE TRIGGER captures_ai AFTER INSERT ON captures BEGIN
                    INSERT INTO captures_fts(rowid, window_title, url, selected_text, extracted_body, user_note)
                        VALUES (new.rowid, new.window_title, new.url, new.selected_text, new.extracted_body, new.user_note);
                    INSERT INTO captures_fts_cjk(rowid, window_title, selected_text, extracted_body, user_note)
                        VALUES (new.rowid, new.window_title, new.selected_text, new.extracted_body, new.user_note);
                END;
                """)
            try db.execute(sql: """
                CREATE TRIGGER captures_ad AFTER DELETE ON captures BEGIN
                    INSERT INTO captures_fts(captures_fts, rowid, window_title, url, selected_text, extracted_body, user_note)
                        VALUES ('delete', old.rowid, old.window_title, old.url, old.selected_text, old.extracted_body, old.user_note);
                    INSERT INTO captures_fts_cjk(captures_fts_cjk, rowid, window_title, selected_text, extracted_body, user_note)
                        VALUES ('delete', old.rowid, old.window_title, old.selected_text, old.extracted_body, old.user_note);
                END;
                """)
            try db.execute(sql: """
                CREATE TRIGGER captures_au AFTER UPDATE ON captures BEGIN
                    INSERT INTO captures_fts(captures_fts, rowid, window_title, url, selected_text, extracted_body, user_note)
                        VALUES ('delete', old.rowid, old.window_title, old.url, old.selected_text, old.extracted_body, old.user_note);
                    INSERT INTO captures_fts_cjk(captures_fts_cjk, rowid, window_title, selected_text, extracted_body, user_note)
                        VALUES ('delete', old.rowid, old.window_title, old.selected_text, old.extracted_body, old.user_note);
                    INSERT INTO captures_fts(rowid, window_title, url, selected_text, extracted_body, user_note)
                        VALUES (new.rowid, new.window_title, new.url, new.selected_text, new.extracted_body, new.user_note);
                    INSERT INTO captures_fts_cjk(rowid, window_title, selected_text, extracted_body, user_note)
                        VALUES (new.rowid, new.window_title, new.selected_text, new.extracted_body, new.user_note);
                END;
                """)
        }

        // v2 (code review P2-1): FK enforcement is now ON, but v1 declared the FK without a
        // cascade — a physical purge of captures would abort on referencing deliveries. Clean
        // legacy orphans (from the FK-off era), rebuild the table with ON DELETE CASCADE, and
        // recreate the index (it dies with the old table).
        m.registerMigration("v2") { db in
            try db.execute(sql: "DELETE FROM deliveries WHERE capture_id NOT IN (SELECT id FROM captures);")
            try db.execute(sql: """
                CREATE TABLE deliveries_v2 (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    capture_id    TEXT NOT NULL REFERENCES captures(id) ON DELETE CASCADE,
                    target        TEXT NOT NULL,
                    delivered_at  INTEGER NOT NULL,
                    status        TEXT NOT NULL,
                    error_message TEXT
                );
                """)
            try db.execute(sql: """
                INSERT INTO deliveries_v2 (id, capture_id, target, delivered_at, status, error_message)
                    SELECT id, capture_id, target, delivered_at, status, error_message FROM deliveries;
                """)
            try db.execute(sql: "DROP TABLE deliveries;")
            try db.execute(sql: "ALTER TABLE deliveries_v2 RENAME TO deliveries;")
            try db.execute(sql: "CREATE INDEX idx_deliveries_capture ON deliveries(capture_id);")
        }
        return m
    }
}
