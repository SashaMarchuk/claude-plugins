# /clickup regression tests

WS-10 harness verifying every PRD finding for `/clickup` survives in code/prose.

## Run

```
bash plugins/clickup/tests/run.sh
```

Exit 0 = all PASS. Exit 1 = at least one FAIL (assertion details printed).

## Coverage map (PRD §3)

| Finding | Severity | Closed by | Test ID in run.sh |
|---|---|---|---|
| PLG-clickup-1 — Lock-file path drift | CRIT | WS-3 task 1 | WS3-F1 (2 assertions) |
| PLG-clickup-2 — schemaVersion silent-downgrade | CRIT | WS-3 task 2 | WS3-F2 (2 assertions) |
| PLG-clickup-3 — IDNA punycode bypass | HIGH | WS-3 task 4 | WS3-F3 |
| PLG-clickup-4 — Homoglyph gate order | HIGH | WS-3 task 5 | WS3-F4 (2 assertions) |
| PLG-clickup-5 — `--onboard --auto` collision | MED | WS-6 task 10 | WS6-F5 |
| PLG-clickup-6 — (no F6 in PRD; explicitly noted) | n/a | n/a | WS-skip-F6 |
| PLG-clickup-7 — MCP auth probe unnamed | HIGH | WS-6 task 1 | WS6-F7 |
| PLG-clickup-8 — `@mention` sanitisation absent | HIGH | WS-6 task 2 | WS6-F8 |
| PLG-clickup-9 — Dup-detection metric unspecified | MED | WS-6 task 3 | WS6-F9 |
| PLG-clickup-10 — Memory-rule precedence | MED | WS-6 task 4 | WS6-F10 |
| PLG-clickup-11 — Cyrillic translit lossy | MED | WS-6 task 5 | WS6-F11 |
| PLG-clickup-12 — UUID format unvalidated | MED | WS-6 task 6 | WS6-F12 |
| PLG-clickup-13 — `teammates[].active` default | MED | WS-6 task 7 | WS6-F13 |
| PLG-clickup-14 — Seed-text size unbounded | LOW | WS-6 task 8 | WS6-F14 |
| PLG-clickup-15 — Stale-rule banner non-blocking | LOW | WS-6 task 9 | WS6-F15 |

15 PRD findings → 18 assertions (some findings warrant ≥2 anchors).

## Assertion style

Each test greps a load-bearing string from the SKILL.md / references that
WS-3 / WS-6 introduced. Tests do NOT execute the plugin or hit ClickUp; they
verify that the prose contracts established by the workstreams are still
present byte-for-byte.

## What tests do NOT cover

- Live MCP traffic (no auth, no network).
- Runtime AskUserQuestion behaviour (Claude-host concern, not greppable).
- Future schemaVersion 3 migration (deferred).

These are explicitly out of scope per WS-10 acceptance ("verification only,
not new fixes").
