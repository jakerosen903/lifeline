import GRDB

/// Schema history. Add a new registered migration for every change; never edit a shipped one.
enum Migrations {
    /// Every migration identifier in order; the last is the schema the app writes.
    static var versions: [String] { migrator.migrations }
    public static var currentSchemaVersion: String { versions.last ?? "" }

    /// By position in the migration list; a version this app has never heard of is from the future.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        guard let ia = versions.firstIndex(of: a) else { return true }
        guard let ib = versions.firstIndex(of: b) else { return false }
        return ia > ib
    }

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
        // v5 (M4): visibility becomes two flags named by their effect; a session has a kind; the
        // landing exists, so every session that ended before it counts as landed.
        m.registerMigration("v5") { db in
            try db.alter(table: "memory") { t in
                t.add(column: "hidden_from_timeline", .boolean).notNull().defaults(to: false)
                t.add(column: "excluded_from_ai", .boolean).notNull().defaults(to: false)
            }
            try db.execute(sql: "update memory set hidden_from_timeline = 1 where visibility = 'private'")
            try db.alter(table: "session") { t in
                t.add(column: "kind", .text).notNull().defaults(to: "quick")
            }
            try db.execute(sql: "update session set landing_choice_made = 1 where ended_at is not null")
        }
        // v6 (M4 review): "Hide today" is remembered on the session so memories kept later are hidden too.
        m.registerMigration("v6") { db in
            try db.alter(table: "session") { t in
                t.add(column: "hidden_from_timeline", .boolean).notNull().defaults(to: false)
            }
        }
        // M4.1: on-device sentence embeddings for "Same as X?", and a span remembers the card it came from.
        m.registerMigration("v7") { db in
            try db.create(table: "memory_embedding") { t in
                t.primaryKey("memory_id", .text).references("memory", onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("dims", .integer).notNull()
                t.column("vector", .blob).notNull()
            }
            try db.alter(table: "memory_span") { t in
                t.add(column: "title_text", .text)
                t.add(column: "candidate_id", .text)
            }
        }
        m.registerMigration("v8") { db in
            try db.create(table: "story") { t in
                t.primaryKey("id", .text)
                t.column("title", .text)
                t.column("chapter_id", .text).references("chapter", onDelete: .setNull)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(table: "story_moment") { t in
                t.column("story_id", .text).notNull().references("story", onDelete: .cascade)
                t.column("memory_id", .text).notNull().references("memory", onDelete: .cascade).unique()
                t.column("order", .integer).notNull()
                t.primaryKey(["story_id", "memory_id"])
            }
            try db.create(table: "duplicate_pair") { t in
                t.primaryKey("id", .text)
                t.column("a_memory_id", .text).notNull().references("memory", onDelete: .cascade)
                t.column("b_memory_id", .text).notNull().references("memory", onDelete: .cascade)
                t.column("score", .double).notNull()
                t.column("verdict", .text).notNull()
                t.column("status", .text).notNull()
                t.column("decided_at", .datetime)
                t.uniqueKey(["a_memory_id", "b_memory_id"])
            }
            try db.alter(table: "memory_span") { t in
                t.add(column: "continues_order", .integer)
            }
        }
        // v9 (M7, PR A): a memory's kind lives in a column, filled from its card; no card, or a
        // card without a kind, is an event.
        m.registerMigration("v9") { db in
            try db.alter(table: "memory") { t in
                t.add(column: "kind", .text).notNull().defaults(to: "event")
            }
            try db.execute(sql: """
                update memory set kind = (select json_extract(c.payload, '$.kind') from candidate c where c.id = memory.created_from_candidate_id)
                where (select json_extract(c.payload, '$.kind') from candidate c where c.id = memory.created_from_candidate_id)
                      in ('event', 'fact', 'feeling', 'goal', 'other')
                """)
        }
        // v10 (M7, PR B): people, places, things and ideas are entities, with one link table.
        // `place`, `memory_place` and `memory_person` are copied in and kept one release, read nowhere.
        m.registerMigration("v10") { db in
            try db.create(table: "entity") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("detail_text", .text)
                t.column("created_from_candidate_id", .text).references("candidate", onDelete: .setNull)
                t.column("created_at", .datetime).notNull()
                for column in ["earliest", "latest", "likely_start", "likely_end", "granularity", "origin", "evidence_text"] {
                    t.column(column, .text)
                }
                t.column("hidden_from_timeline", .boolean).notNull().defaults(to: false)
                t.column("excluded_from_ai", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "entity_span") { t in
                t.column("entity_id", .text).notNull().references("entity", onDelete: .cascade)
                t.column("segment_id", .text).notNull().references("segment", onDelete: .cascade)
                t.column("start_ms", .integer).notNull()
                t.column("end_ms", .integer).notNull()
                t.column("order", .integer).notNull()
                t.primaryKey(["entity_id", "order"])
            }
            try db.create(table: "moment_entity") { t in
                t.column("memory_id", .text).notNull().references("memory", onDelete: .cascade)
                t.column("entity_id", .text).notNull().references("entity", onDelete: .cascade).indexed()
                t.column("relation", .text).notNull()
                t.column("role_text", .text)
                t.primaryKey(["memory_id", "entity_id", "relation"])
            }
            try db.create(table: "domain_tag") { t in
                t.column("element_kind", .text).notNull()
                t.column("element_id", .text).notNull()
                t.column("text", .text).notNull()
                t.primaryKey(["element_kind", "element_id", "text"])
            }
            // A migrated person or place keeps its id as its entity's id.
            try db.execute(sql: """
                insert into entity (id, type, title, created_at) select id, 'person', display_name, datetime('now') from person;
                insert into entity (id, type, title, created_at) select id, 'place', name_text, datetime('now') from place;
                insert or ignore into moment_entity (memory_id, entity_id, relation, role_text) select memory_id, person_id, 'mention', role_text from memory_person;
                insert or ignore into moment_entity (memory_id, entity_id, relation, role_text) select memory_id, place_id, 'mention', null from memory_place;
                insert into entity_span (entity_id, segment_id, start_ms, end_ms, "order")
                select mp.place_id, ms.segment_id, ms.start_ms, ms.end_ms, 0
                from memory_place mp
                join memory m on m.id = mp.memory_id
                join memory_span ms on ms.memory_id = m.id and ms."order" = 0
                where m.id = (select m2.id from memory_place mp2 join memory m2 on m2.id = mp2.memory_id
                              join memory_span s2 on s2.memory_id = m2.id and s2."order" = 0
                              where mp2.place_id = mp.place_id order by m2.created_at, m2.id limit 1);
                """)
            // The name moves to the entity. Nothing is dropped: `person.display_name` stays one release,
            // read nowhere (like `place`, `memory_place`, `memory_person`), and new rows leave it empty.
            try db.alter(table: "person") { t in
                t.add(column: "entity_id", .text).references("entity", onDelete: .cascade)
            }
            try db.execute(sql: "update person set entity_id = id")
            try db.create(index: "person_entity_id", on: "person", columns: ["entity_id"], unique: true)
            try db.alter(table: "curiosity_item") { t in
                t.add(column: "entity_id", .text).references("entity", onDelete: .cascade)
            }
        }
        return m
    }
}
