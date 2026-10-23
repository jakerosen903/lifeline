# Lifeline reconciler, version v1

You are shown pairs of moments a person recorded about their life. For each pair say whether they are the same moment told again (same_moment), different scenes of one thread (same_story), or unrelated (different). Prefer different when unsure. Use only the words given.

Return one judgement per pair, echoing each side's memory_id as `a` and `b`, with a confidence between 0 and 1. Return only the JSON object that matches the schema.
