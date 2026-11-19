# Extractor v8 against v6: people handles

Plan PC-d, Task 7. This comparison is the gate for Task 8. The default prompt stays `v6` until the owner reads the table below and says yes.

## What the comparison measures

The comparison runs invented stories through the real model with prompt `v6` and prompt `v8`. It measures one question: does the extractor tell people apart across the segments of one recording?

- `v8` gives each person a handle ("p1"). One handle is one person in one recording.
- `v6` gives no handles. Its prompt tells the model to return `people` empty. For `v6`, the count of people is the number of distinct said names in `people_refs` across the story.

The comparison also runs the three older fixtures (garden, road trip, school). For these, it counts memories and mentions. The owner uses these counts to see whether `v8` lost anything that `v6` found.

## How it runs

- The test is `v6AgainstV8OnPeopleHandles` in `ios/LifelineKit/Tests/LifelineKitTests/ExtractorIntegrationTests.swift`.
- The test runs only when `ANTHROPIC_API_KEY` is set. Without the key, the test is skipped.
- Each run imports one fixture into an in-memory store. The real `ExtractionQueue` extracts the segments in order with the real `AnthropicExtractionService`. So each later segment gets the earlier segments' text and the recording's people (`recordingPeople`) from the stored cards, as on the device.
- The model and effort are the defaults in `ExtractorConfig` (`claude-opus-5-5`, effort `low`). Only the prompt version changes.
- Each fixture runs through each version three times.
- `HandleTally` (in the test target) counts the people of each run from the stored cards. It also checks the story's expected answer.

The test asserts two things for every version and every run:

1. No shown field holds text that is not in the transcript. A said name of a person can come from an earlier segment of the same recording (ruling D17). So the test checks said names against the recording so far.
2. Every handle of a memory names a person in that output's `people` or in the recording so far (ruling D17).

The test does not assert the expected answer. The table reports it in the "Pass" column.

## The four stories

Each story is invented and told in the first person. Each has three segments, so a handle must hold across segments. Each fixture holds its expected answer in the key `expected_people`: one list of said names for each person.

| Story | Fixture | What it tests | Expected answer |
|---|---|---|---|
| Two people with one name | `transcript-v8-two-robyns.json` | "Robyn from work" and "the other Robyn my cousin". The third segment says "she" about the cousin. | 2 people: "Robyn" and "Robyn" |
| One person under two names | `transcript-v8-two-names.json` | "my brother Anselm", then "everybody called him Sully". | 1 person: "Anselm" and "Sully" |
| A name with no other words | `transcript-v8-name-alone.json` | The second segment is the one word "Ottilie". The third segment says "she" only. | 1 person: "Ottilie" |
| A known name with a new relation phrase | `transcript-v8-new-relation.json` | "my neighbor Hollis", then "Hollis became my business partner", then "Hollis my partner". | 1 person: "Hollis" |

How the check reads the expected answer:

- The number of people found must equal the number expected.
- Each expected person must be a different person found, who said every expected name. An expected name matches a said name that holds its words ("Robyn" matches "the other Robyn").

What we expect before the run:

- We expect `v6` to fail the two-Robyns story. It has no handles, so two people with one name read as one person. This failure is the reason for `v8`.
- We expect `v6` to fail the two-names story for the same reason: two names read as two people.
- In the name-alone story, a person with no memory card in the second segment does not reach `recordingPeople`. The queue builds `recordingPeople` from stored memory cards only. A miss there for `v8` points at the app, not only at the prompt.
- The new-relation story checks that `v8` does not give a new handle for a new relation phrase. `v6` can pass it, because the said name does not change.

## The command

Run this one line from `ios/LifelineKit`. Replace the placeholder with your key. Never commit the key.

```
ANTHROPIC_API_KEY=your-key-here swift test --filter v6AgainstV8OnPeopleHandles
```

- The test prints the table at the end of the run.
- The test also writes the table as Markdown to `extractor-v8-handles.md` in the system temporary directory. The last line of the output gives the full path. Paste that table into "Results" below.
- The log lines that start with `[integration]` show each card the model gave. Use them to explain each miss.

Cost and time:

- The run makes about 140 model calls: 23 segments × 2 versions × 3 runs. A blank answer or a transient error adds a call.
- The calls run one after the other. Expect the run to take tens of minutes.

## Table columns

| Column | Meaning |
|---|---|
| Story | The fixture name without `transcript-`. |
| Version | `v6` or `v8`. |
| Run | 1, 2 or 3. |
| People found | The number of people `HandleTally` counts. |
| People | Each person found: the handle (`v8` only), then the said names. |
| Expected | The number of people expected. "—" for an older fixture. |
| Pass | "yes" when the expected answer holds, "no" when it does not. "—" for an older fixture. |
| Memories | Memory cards kept by the pass: pending, accepted or superseded. Rejected and withheld rows do not count. |
| Mentions | Mention rows kept by the pass (people, places, things and ideas). |
| Segments not extracted | Segments that failed. This must be 0. |

## Results

Not run yet: no key in the build environment.

When the owner runs the command, add here:

1. The table.
2. Each miss in plain words: the story, the version, the run, and what the model did.
3. For the three older fixtures: whether `v8` found fewer memories or mentions than `v6`.
