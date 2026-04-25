# /gevent regression tests

WS-10 harness verifying every PRD finding for `/gevent` survives in code/prose.

## Run

```
bash plugins/gevent/tests/run.sh
```

Exit 0 = all PASS. Exit 1 = at least one FAIL (assertion details printed).

## Coverage map (PRD §3)

| Finding | Severity | Closed by | Test ID |
|---|---|---|---|
| PLG-gevent-H1 — Auth classifier | HIGH | WS-4 task 1 | WS4-H1 |
| PLG-gevent-H2 — Conflict math | HIGH | WS-4 task 2 | WS4-H2 |
| PLG-gevent-H3 — Cancel sendUpdates | HIGH | WS-4 task 3 | WS4-H3 |
| PLG-gevent-H4 — Homoglyph zero-match upsert | HIGH | WS-3 task 5 | WS3-H4 |
| PLG-gevent-M1 — notes_bot_decided type-lax | MED | WS-7 task 1 | WS7-M1 |
| PLG-gevent-M2 — Shadow-check scope | MED | WS-7 task 2 | WS7-M2 |
| PLG-gevent-M3 — Read-path tempfile | MED | WS-7 task 3 | WS7-M3 |
| PLG-gevent-M4 — calendarId validation | MED | WS-7 task 4 | WS7-M4 |
| PLG-gevent-M5 — Stale-read window | MED | WS-7 task 8 | WS7-M5 |
| PLG-gevent-M6 — Unknown-key preservation | MED | WS-7 task 7 | WS7-M6 |
| PLG-gevent-M7 — Intent-precedence | MED | WS-7 task 5 | WS7-M7 |
| PLG-gevent-M8 — DST handling | MED | WS-7 task 6 | WS7-M8 |
| PLG-gevent-M9 — Conflict-list cap | MED | WS-4 task 4 | WS4-M9 |
| PLG-gevent-M10 — events patch worked example | MED | WS-4 task 4 | WS4-M10 |
| PLG-gevent-L1 — requestId precision | LOW | WS-7 task 9 | WS7-L1 |
| PLG-gevent-L2 — Notes-bot self-email | LOW | WS-7 task 9 | WS7-L2 |
| PLG-gevent-L3 — always_include[].tag strip | LOW | WS-7 task 9 | WS7-L3 |
| PLG-gevent-L4 — Duplicate Request ID section | LOW | WS-7 task 9 | WS7-L4 |
| PLG-gevent-L5 — Banner emoji unification | LOW | WS-7 task 9 | WS7-L5+L16 |
| PLG-gevent-L6 — Config schema load checks | LOW | WS-7 task 9 | WS7-L6 |
| PLG-gevent-L7 — Title prompt-injection | LOW | WS-7 task 9 | WS7-L7 |
| PLG-gevent-L8 — Contacts symlink + size cap | LOW | WS-7 task 9 | WS7-L8 |
| PLG-gevent-L9 — Case-insensitive FS hazard | LOW | WS-7 task 9 | WS7-L9 |
| PLG-gevent-L10 — --auto non-create verb | LOW | WS-7 task 9 | WS7-L10 |
| PLG-gevent-L11 — Alias-collision banner | LOW | WS-7 task 9 | WS7-L11 |
| PLG-gevent-L12 — Calendar-switch registry | LOW | WS-7 task 9 | WS7-L12 |
| PLG-gevent-L13 — teammates[].active gate | LOW | WS-7 task 9 | WS7-L13 |
| PLG-gevent-L14 — trusted_domains[] in schema | LOW | WS-7 task 9 | WS7-L14 |
| PLG-gevent-L15 — Version mapping policy | LOW | WS-7 task 9 | WS7-L15 |
| PLG-gevent-L16 — Legacy-shadow text dedup | LOW | WS-7 task 9 | WS7-L16 |
| PLG-gevent-L17 — $ARGUMENTS expansion note | LOW | WS-7 task 9 | WS7-L17 |
| PLG-gevent-L18 — Cancel confirmation count | LOW | WS-7 task 9 | WS7-L18 |
| PLG-gevent-L19 — scripts/preflight.py mechanical | LOW | WS-7 task 10 | WS7-L19 |

33 PRD findings → 34 assertions (L-19 = 2 anchors: SKILL invocation + Python validity).

## What tests do NOT cover

- Live Google Calendar traffic.
- Interactive AskUserQuestion flow.
- Behavior of the actual Google `events list` / `events insert` / `events patch`
  CLI on production data.

These are explicitly out of scope per WS-10 acceptance ("verification only").
