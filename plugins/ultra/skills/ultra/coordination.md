# Multi-Terminal Coordination Protocol

## When This Applies

Only when BOTH `--task=<name>` AND `--terminal=<N>` flags are present. Without these flags, /ultra runs as a single-terminal operation.

## File Structure

```
.planning/ultra/<task>/
  coordination.json       # Terminal registry + status
  state.json              # Shared progress tracking (schema below)
  claims/
    terminal-1.lock       # Territory lock for terminal 1
    terminal-2.lock       # Territory lock for terminal 2
    ...
  findings/
    terminal-1.json       # Results from terminal 1
    terminal-2.json       # Results from terminal 2
    ...
  territory-map.json      # What each terminal is investigating
  synthesis.md            # Final synthesis (written by last terminal)
  synthesis.lock          # Lock file for synthesis claim
  summary.md              # Executive summary

.planning/ultra/
  lessons.md              # Self-improvement log (GLOBAL, not per-task)
```

### state.json Schema

Used for BOTH single-terminal and multi-terminal runs. Updated after each phase completes.

```json
{
  "task": "<task-name>",
  "tier": "large",
  "created_at": "ISO8601",
  "updated_at": "ISO8601",
  "terminals": {
    "1": {
      "phases_completed": ["phase0", "phase1", "phase2"],
      "current_phase": "phase3",
      "phase_started_at": "ISO8601"
    }
  }
}
```

For single-terminal runs (no `--terminal` flag), use terminal key `"0"`.
The `tier` field is preserved for `--resume` to maintain consistency across runs.

## Terminal Registration

When a terminal starts with `--terminal=N --task=<name>`:

1. Create `.planning/ultra/<task>/` if it doesn't exist
2. Read `coordination.json` (create if missing)
3. Register this terminal:

```json
{
  "task": "<task-name>",
  "terminals": {
    "1": { "status": "running", "started_at": "ISO8601", "last_phase_update": "ISO8601" },
    "2": { "status": "running", "started_at": "ISO8601", "last_phase_update": "ISO8601" }
  }
}
```

4. Update `last_phase_update` timestamp in `coordination.json` after completing EACH phase. This replaces heartbeats — synchronous agents cannot emit periodic writes, so phase completion is the liveness signal.

## Territory Claiming (Strict Lock Files)

Before Phase 2 (Research), each terminal must claim its investigation territory:

### Claim Process

1. Read `territory-map.json` to see what's already claimed
2. Choose UNCLAIMED territory (different perspective, angle, or solution space)
3. Write a lock file: `claims/terminal-N.lock`

```json
{
  "terminal": N,
  "claimed_at": "ISO8601",
  "territory": "Description of what this terminal is investigating",
  "perspective": "The angle/approach this terminal is taking",
  "keywords": ["key", "terms", "this", "terminal", "covers"]
}
```

4. Update `territory-map.json` with the claim
5. After 3-5 research steps, RE-READ all lock files to verify no overlap
6. If overlap detected with a later terminal, the LATER terminal must pivot

### Overlap Detection

Two territories overlap if:
- Keywords have >50% overlap
- Perspective descriptions are semantically similar
- Both terminals are investigating the same specific tool/approach/solution

### Overlap Resolution

- **First-come wins**: Check `claimed_at` timestamps. Earlier claim keeps territory.
- **Later terminal pivots**: Must choose a different perspective and update its lock file.
- **If all territory is claimed**: Later terminal takes a META perspective — synthesize and cross-validate what other terminals found.

## Stale Lock Detection

A lock file is considered STALE if:
- The terminal's `last_phase_update` in `coordination.json` is older than **30 minutes** (phases can take time, especially with many agents)
- The terminal's status is still "running" but no phase updates
- Note: since agents are synchronous, liveness is measured by phase completions, not heartbeats

### Stale Lock Recovery

1. Mark the stale terminal as `"status": "stale"` in `coordination.json`
2. Release its territory claim (delete its lock file)
3. Other terminals can now claim that territory
4. If the stale terminal comes back, it must re-register and claim new territory

## Progress Tracking

Each terminal writes to its own findings file: `findings/terminal-N.json`

```json
{
  "terminal": N,
  "tier": "large",
  "phases_completed": ["scope", "research", "synthesis"],
  "current_phase": "validation",
  "key_findings": [
    { "id": "F1", "claim": "...", "evidence": "...", "confidence": 8 }
  ],
  "timestamp": "ISO8601"
}
```

**Contribution Rules**:
- Each terminal writes ONLY to its own findings file
- Terminals may READ other terminals' findings for coordination
- No terminal may MODIFY another terminal's findings
- The territory-map.json and coordination.json are shared and require read-before-write

## Last Terminal Detection & Synthesis

When a terminal completes all its phases:

### Step 1: Mark Finish
Update `coordination.json`:
```json
"terminals": {
  "N": { "status": "finished", "finished_at": "ISO8601" }
}
```

### Step 2: Check All Finished
Read `coordination.json`. Are ALL registered (non-stale) terminals "finished"?
- If NO: Write findings, exit. Another terminal will do synthesis.
- If YES: Proceed to Step 3.

### Step 3: Claim Synthesis
Write `synthesis.lock`:
```json
{
  "claimed_by": N,
  "claimed_at": "ISO8601"
}
```

### Step 4: Wait & Verify (15-second grace period)
Use Bash tool: `sleep 15` to wait. Then re-read `synthesis.lock`.
- If `claimed_by` is still YOUR terminal number: You are the synthesizer. Proceed.
- If `claimed_by` changed to another terminal: That terminal is the synthesizer. Exit.
- If multiple claims (file was overwritten): Compare `claimed_at` timestamps. Earliest wins.

### Step 5: Run Synthesis
The synthesizing terminal:
1. Reads ALL `findings/terminal-*.json` files
2. Reads ALL `claims/terminal-*.lock` files to understand perspectives
3. Performs a cross-terminal synthesis:
   - Where terminals converge: HIGH CONFIDENCE
   - Where terminals diverge: INVESTIGATE (may need to re-run devil's advocate)
   - Unique findings from each terminal
4. Runs a condensed anti-slop audit on the merged findings
5. Writes `synthesis.md` with the merged results
6. Writes `summary.md` with the executive summary
7. Updates `coordination.json` with `"synthesis_by": N, "synthesis_at": "ISO8601"`

## Resuming with --resume

When `--resume` is used with `--task=<name>`:

1. Read `state.json` — get this terminal's `phases_completed` array and the original `tier`
2. Read `coordination.json` if multi-terminal
3. Resume from the first phase NOT in `phases_completed`
4. Use the `tier` from `state.json` (ignore any tier flag on the resume command to maintain consistency)
5. Trust previous findings (don't re-run completed phases)
6. If multi-terminal and new findings from other terminals appeared since last run, incorporate them

## Incremental Improvement

When running `/ultra --task=<name>` on the same task again (without --resume):

1. Check if `.planning/ultra/<task>/` exists with previous findings
2. If yes, treat previous findings as CONTEXT (not constraints)
3. New agents get a brief: "Previous research found [summary]. Build on this but verify independently."
4. The new run may confirm, extend, or contradict previous findings
5. Update findings files (don't overwrite — append with version markers)
