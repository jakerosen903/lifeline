Invented transcripts for tests and the CLI. No real person's data. Format: see TranscriptImport.swift.

transcript-v8-*.json are the PC-d test stories for person handles. Each also has the key
"expected_people": one list of said names per person in the story. Only the tests read it
(HandleTally.expectedPeople); the import ignores it. See docs/experiments/2026-11-19-extractor-v8-handles.md.
