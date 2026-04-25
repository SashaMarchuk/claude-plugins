# /ultra regression tests

WS-10 harness verifying every PRD finding for `/ultra` survives in code/prose.

## Run

```
bash plugins/ultra/tests/run.sh
```

Exit 0 = all PASS. Exit 1 = at least one FAIL (assertion details printed).

## Coverage map (PRD §3)

| Finding | Severity | Closed by | Test ID |
|---|---|---|---|
| PLG-ultra-CRIT1 — Wrapped-skill output ingest | CRIT | WS-1 task 1+2 | WS1-CRIT1 (2 assertions) |
| PLG-ultra-CRIT2 — --xl cost pre-flight | CRIT | WS-1 task 3+4 | WS1-CRIT2 (2 assertions) |
| PLG-ultra-CRIT3 — Lessons symlink defense | CRIT | WS-5 task 2 | WS5-CRIT3 (2 assertions) |
| PLG-ultra-HIGH1 — Phase 2 isolation | HIGH | gap-noted | WS-gap-HIGH1 |
| PLG-ultra-HIGH2 — Tier-config minimum vs roster | HIGH | gap-noted | WS-gap-HIGH2 |
| PLG-ultra-HIGH3 — --resume missing state | HIGH | partial (SKILL guard) | WS-gap-HIGH3 |
| PLG-ultra-HIGH4 — State-tree race | HIGH | WS-5 tasks 3, 4 | WS5-HIGH4 (2 assertions) |
| PLG-ultra-HIGH5 — XL C1 double-spawn | HIGH | gap-noted | WS-gap-HIGH5 |
| PLG-ultra-HIGH6 — Parent-agent bypass | HIGH | WS-1 task 5 | WS1-HIGH6 |
| PLG-ultra-HIGH7 — Lessons paths drift | HIGH | WS-5 task 1 | WS5-HIGH7 (2 assertions) |
| PLG-ultra-MED1..MED12 | MED | WS-8 tasks 1..12 | WS8-MED1..MED12 |
| PLG-ultra-LOW1..LOW7 | LOW | WS-8 task 13 | WS8-LOW1..LOW7 |

29 PRD findings → 34 assertions (CRIT1, CRIT2, CRIT3, HIGH4, HIGH7 have 2 anchors each).

## Coverage gaps (honest disclosure)

The following findings are NOT closed by any of WS-1..WS-9 in the source plugin
files. Their tests are marked `WS-gap-*` and verify what evidence IS present
(or document the gap honestly). They MUST be re-evaluated when (if) follow-up
workstreams close them:

- **HIGH-1** — Phase 2 isolation is currently prose ("trusted vs untrusted
  prose") only; no mechanical isolation primitive (e.g. separate context window,
  schema-validated boundary).
- **HIGH-2** — `tier-config.md:103` still pins `xl:15` as the tier minimum
  while the actual XL roster sums to ~23 named roles. Drift documented.
- **HIGH-3** — `--resume` requires `--task=<name>` and warns on missing state,
  but no loud-fail / refuse-without-confirm spec exists.
- **HIGH-5** — XL C1 contrarian fires twice (standing + consensus-trap) but
  the distinct-tag mechanism for cross-agent independence is not specified.

These are acknowledged in the PRD §3 backlog and unblocked for follow-up.

## What tests do NOT cover

- Live multi-agent spawn (no real Claude Code Agent tool calls).
- Concurrent /ultra runs in parallel terminals.
- Wrapped-skill execution.

These are explicitly out of scope per WS-10 acceptance ("verification only").
