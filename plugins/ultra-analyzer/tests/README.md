# /ultra-analyzer regression tests

WS-10 coverage map for `/ultra-analyzer`. The test runner (`run.sh`) was
created in WS-2 (28 tests) and extended in WS-9 (now 68 PASS / 0 FAIL covering
all 20 PRD findings). This README documents the finding → test mapping so
WS-10's master runner can reference it.

## Run

```
bash plugins/ultra-analyzer/tests/run.sh
```

Exit 0 = all PASS. Exit 1 = at least one FAIL.

Baseline (post-WS-9): **68 PASS / 0 FAIL**.

## Coverage map (PRD §3 — 20 findings, all covered)

| Finding | Severity | Closed by | Test ID(s) in run.sh |
|---|---|---|---|
| PLG-ultra-analyzer-C1 — Gate FAIL advisory | CRIT | WS-2 tasks 3, 4 | AC3 + AC4 (`.current_step` enum + gate-consult) |
| PLG-ultra-analyzer-C2 — Counter invariant | CRIT | WS-2 task 1 | AC1 (8 assertions across init/claim/release/requeue) |
| PLG-ultra-analyzer-C3 — Cross-model validator | CRIT | WS-2 task 7 | AC7 (default-profile + per-tier separation) |
| PLG-ultra-analyzer-H1 — Symlink attack | HIGH | WS-9 | WS9-H1 (symlinked dir + file refused exit 5) |
| PLG-ultra-analyzer-H2 — jq injection | HIGH | WS-2 task 5 | AC5 (set + inc both reject) |
| PLG-ultra-analyzer-H3 — Run-name traversal | HIGH | WS-2 task 2 | AC2 (`../../tmp/evil` rejected exit 6) |
| PLG-ultra-analyzer-H4 — No timeout binary | HIGH | WS-9 | WS9-H4 (PATH-restricted launch exits 7) |
| PLG-ultra-analyzer-H5 — Forbidden-field alias | HIGH | WS-9 | WS9-H5 (validator + analyze-unit alias prose) |
| PLG-ultra-analyzer-H6 — SIGKILL orphan lock | HIGH | WS-9 | WS9-H6 (heal_orphan_lock removes >30s, leaves fresh) |
| PLG-ultra-analyzer-H7 — set-no-lock | HIGH | WS-2 task 6 | AC6 (concurrent inc+set preserves count) |
| PLG-ultra-analyzer-M1 — Topic filename injection | MED | WS-9 | WS9-M1 (basename_safe + delimiter prose) |
| PLG-ultra-analyzer-M2 — sqlite read-only filter | MED | WS-9 | WS9-M2 (sql_is_safe rejects 6 write/DDL patterns) |
| PLG-ultra-analyzer-M3 — Counter sum invariant in /health | MED | WS-9 | WS9-M3 (broken state correctly reports false) |
| PLG-ultra-analyzer-M4 — XL topic cap | MED | WS-9 | WS9-M4 (Cap-70 removed, profile-driven 70-120 band) |
| PLG-ultra-analyzer-M5 — Empty contradictions | MED | WS-9 | WS9-M5 (4 assertions: empty + None + honest no-contradiction + synthesize) |
| PLG-ultra-analyzer-M6 — Late-schema rescue determinism | MED | WS-9 | WS9-M6 (validator + connector + anti-LLM language check) |
| PLG-ultra-analyzer-M7 — Browser cookie strip | MED | WS-9 | WS9-M7 (3 functional assertions: cookie + JWT + storage redacted) |
| PLG-ultra-analyzer-L1 — Hook decorative | LOW | WS-9 | WS9-L1 (hardening doc + functional shell-meta reject) |
| PLG-ultra-analyzer-L2 — set -e omission | LOW | WS-9 | WS9-L2 (intentional comment present) |
| PLG-ultra-analyzer-L3 — Anchor cross-verify | LOW | WS-9 | WS9-L3 (validator documents Step 2a + fabricated example) |

20 PRD findings → 68 assertions (multiple anchors per finding for thoroughness).

## Why this runner is fundamentally different from the other plugins'

`/ultra-analyzer` ships actual shell binaries (`bin/state.sh`, `bin/claim.sh`,
`bin/release.sh`, `bin/requeue.sh`, `bin/launch-terminal.sh`). The runner
exercises them functionally — initialize fresh runs, claim/release topics,
attempt path traversal, force jq injection. The `/clickup`, `/gevent`, and
`/ultra` plugins are prose-as-contract; their runners verify SKILL.md /
references/ greps. /ultra-analyzer's runner does both.

## What tests do NOT cover

- Live MongoDB/SQLite/HTTP/browser connector traffic.
- Multi-process race tests beyond the 10x concurrent inc+set in AC6.
- `/ultra` gate verdicts (the analyzer pipeline calls `/ultra` for gates;
  those gates are tested by `/ultra`'s own harness, not here).

These are explicitly out of scope per WS-10 acceptance.
