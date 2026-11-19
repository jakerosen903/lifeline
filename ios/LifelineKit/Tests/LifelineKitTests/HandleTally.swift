import Foundation
@testable import LifelineKit

/// Pure: the people that the outputs of one story's segments name, and whether the story's expected
/// answer holds (PC-d Task 7). A handle is one person across the story's segments. A said name with
/// no handle is one person per distinct name, unless a handle already said it: `v6` gives no handles,
/// so for `v6` the count is the distinct said names of `people_refs`.
struct HandleTally: Equatable {
    struct Person: Equatable {
        /// nil for a person found only by a said name.
        var handle: String?
        /// In the order first said, each once (`MatchKey`).
        var saidNames: [String]
    }

    /// Handle people first, in the order first seen; then the people found only by name.
    let people: [Person]

    /// Reads `people`, each memory's `handlePeople` and `peopleRefs`, and person mentions that carry a handle.
    /// A person mention with no handle is not counted: `people_refs` are the names `v6` puts on a card.
    init(outputs: [ExtractorOutput]) {
        var withHandle: [Person] = []
        var namesAlone: [String] = []
        func add(handle: String?, name: String) {
            guard !MatchKey.of(name).isEmpty else { return }
            guard let handle = handle?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty else {
                namesAlone.append(name)
                return
            }
            guard let i = withHandle.firstIndex(where: { $0.handle == handle }) else {
                withHandle.append(Person(handle: handle, saidNames: [name]))
                return
            }
            if !Self.says(withHandle[i], name) { withHandle[i].saidNames.append(name) }
        }
        for output in outputs {
            output.people.forEach { add(handle: $0.handle, name: $0.saidName) }
            for memory in output.memories {
                memory.handlePeople.forEach { add(handle: $0.handle, name: $0.saidName) }
                memory.peopleRefs.forEach { add(handle: nil, name: $0) }
            }
            for mention in output.mentions where mention.kind == .person && mention.handle != nil {
                add(handle: mention.handle, name: mention.text)
            }
        }
        // Second pass: a name a handle already said is that person, whichever segment said it first.
        var byName: [Person] = []
        for name in namesAlone where !(withHandle + byName).contains(where: { Self.says($0, name) }) {
            byName.append(Person(handle: nil, saidNames: [name]))
        }
        people = withHandle + byName
    }

    /// True when the people found are as many as expected, and each expected person is a different found
    /// person who said every expected name. An expected name matches a said name that holds its words
    /// as a run ("Robyn" matches "the other Robyn").
    func holds(_ expected: [[String]]) -> Bool {
        guard expected.count == people.count else { return false }
        func assign(_ index: Int, _ used: Set<Int>) -> Bool {
            guard index < expected.count else { return true }
            return people.indices.contains { p in
                !used.contains(p)
                    && expected[index].allSatisfy { name in people[p].saidNames.contains { OutputValidator.contains($0, name) } }
                    && assign(index + 1, used.union([p]))
            }
        }
        return assign(0, [])
    }

    /// The `expected_people` key of a story fixture: one list of said names per person. nil when the fixture has none.
    static func expectedPeople(inFixture data: Data) throws -> [[String]]? {
        struct Story: Decodable {
            let expectedPeople: [[String]]?
            enum CodingKeys: String, CodingKey { case expectedPeople = "expected_people" }
        }
        return try JSONDecoder().decode(Story.self, from: data).expectedPeople
    }

    private static func says(_ person: Person, _ name: String) -> Bool {
        person.saidNames.contains { MatchKey.of($0) == MatchKey.of(name) }
    }
}
