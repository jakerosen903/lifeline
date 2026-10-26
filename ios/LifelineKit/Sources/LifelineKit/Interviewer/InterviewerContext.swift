/// The only code that puts a person's words into the interviewer call. It sees this session's
/// segments only, never earlier sessions, and never a segment of a memory excluded from AI.
public enum InterviewerContext {
    /// - Parameters:
    ///   - session: the session being recorded. Segments and turns of any other session are left out.
    ///   - segments: closed segments in any order; they are sorted newest first here (by `index`).
    ///   - excluded: segments to leave out (`MemoryRepository.excludedSegmentIDs(in:)`).
    ///   - turns: what the app has spoken, in any order. The request keeps the last three by `startMs`, oldest first.
    ///   - tokenBudget: characters ÷ 4, counted over the segments' text only. The opening and the turns are small and always sent.
    /// The newest usable segment is always sent, even when it alone is over the budget. Older segments are
    /// added while the running total stays at or under the budget; the first one that would pass it ends the list.
    public static func build(session: SessionID, segments: [Segment], excluded: Set<SegmentID>, opening: String, stage: Stage,
                             turns: [InterviewerTurn], tokenBudget: Int = 1500) -> InterviewerRequest {
        let usable = segments.filter { $0.sessionID == session && !excluded.contains($0.id) }.sorted { $0.index > $1.index }

        var texts: [String] = []
        var characters = 0
        for segment in usable {
            if !texts.isEmpty && characters + segment.text.count > tokenBudget * 4 { break }
            texts.append(segment.text)
            characters += segment.text.count
        }
        let recent = turns.filter { $0.sessionID == session }.sorted { $0.startMs < $1.startMs }.suffix(3).map(\.text)
        return InterviewerRequest(segments: texts, opening: opening, stage: stage, recentTurns: Array(recent), newestSegment: usable.first?.id)
    }
}
