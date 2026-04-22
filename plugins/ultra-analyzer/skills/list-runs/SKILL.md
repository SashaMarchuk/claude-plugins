---
name: list-runs
description: List all ultra-analyzer runs in the current project, with current step, status, profile, and key counters. Use to find where you left off across multiple analyses.
allowed-tools: Bash, Read, Glob
---

# Role
Directory listing with status enrichment. No mutations.

# Invocation
  /ultra-analyzer:list-runs [--verbose]

# Protocol

## Step 1: Locate runs
```bash
runs=$(ls -d .planning/ultra-analyzer/*/ 2>/dev/null | grep -v '_explore-drafts')
```
If none, print: "No runs found. Start one with /ultra-analyzer:init <name>."

## Step 2: For each run, read state.json
```bash
for run in $runs; do
  state="$run/state.json"
  [[ -f "$state" ]] || continue
  # Extract summary fields
  jq -r '[.run, .profile.tier // "large", .current_step, .status, .counters.topics_total, .counters.topics_done, .counters.topics_failed, .updated_at] | @tsv' "$state"
done
```

## Step 3: Format as a table

```
ultra-analyzer runs in .planning/ultra-analyzer/

NAME                  PROFILE  STEP                  STATUS    TOPICS (done/total)  FAILED  UPDATED
my-json-analysis      large    analyze               running   34/60                2       2026-04-16 15:30
coaching-q2           large    done                  passed    58/60                2       2026-04-14 11:20
security-audit        xl       pre-synthesize-gate   blocked   75/75                0       2026-04-15 09:45
quick-poc             small    init                  pending   0/0                  0       2026-04-16 14:00

4 runs total: 1 running, 1 passed, 1 blocked, 1 pending
```

## Step 4: If --verbose
Also emit per run:
- Ultra-gate verdicts (pre-discover, pre-synthesize)
- Last checkpoint timestamp
- Next suggested action (delegate to `/ultra-analyzer:next` output per run)

## Step 5: Suggest action
At the end, based on the aggregate status:
- If any run is `blocked`: "X runs are blocked. Run /ultra-analyzer:health <name> to diagnose."
- If any run is `running`: "X runs are in progress. /ultra-analyzer:progress <name> for details."
- If all runs are `done`: "All runs complete. Start a new one with /ultra-analyzer:init."

# Hard rules
- Read-only. No state mutations.
- Skip directories without a valid state.json (warn once at the end: "ignored N directories without state.json").
- If state.json is malformed (jq parse fails), list the run with status=CORRUPT and suggest `/ultra-analyzer:health`.
