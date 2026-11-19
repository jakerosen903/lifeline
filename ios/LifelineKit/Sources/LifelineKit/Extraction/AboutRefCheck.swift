import Foundation

/// `about_ref` says what a fact, feeling or goal is about. It must name something real: the
/// person (`self`), an id the packet gave the model, a mention in the same answer, or a handle of
/// the same answer's people or of the recording's other segments (v8, D17, D30). Anything
/// else is cleared and the memory is kept: a memory about nothing in particular is true, and a
/// link to the wrong page is not. The model is not asked again for this one field.
public enum AboutRefCheck {
    /// `recordingHandles`: the handles of the packet's `recordingPeople`.
    public static func cleared(_ validated: OutputValidator.Validated, knownIDs: Set<String>,
                               recordingHandles: Set<String> = []) -> OutputValidator.Validated {
        let refs = Set(validated.accepted.compactMap { candidate -> String? in
            if case .mention(let mention) = candidate { return mention.ref }
            return nil
        } + validated.people.map(\.handle)).union(recordingHandles)
        var out = validated
        out.accepted = validated.accepted.map { candidate in
            guard case .memory(var memory) = candidate, let about = memory.aboutRef?.trimmingCharacters(in: .whitespacesAndNewlines) else { return candidate }
            if about == "self" || knownIDs.contains(about) || refs.contains(about) { return candidate }
            memory.aboutRef = nil
            return .memory(memory)
        }
        return out
    }
}
