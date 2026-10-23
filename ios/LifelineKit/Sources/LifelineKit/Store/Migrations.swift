import GRDB

/// Schema history. Add a new registered migration for every change; never edit a shipped one.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "session") { t in
                t.primaryKey("id", .text)
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("audio_path", .text).notNull()
                t.column("stage_log", .text).notNull().defaults(to: "[]")
                t.column("landing_choice_made", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "segment") { t in
                t.primaryKey("id", .text)
                t.column("session_id", .text).notNull().references("session", onDelete: .cascade).indexed()
                t.column("index", .integer).notNull()
                t.column("start_ms", .integer).notNull()
                t.column("end_ms", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("status", .text).notNull()
                t.uniqueKey(["session_id", "index"])
            }
            try db.create(table: "word") { t in
                t.column("segment_id", .text).notNull().references("segment", onDelete: .cascade)
                t.column("index", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("start_ms", .integer).notNull()
                t.column("end_ms", .integer).notNull()
                t.primaryKey(["segment_id", "index"])
            }
            try db.create(table: "person") { t in
                t.primaryKey("id", .text)
                t.column("display_name", .text).notNull()
                t.column("notes", .text)
                t.column("is_owner", .boolean).notNull().defaults(to: false)
                t.column("birth_date", .datetime)
                t.column("birth_date_origin", .text)
            }
            try db.create(indexOn: "person", columns: ["is_owner"])
            try db.create(table: "profile") { t in
                t.primaryKey("id", .integer)
                t.column("display_name", .text)
                t.column("birth_date", .datetime)
                t.column("birth_place_text", .text)
                t.column("free_text", .text)
                t.column("updated_at", .datetime).notNull()
            }
        }
        return m
    }
}
