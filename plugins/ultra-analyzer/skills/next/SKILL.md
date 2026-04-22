---
name: next
description: Reads state.json and tells the user the single next action to take. Unlike /run which advances state, /next only ADVISES — it won't invoke /ultra gates or launch workers. Use when you forgot where you left off or want to know before committing.
allowed-tools: Bash, Read
---

# Role
Read-only advisor. Output: exactly one sentence saying what to do next.

# Invocation
  /ultra-analyzer:next [run-name]

# Protocol

## Step 1: Locate run
Same rules as `/ultra-analyzer:run` Step 1. If multiple runs and none specified, list them with `/ultra-analyzer:list-runs` guidance.

## Step 2: Read state
```bash
current_step=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .current_step)
status=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .status)
pending=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .counters.topics_pending)
done=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .counters.topics_done)
total=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .counters.topics_total)
in_progress_count=$(ls $RUN_PATH/topics/in-progress/*.md 2>/dev/null | wc -l)
```

## Step 3: Emit a single recommendation

Format:
```
<current_step> / <status>  [<progress>]
→ <one-sentence next action>
  <optional second line with exact command>
```

### Decision table

| step / status | recommendation |
|---|---|
| init / pending | "Edit config.yaml + seeds.md + connector.md, then run /ultra-analyzer:run" |
| init / pending (no connector.md) | "First, create connector.md: copy `${CLAUDE_PLUGIN_ROOT}/templates/connectors/<type>.md` to `<run>/connector.md`, or run /ultra-analyzer:connector-init" |
| pre-discover-gate / pending | "Run /ultra-analyzer:run to invoke Gate 1 (/ultra reviews config+seeds)" |
| pre-discover-gate / blocked | "Gate 1 failed. Read <run>/validation/gate1-*.md, fix flagged issues, then /ultra-analyzer:run" |
| discover / running | "discover is in progress — wait for it to complete" |
| analyze / running (pending > 0) | "Open N terminals running: bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-terminal.sh <run>. N topics pending." |
| analyze / running (pending == 0, in_progress > 0) | "Workers still processing <in_progress> topics. /ultra-analyzer:progress to watch." |
| analyze / running (all done, pass rate >= 50%) | "All topics resolved. Run /ultra-analyzer:run to advance to Gate 2." |
| analyze / blocked | "PASS rate too low (<50%). Inspect failing findings before advancing. See /ultra-analyzer:health for diagnosis." |
| pre-synthesize-gate / pending | "Run /ultra-analyzer:run to invoke Gate 2 (/ultra reviews findings corpus)." |
| pre-synthesize-gate / blocked | "Gate 2 flagged topics were requeued. Re-run workers, then /ultra-analyzer:run to re-gate." |
| synthesize / running | "Synthesis in progress. Will produce <run>/synthesis/REPORT.md." |
| done / passed | "DONE. Read <run>/synthesis/REPORT.md" |
| failed / failed | "Run is in failed state. Tail <run>/run.log for the error, or /ultra-analyzer:health for diagnosis." |

## Step 4: Exit cleanly (no state mutation)

# Hard rules
- NEVER advance state. NEVER invoke /ultra. NEVER launch workers. This command is an advisor only.
- NEVER write files to <run-path>.
- Output MUST be ≤ 5 lines. User invokes this when they want a quick answer, not a dashboard.
