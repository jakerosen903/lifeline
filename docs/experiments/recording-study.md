# Recording study: does extraction work on real speech?

The first task before any app code. One weekend. Answers: how often extraction is wrong, what it misses, and which relative questions actually pin memories down.

## Goal

Calibrate the extractor prompt, the resolver, and the interviewer's follow-ups against real, rambling, undated storytelling.

## Participants

Five to eight people who agree to be recorded for this purpose. Include at least one older relative and at least one person who tends to summarize rather than tell scenes. Tell each person: the recording is for building the app, it stays with you, and they can ask for it to be deleted at any time.

## Procedure

1. Use a voice memo app. One speaker. Ten minutes.
2. Open with exactly one prompt: "Tell me about the house you grew up in." Then listen. Use only acknowledgements and reflections ("the pomegranate tree"). Ask at most one question, and only after a long pause. Note the time of any question.
3. At ten minutes, wind down: "Let's leave it there." Ask: "Did I miss anything?" and note what they add.
4. Transcribe (any STT; keep timestamps).
5. Run the extractor prompt (v0 in this folder once written) over the transcript in 60-second segments and over the whole transcript. Save both outputs.
6. By hand, mark every candidate event as: correct, partly correct, invented detail, missed entirely. Mark every time anchor as: exact, relative to a named event, relative to an unnamed event, none.
7. For each memory without a date, write the one relative question that would place it ("before or after Maya was born?"). Note whether the answer exists elsewhere in the transcript.

## What to record per participant

| Field | Value |
| --- | --- |
| Minutes of speech | |
| Candidate events (segmented / whole) | |
| Correct / partly / invented / missed | |
| Anchors: exact / relative-named / relative-unnamed / none | |
| Questions the interviewer asked | |
| Longest silence that was followed by more story | |
| What they added after "did I miss anything?" | |

## Questions this must answer

- Does segmenting at 60 s lose context that the whole transcript keeps? (Decides extractor batching.)
- How often does the extractor invent a detail? (Decides how conservative the prompt and the UI must be.)
- What fraction of memories have a usable relative anchor? (Decides how much the resolver matters.)
- How long are natural pauses mid-thought? (Calibrates the end-of-thought check.)
- Did the one allowed question help or interrupt? (Tests principle 3.)

## Output

A short write-up in this folder: numbers per participant, the extractor prompt v1, a list of resolver question patterns that worked, and the pause-length distribution. Transcripts stay out of the repo unless the participant consents to a redacted fixture.
