import Foundation

/// Pure: turns a memory's handles into the people they name (PC-d). The card stores those people
/// (`handlePeople`) for Keep, and their said names as `peopleRefs`, so the rest of the app keeps
/// reading said names. A person id the packet of this call did not hold is cleared: the model may
/// only point at people it was shown.
public enum HandleResolve {
    /// For each memory with handles: `handlePeople` = the people of its handles, with a person id kept only when `knownPeople` holds it;
    /// `peopleRefs` = their said names, in handle order. A memory with no handle is not changed.
    public static func resolved(_ output: OutputValidator.Validated, knownPeople: Set<String>) -> OutputValidator.Validated {
        guard !output.people.isEmpty else { return output }
        var out = output
        out.people = output.people.map { checked($0, knownPeople) }
        // The validator keeps the first entry of each handle, so a handle names one person.
        let byHandle = Dictionary(out.people.map { ($0.handle, $0) }, uniquingKeysWith: { first, _ in first })
        out.accepted = output.accepted.map { candidate in
            guard case .memory(var memory) = candidate, !memory.personHandles.isEmpty else { return candidate }
            var seen: Set<String> = []
            // A handle listed twice in one memory is one person, so it gives one entry.
            memory.handlePeople = memory.personHandles.filter { seen.insert($0).inserted }.compactMap { byHandle[$0] }
            memory.peopleRefs = memory.handlePeople.map(\.saidName)
            return .memory(memory)
        }
        return out
    }

    private static func checked(_ person: PersonOut, _ knownPeople: Set<String>) -> PersonOut {
        guard let id = person.personID, !knownPeople.contains(id) else { return person }
        var out = person
        out.personID = nil
        return out
    }
}
