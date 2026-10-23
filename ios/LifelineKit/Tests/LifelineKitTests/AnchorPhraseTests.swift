import Foundation
import Testing
@testable import LifelineKit

private struct Case: Decodable {
    struct Expect: Decodable {
        let earliest: String?, latest: String?, granularity: String?, origin: String?
        let age: Age?
        struct Age: Decodable { let years: [Int]?; let approximate: [Int]?; let grade: Int? }
    }
    let phrase: String, value: String?, relation: String, expect: Expect?
}

private func cases() throws -> [Case] {
    let url = try #require(Bundle.module.url(forResource: "resolver-cases", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode([Case].self, from: try Data(contentsOf: url))
}

@Test func everyFixtureRowParsesAsExpected() throws {
    let rows = try cases()
    #expect(rows.count >= 30)
    for row in rows {
        if row.relation == "age" {
            let got = AnchorPhrase.parseAge(row.phrase, value: row.value)
            guard let age = row.expect?.age else { #expect(got == nil, Comment(rawValue: row.phrase)); continue }
            let want: AgeSpan? = age.years.map { .years(from: $0[0], to: $0[1]) }
                ?? age.approximate.map { .approximate(center: $0[0], slack: $0[1]) }
                ?? age.grade.map { .grade($0) }
            #expect(got == want, Comment(rawValue: "\(row.phrase): got \(String(describing: got))"))
        } else {
            let got = AnchorPhrase.parseAbsolute(row.phrase, value: row.value)
            guard let e = row.expect else { #expect(got == nil, Comment(rawValue: row.phrase)); continue }
            #expect(got?.earliest?.iso == e.earliest && got?.latest?.iso == e.latest && got?.granularity?.rawValue == e.granularity,
                    Comment(rawValue: "\(row.phrase): got \(String(describing: got))"))
            #expect(got?.origin.map(\.rawValue) == (e.origin ?? "stated") && got?.evidenceText == row.phrase, Comment(rawValue: row.phrase))
        }
    }
}

@Test func unknownPhrasesReturnNil() {
    for phrase in ["the summer after graduation", "before Maya was born", "a long time ago", ""] {
        #expect(AnchorPhrase.parseAbsolute(phrase, value: nil) == nil, Comment(rawValue: phrase))
        #expect(AnchorPhrase.parseAge(phrase, value: nil) == nil, Comment(rawValue: phrase))
    }
}
