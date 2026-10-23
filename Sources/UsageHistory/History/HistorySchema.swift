import UsageCore
import GRDB

/// Spec §8 schema. Migration v1 only; later versions append migrations.
enum HistorySchema {
    static let version = 1

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE sample (
                  account_id TEXT NOT NULL,
                  meter      TEXT NOT NULL,
                  ts         INTEGER NOT NULL,
                  percent    REAL,
                  used       REAL,
                  limit_v    REAL,
                  resets_at  INTEGER,
                  PRIMARY KEY (account_id, meter, ts)
                ) WITHOUT ROWID;
                CREATE TABLE sample_hourly (
                  account_id TEXT NOT NULL, meter TEXT NOT NULL, hour INTEGER NOT NULL,
                  percent_max REAL, percent_last REAL, resets_at_last INTEGER,
                  PRIMARY KEY (account_id, meter, hour)
                ) WITHOUT ROWID;
                CREATE TABLE spend_sample (
                  account_id TEXT NOT NULL, ts INTEGER NOT NULL,
                  used_minor INTEGER, limit_minor INTEGER, currency TEXT, exponent INTEGER,
                  PRIMARY KEY (account_id, ts)
                ) WITHOUT ROWID;
                CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
                """)
            try db.execute(sql: "INSERT INTO meta (key, value) VALUES ('schema_version', ?)", arguments: ["\(version)"])
        }
        return m
    }
}
