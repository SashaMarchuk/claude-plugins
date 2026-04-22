---
name: pause
description: Write a handoff document for a run so you can switch contexts and resume cleanly later (or hand off to someone else). Snapshots state, notes pending decisions, lists next actions.
allowed-tools: Bash, Read, Write, Glob
---

# Role
Persist a human-readable pause memo. Useful when taking a break mid-run, switching to a different project, or handing off to a colleague.

# Invocation
  /ultra-analyzer:pause [run-name] [--note "freeform note"]

# Protocol

## Step 1: Locate run (standard rules)

## Step 2: Snapshot state
- Call `bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh checkpoint <run-path>` to create a state.json snapshot.
- Capture timestamp.

## Step 3: Gather context
Read:
- state.json (current step, status, counters)
- `<run>/run.log` tail (last 10 entries)
- `<run>/validation/gate1-*.md` or gate2 most recent (if exists)
- Any topics with retry count >=2 (flagging potential systemic issues)
- `<run>/seeds.md` (for context)

## Step 4: Generate PAUSE.md at `<run>/PAUSE-<timestamp>.md`

```markdown
# Pause: <run-name>

**Paused at:** 2026-04-16T15:30:00Z
**Author note:** <from --note, or "none">
**Checkpoint:** <path-to-checkpoint-json>

## Current state
- Step: <current_step>
- Status: <status>
- Profile: <profile.tier>

## Progress
- Topics: <done>/<total> done, <failed> failed, <pending> pending, <in_progress> in-progress
- Findings: <passed> passed, <failed_findings> failed
- Ultra gates: pre-discover=<verdict>, pre-synthesize=<verdict>

## Context to remember when resuming

### Decision-maker + primary question
<from config.yaml run.stakeholder + run.primary_question>

### Active seeds (top 3 P1)
<first 3 P1 seed titles from seeds.md>

### Recent issues (from run.log tail)
<last 10 run.log entries, reformatted>

### Topics on retry (>=2 retries)
<topic basenames + reason slugs — these indicate systemic problems to investigate before resuming>

### Last gate verdict
<summary of most recent gate report, if any>

## Next action on resume
<copy from /ultra-analyzer:next output>

## How to resume
1. (optional) Read this PAUSE.md to refresh context.
2. Run: /ultra-analyzer:progress <run-name>  — reconcile with current state.
3. Run: /ultra-analyzer:resume <run-name>  — continues the pipeline.

## Known hazards on resume
- <any in-progress topics with orphan risk>
- <any env vars that must be re-set>
- <any stale locks detected>
```

## Step 5: Print summary

```
✓ Paused: <run-name>
  Snapshot: <checkpoint path>
  Handoff doc: <run>/PAUSE-<timestamp>.md
  
To resume: /ultra-analyzer:resume <run-name>
```

# Hard rules
- NEVER modify state.status to "paused" — there is no such status. pause is a DOC operation, not a state change.
- NEVER delete prior PAUSE-*.md files — they're an audit trail.
- If --note is unsafe (contains anything that looks like a secret), strip and warn. We do not write secrets to this file.
- The handoff doc MUST include concrete next-action commands, not vague "continue where you left off".
