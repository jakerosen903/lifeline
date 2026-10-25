import Foundation
import GRDB

/// Domains as free-text tags on memories and entities (M7). No fixed list: a tag is whatever
/// the person accepted or typed. Tags compare ignoring case and outer whitespace.
public struct DomainTagRepository: Sendable {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    /// A second tag with the same words (any case) is a no-op.
    public func tag(_ kind: ElementKind, _ id: String, _ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try db.writer.write { db in
            let exists = try Int.fetchOne(db, sql: "select count(*) from domain_tag where element_kind = ? and element_id = ? and lower(text) = ?",
                                          arguments: [kind.rawValue, id, PeopleRepository.normalize(trimmed)]) ?? 0
            guard exists == 0 else { return }
            try db.execute(sql: "insert into domain_tag (element_kind, element_id, text) values (?, ?, ?)", arguments: [kind.rawValue, id, trimmed])
        }
    }

    public func untag(_ kind: ElementKind, _ id: String, _ text: String) throws {
        try db.writer.write { db in
            try db.execute(sql: "delete from domain_tag where element_kind = ? and element_id = ? and lower(text) = ?",
                           arguments: [kind.rawValue, id, PeopleRepository.normalize(text)])
        }
    }

    public func tags(of kind: ElementKind, _ id: String) throws -> [String] {
        try db.writer.read { try String.fetchAll($0, sql: "select text from domain_tag where element_kind = ? and element_id = ? order by text collate nocase",
                                                 arguments: [kind.rawValue, id]) }
    }

    /// Every tag in use, one spelling each, for the filter menu.
    public func all() throws -> [String] {
        try db.writer.read { try String.fetchAll($0, sql: "select min(text) from domain_tag group by lower(text) order by lower(text)") }
    }

    /// The ids of one kind of element that carry this tag.
    public func elements(_ kind: ElementKind, tagged text: String) throws -> Set<String> {
        try db.writer.read { db in
            Set(try String.fetchAll(db, sql: "select element_id from domain_tag where element_kind = ? and lower(text) = ?",
                                    arguments: [kind.rawValue, PeopleRepository.normalize(text)]))
        }
    }
}
