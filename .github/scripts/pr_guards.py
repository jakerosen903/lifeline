#!/usr/bin/env python3
"""
Deterministic PR guards for Lifeline. These run in CI before the Claude review
so the things that can lose a person's data are caught by code, not judgement.

  1. Migration guard  — a shipped `registerMigration("vN")` block in
                        Store/Migrations.swift must not change. The phone has
                        already run it.
  2. Migration lint   — a new block is named v(N+1) and appended last; a
                        destructive statement (drop, rename, DELETE) needs the
                        phrase "destructive migration approved" in the PR body;
                        a new migration needs a change to MigrationsTests.swift.
  3. Schema guard     — a new or changed stored column in a Domain/ row type
                        (a `CodingKeys` case) needs a new migration in the same
                        PR, unless the PR body says "no migration needed".
  4. Posture guard    — no new network host other than api.anthropic.com in
                        LifelineKit sources, and no UserDefaults write of a key
                        or transcript. The PR body phrase "new endpoint approved"
                        overrides the host check.
  5. Fixture guard    — no real-looking phone number or email in tests or
                        fixtures. Only 555 numbers and *.test / *.invalid /
                        example.* addresses are allowed.
  6. Secret guard     — no Anthropic API key (sk-ant-...) or device identifier
                        in the diff.

Usage: pr_guards.py <base_ref>
PR body is read from the PR_BODY environment variable.
Exit 1 with a readable report if anything fails.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(
    subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True).stdout.strip()
)
KIT = "ios/LifelineKit"
MIGRATIONS = f"{KIT}/Sources/LifelineKit/Store/Migrations.swift"
MIGRATION_TESTS = f"{KIT}/Tests/LifelineKitTests/MigrationsTests.swift"
DOMAIN = f"{KIT}/Sources/LifelineKit/Domain/"
SOURCES = f"{KIT}/Sources/"
TESTS = (f"{KIT}/Tests/", f"{KIT}/Fixtures/", "ios/LifelineUITests/")


def sh(*args: str, ok_fail: bool = False) -> str:
    r = subprocess.run(args, capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0 and not ok_fail:
        raise SystemExit(f"command failed: {' '.join(args)}\n{r.stderr}")
    return r.stdout


def changed_files(base: str) -> list[str]:
    out = sh("git", "diff", "--name-only", "--diff-filter=ACMR", f"{base}...HEAD")
    return [l.strip() for l in out.splitlines() if l.strip()]


def file_at(ref: str, path: str) -> str:
    return sh("git", "show", f"{ref}:{path}", ok_fail=True)


def diff_added_lines(base: str, *paths: str) -> list[tuple[str, int, str]]:
    """(path, line_no, text) for every added line in the PR diff."""
    cmd = ["git", "diff", "--unified=0", f"{base}...HEAD"]
    if paths:
        cmd += ["--", *paths]
    out = sh(*cmd)
    rows: list[tuple[str, int, str]] = []
    path, line = "", 0
    for raw in out.splitlines():
        if raw.startswith("+++ "):
            path = raw[4:].removeprefix("b/")
            continue
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)", raw)
        if m:
            line = int(m.group(1))
            continue
        if raw.startswith("+") and not raw.startswith("+++"):
            rows.append((path, line, raw[1:]))
            line += 1
    return rows


# ---------------------------------------------------------------- migrations

MIGRATION_START = re.compile(r'registerMigration\("(v\d+)"\)\s*\{')


def migration_blocks(src: str) -> list[tuple[str, str]]:
    """[(name, block_text)] for each registerMigration block, by brace matching."""
    blocks = []
    for m in MIGRATION_START.finditer(src):
        depth, i = 1, m.end()
        while i < len(src) and depth:
            depth += {"{": 1, "}": -1}.get(src[i], 0)
            i += 1
        blocks.append((m.group(1), src[m.start():i]))
    return blocks


def migration_guard(base: str, changed: list[str], pr_body: str) -> tuple[list[str], list[str]]:
    """Returns (problems, names of new migrations)."""
    problems: list[str] = []
    if MIGRATIONS not in changed:
        return problems, []
    old = migration_blocks(file_at(base, MIGRATIONS))
    new = migration_blocks(file_at("HEAD", MIGRATIONS))
    old_names = [n for n, _ in old]
    new_names = [n for n, _ in new]

    # 1. shipped blocks are byte-identical and in the same order
    for i, (name, text) in enumerate(old):
        if i >= len(new) or new[i][0] != name:
            problems.append(f"{MIGRATIONS}: shipped migration {name} is removed or moved. Never edit a shipped migration.")
            continue
        if new[i][1] != text:
            problems.append(f"{MIGRATIONS}: shipped migration {name} is edited. Append a new block instead; the phone has already run {name}.")

    added = [n for n in new_names if n not in old_names]
    # 2. numbering and position
    expected = int(old_names[-1][1:]) + 1 if old_names else 1
    for name in added:
        if int(name[1:]) != expected:
            problems.append(f"{MIGRATIONS}: new migration is {name}; expected v{expected} (last shipped is {old_names[-1] if old_names else 'none'}).")
        expected += 1
        if new_names.index(name) < len(old_names):
            problems.append(f"{MIGRATIONS}: migration {name} is inserted before a shipped block. New blocks go last.")

    # 3. destructive statements and an upgrade test
    if added:
        new_text = "\n".join(t for n, t in new if n in added)
        destructive = re.findall(r"\b(drop\(|rename\(|DELETE FROM|DROP TABLE|DROP COLUMN|ALTER TABLE \S+ DROP)", new_text, re.I)
        if destructive and "destructive migration approved" not in pr_body.lower():
            problems.append(
                f"{MIGRATIONS}: {', '.join(added)} has a destructive statement ({', '.join(sorted(set(destructive)))}). "
                "Back up the phone's database, then put 'destructive migration approved' in the PR body."
            )
        if MIGRATION_TESTS not in changed:
            problems.append(
                f"{MIGRATION_TESTS}: {', '.join(added)} has no test change. Add a test that migrates upTo: the previous "
                "version, inserts rows, migrates to the new version, and checks the rows."
            )
    return problems, added


CODING_KEY = re.compile(r'^\s*case\s+\w+(\s*=\s*"[a-z_]+")?\s*(,\s*\w+(\s*=\s*"[a-z_]+")?\s*)*$')


def schema_guard(base: str, changed: list[str], new_migrations: list[str], pr_body: str) -> list[str]:
    problems = []
    if new_migrations or "no migration needed" in pr_body.lower():
        return problems
    hits = []
    for path, no, text in diff_added_lines(base, DOMAIN):
        if not path.startswith(DOMAIN):
            continue
        if 'enum CodingKeys' in text or (CODING_KEY.match(text) and '= "' in text):
            hits.append(f"{path}:{no}: {text.strip()[:100]}")
    if hits:
        problems.append(
            "A Domain/ row type adds or changes a stored column but the PR adds no migration:\n"
            + "\n".join(f"    {h}" for h in hits[:8])
            + "\n  Add registerMigration(\"vN\") in Store/Migrations.swift, or put 'no migration needed' in the PR body and say why."
        )
    return problems


# ---------------------------------------------------------------- data posture

HOST = re.compile(r'https?://([A-Za-z0-9.-]+)')
ALLOWED_HOSTS = {"api.anthropic.com"}
DEFAULTS_WRITE = re.compile(r'UserDefaults[^\n]*\.set\(')


def posture_guard(lines: list[tuple[str, int, str]], pr_body: str) -> list[str]:
    problems = []
    for path, no, text in lines:
        if not path.startswith(SOURCES) or path.endswith(".md"):
            continue
        if "//" in text and text.strip().startswith("//"):
            continue
        for m in HOST.finditer(text):
            host = m.group(1)
            if host in ALLOWED_HOSTS or host.endswith((".apple.com", "example.com", "w3.org", "github.com")):
                continue
            if "new endpoint approved" in pr_body.lower():
                continue
            problems.append(
                f"{path}:{no}: new network host {host!r}. V1 sends data only to api.anthropic.com. "
                "Remove it, or add a DECISIONS.md entry and 'new endpoint approved' to the PR body."
            )
        if DEFAULTS_WRITE.search(text) and re.search(r"key|token|transcript|segment|text", text, re.I):
            problems.append(f"{path}:{no}: UserDefaults write that looks like a key or transcript. Keys go in SecretStore; content goes in the store.")
    return problems


# ---------------------------------------------------------------- fixtures and secrets

PHONE = re.compile(r"(?<![\d.])(?:\+?1[\s.-]?)?\(?([2-9]\d{2})\)?[\s.-]?(\d{3})[\s.-]?(\d{4})(?![\d.])")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
EMAIL_OK = re.compile(r"(\.test|\.invalid|\.example|\.localhost)$|^example\.(com|org|net)$", re.I)


def fixture_guard(lines: list[tuple[str, int, str]]) -> list[str]:
    problems = []
    for path, no, text in lines:
        if not path.startswith(TESTS):
            continue
        if path.endswith((".png", ".jpg", ".m4a", ".wav", ".caf")):
            continue
        for m in PHONE.finditer(text):
            if m.group(1) == "555" or m.group(2) == "555":
                continue
            # millisecond-style numbers in tests (startMs: 1200, 3000) are not phones; require a separator
            if not re.search(r"[\s.()-]", m.group(0).strip()):
                continue
            problems.append(f"{path}:{no}: real-looking phone number {m.group(0).strip()!r}. Use a 555 number.")
        for m in EMAIL.finditer(text):
            if not EMAIL_OK.search(m.group(1)):
                problems.append(f"{path}:{no}: real-looking email {m.group(0)!r}. Use @test.invalid.")
    return problems


SECRET = re.compile(r"\b(sk-ant-[A-Za-z0-9_-]{20,}|0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16})\b")


def secret_guard(lines: list[tuple[str, int, str]]) -> list[str]:
    problems = []
    for path, no, text in lines:
        if "fake" in text.lower() or "example" in text.lower():
            continue
        for m in SECRET.finditer(text):
            what = "Anthropic API key" if m.group(0).startswith("sk-ant-") else "device identifier"
            problems.append(f"{path}:{no}: looks like a {what} ({m.group(0)[:12]}…). Remove it; if it is a key, rotate it.")
    return problems


# ---------------------------------------------------------------- main

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    base = sys.argv[1]
    pr_body = os.environ.get("PR_BODY", "") or ""

    # Compare against the merge-base so an older base branch tip does not read as a change.
    base = sh("git", "merge-base", base, "HEAD").strip()
    changed = changed_files(base)
    lines = diff_added_lines(base)

    migration_problems, new_migrations = migration_guard(base, changed, pr_body)
    report: dict[str, list[str]] = {
        "Migration guard (shipped blocks unchanged, numbering, destructive, upgrade test)": migration_problems,
        "Schema guard (Domain/ column ⇒ migration)": schema_guard(base, changed, new_migrations, pr_body),
        "Posture guard (hosts, UserDefaults)": posture_guard(lines, pr_body),
        "Fixture guard (no real phones/emails)": fixture_guard(lines),
        "Secret guard (API keys, device IDs)": secret_guard(lines),
    }
    failed = False
    for name, probs in report.items():
        if probs:
            failed = True
            print(f"✗ {name}")
            for p in probs:
                print(f"  - {p}")
        else:
            print(f"✓ {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
