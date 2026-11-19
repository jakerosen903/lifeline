import Foundation

/// Pure: turns a memory's handles into the people they name (PC-d). The card stores those people
/// (`handlePeople`) for Keep, and their said names as `peopleRefs`, so the rest of the app keeps
/// reading said names. A person id the packet of this call did not hold is cleared: the model may
/// only point at people it was shown.
public enum HandleResolve {
    /// For each memory with handles: `handlePeople` = the people of its handles, with a person id kept only when `knownPeople` holds it;
    /// `peopleRefs` = their said names, in handle order. A memory with no handle is not changed.
    /// `recording` is the packet's `recordingPeople`: a handle with no entry in this output takes the recording's entry (D17).
    public static func resolved(_ output: OutputValidator.Validated, knownPeople: Set<String>,
                                recording: [ContextPacket.RecordingPerson] = []) -> OutputValidator.Validated {
        guard !output.people.isEmpty || !recording.isEmpty else { return output }
        var out = output
        out.people = output.people.map { checked($0, knownPeople) }
        // The validator keeps the first entry of each handle, so a handle names one person.
        // This output's own entry wins over the recording's: the name was said again (D17 rule 4).
        let own = Dictionary(out.people.map { ($0.handle, $0) }, uniquingKeysWith: { first, _ in first })
        let earlier = Dictionary(recording.compactMap { entry in person(of: entry).map { (entry.handle, checked($0, knownPeople)) } },
                                 uniquingKeysWith: { first, _ in first })
        let byHandle = own.merging(earlier, uniquingKeysWith: { own, _ in own })
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

    /// The recording's entry as a person of this card: the first name said for the handle, so the chip shows
    /// what the owner said earlier in this recording. Nil with no said name: there is nothing to show.
    private static func person(of entry: ContextPacket.RecordingPerson) -> PersonOut? {
        entry.saidNames.first.map { PersonOut(handle: entry.handle, saidName: $0, relationText: entry.relation, personID: entry.personID) }
    }

    private static func checked(_ person: PersonOut, _ knownPeople: Set<String>) -> PersonOut {
        guard let id = person.personID, !knownPeople.contains(id) else { return person }
        var out = person
        out.personID = nil
        return out
    }
}
