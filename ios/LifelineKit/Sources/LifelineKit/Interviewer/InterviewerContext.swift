/// The only code that puts a person's words into the interviewer call. It sees this session's
/// segments only, never earlier sessions, and never a segment of a memory excluded from AI.
public enum InterviewerContext {
    /// - Parameters:
    ///   - segments: closed segments, newest first.
    ///   - excluded: segments to leave out (`MemoryRepository.excludedSegmentIDs(in:)`).
    ///   - turns: what the app has spoken, in any order. The request keeps the last three by `startMs`, oldest first.
    ///   - tokenBudget: characters ÷ 4, counted over the segments' text only. The opening and the turns are small and always sent.
    /// The newest segment is always sent, even when it alone is over the budget. Older segments are
    /// added while the running total stays at or under the budget; the first one that would pass it ends the list.
    public static func build(segments: [Segment], excluded: Set<SegmentID>, opening: String, stage: Stage,
                             turns: [InterviewerTurn], tokenBudget: Int = 1500) -> InterviewerRequest {
        // The first segment names the session; a segment of any other session is left out.
        let session = segments.first?.sessionID
        let usable = segments.filter { $0.sessionID == session && !excluded.contains($0.id) }

        var texts: [String] = []
        var used = 0
        for segment in usable {
            let tokens = segment.text.count / 4
            if !texts.isEmpty && used + tokens > tokenBudget { break }
            texts.append(segment.text)
            used += tokens
        }
        let recent = turns.sorted { $0.startMs < $1.startMs }.suffix(3).map(\.text)
        return InterviewerRequest(segments: texts, opening: opening, stage: stage, recentTurns: Array(recent))
    }
}
