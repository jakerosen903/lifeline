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
        m.registerMigration("v2") { db in
            try db.create(table: "candidate") { t in
                t.primaryKey("id", .text)
                t.column("segment_id", .text).notNull().references("segment", onDelete: .cascade).indexed()
                t.column("extractor_version", .text).notNull()
                t.column("ordinal", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("status", .text).notNull()
                t.column("rejection", .text)
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["segment_id", "extractor_version", "ordinal"])
            }
            try db.create(table: "memory") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("summary_quote", .text).notNull()
                t.column("visibility", .text).notNull()
                t.column("chapter_id", .text)
                t.column("created_from_candidate_id", .text).notNull().references("candidate")
                t.column("created_at", .datetime).notNull()
                t.column("earliest", .text)
                t.column("latest", .text)
                t.column("likely_start", .text)
                t.column("likely_end", .text)
                t.column("granularity", .text)
                t.column("origin", .text)
                t.column("evidence_text", .text)
            }
            try db.create(table: "memory_span") { t in
                t.column("memory_id", .text).notNull().references("memory", onDelete: .cascade)
                t.column("segment_id", .text).notNull().references("segment", onDelete: .cascade).indexed()
                t.column("start_ms", .integer).notNull()
                t.column("end_ms", .integer).notNull()
                t.column("order", .integer).notNull()
                t.primaryKey(["memory_id", "order"])
            }
            try db.create(table: "place") { t in
                t.primaryKey("id", .text)
                t.column("name_text", .text).notNull()
                t.column("lat", .double)
                t.column("lon", .double)
            }
            try db.create(table: "memory_person") { t in
                t.column("memory_id", .text).notNull().references("memory", onDelete: .cascade)
                t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
                t.column("role_text", .text)
                t.primaryKey(["memory_id", "person_id"])
            }
            try db.create(table: "memory_place") { t in
                t.column("memory_id", .text).notNull().references("memory", onDelete: .cascade)
                t.column("place_id", .text).notNull().references("place", onDelete: .cascade)
                t.primaryKey(["memory_id", "place_id"])
            }
            try db.create(table: "alias") { t in
                t.column("person_id", .text).notNull().references("person", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.primaryKey(["person_id", "text"])
            }
            try db.create(table: "mention") { t in
                t.primaryKey("id", .text)
                t.column("segment_id", .text).notNull().references("segment", onDelete: .cascade).indexed()
                t.column("text", .text).notNull()
                t.column("status", .text).notNull()
                t.column("person_id", .text).references("person", onDelete: .setNull)
            }
            try db.create(table: "anchor") { t in
                t.primaryKey("id", .text)
                t.column("memory_id", .text).notNull().references("memory", onDelete: .cascade).indexed()
                t.column("phrase", .text).notNull()
                t.column("relation", .text).notNull()
                t.column("target_kind", .text).notNull()
                t.column("target_id", .text)
                t.column("value", .text)
                t.column("resolved", .boolean).notNull().defaults(to: false)
            }
        }
        m.registerMigration("v3") { db in
            try db.alter(table: "mention") { t in
                t.add(column: "relation_text", .text)
            }
        }
        m.registerMigration("v4") { db in
            try db.create(table: "chapter") { t in
                t.primaryKey("id", .text)
                t.column("title", .text)
                for column in ["earliest", "latest", "likely_start", "likely_end", "granularity", "origin", "evidence_text"] {
                    t.column(column, .text)
                }
                t.column("order", .integer).notNull()
            }
            try db.create(table: "collection") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
            }
            try db.create(table: "collection_memory") { t in
                t.column("collection_id", .text).notNull().references("collection", onDelete: .cascade)
                t.column("memory_id", .text).notNull().references("memory", onDelete: .cascade)
                t.primaryKey(["collection_id", "memory_id"])
            }
            try db.create(table: "curiosity_item") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("text", .text).notNull()
                t.column("payoff_count", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull()
                t.column("source_memory_id", .text).references("memory", onDelete: .setNull)
                t.column("target_memory_id", .text).references("memory", onDelete: .setNull)
            }
            try db.create(table: "prompt_log") { t in
                t.column("prompt_id", .text).notNull()
                t.column("session_id", .text).notNull().references("session", onDelete: .cascade)
                t.column("used_at", .datetime).notNull()
                t.primaryKey(["prompt_id", "session_id"])
            }
            // memory: the candidate link becomes optional (floating memories have none) and the
            // chapter link gets its foreign key. SQLite cannot alter those, so the table is rebuilt.
            // Child tables keep their references: SQLite rewrites them on RENAME.
            try db.create(table: "memory_v4") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("summary_quote", .text).notNull()
                t.column("visibility", .text).notNull()
                t.column("chapter_id", .text).references("chapter", onDelete: .setNull)
                t.column("created_from_candidate_id", .text).references("candidate")
                t.column("created_at", .datetime).notNull()
                for column in ["earliest", "latest", "likely_start", "likely_end", "granularity", "origin", "evidence_text"] {
                    t.column(column, .text)
                }
            }
            try db.execute(sql: """
                insert into memory_v4 select id, title, summary_quote, visibility, chapter_id, created_from_candidate_id, created_at,
                    earliest, latest, likely_start, likely_end, granularity, origin, evidence_text from memory
                """)
            try db.drop(table: "memory")
            try db.rename(table: "memory_v4", to: "memory")
            try db.create(indexOn: "memory", columns: ["chapter_id"])
            try db.alter(table: "anchor") { t in
                t.add(column: "target_text", .text)
            }
        }
        return m
    }
}
