---
name: health
description: (beta) Diagnose a stuck migration run and PROPOSE (never auto-apply) repairs. Checks corrupt state.json, stale lock dirs, orphaned in-progress units, the §3.3 counter-sum invariants, and seed/project drift. Prints every finding with a severity and a copy-paste repair command the user runs themselves. Use when the user types /claude-migrate:health, or says "my migration is stuck", "the run looks frozen", "lock timeout", "counters look wrong", "diagnose the migration".
allowed-tools: Bash, Read
---

# Role
Diagnostic only. Run a battery of read-only checks against one run's `state.json` plus its work-queue dirs, then report each finding with a SEVERITY and a suggested repair COMMAND. This skill PROPOSES repairs; it NEVER applies them. The user copy-pastes the command they choose. There is no `--fix` auto-apply mode by design - a migration moves real chats into a real account, so every mutation stays under human control.

# Invocation
  /claude-migrate:health [<run-name>]

- `<run-name>` optional. If omitted, auto-detect: list `.planning/claude-migrate/` and if exactly one run dir exists, use it; otherwise print the available runs and exit.

# Protocol

## Step 1: Locate the run
- Parse `<run-name>` from `$ARGUMENTS`.
- If absent: `ls .planning/claude-migrate/` - if exactly one dir, use it; else print available runs and exit.
- `RUN_PATH=".planning/claude-migrate/<run-name>"`.
- If `$RUN_PATH/state.json` is missing, STOP: "No such run. Initialize with `/claude-migrate:init <run-name>` first."

## Step 2: Run the checks (read-only)

### Check 1: state.json integrity
- Does `$RUN_PATH/state.json` exist and parse as JSON (`jq -e . "$RUN_PATH/state.json"`)?
- Are all required top-level fields present: `run`, `current_step`, `status`, `input`, `output`, `profile`, `gates`, `decisions`, `counters`?
- Is `current_step` a member of the §3.1 enum (`init, pre-split-gate, split, preflight, filter-gate, distill, synthesize, build-page, verify-gate, ready, pre-apply-gate, apply, finalize, done, failed`)?
- On any failure: SEVERITY=CRITICAL. PROPOSE: restore from the newest checkpoint -
  ```bash
  ls -t "$RUN_PATH/checkpoints"/*.json | head -1   # newest snapshot
  # then, after reviewing it:  cp "<that-file>" "$RUN_PATH/state.json"
  ```

### Check 2: Stale lock dirs (PID-aware)
claude-migrate uses mkdir-based locks. Candidate lockdirs:
- `$RUN_PATH/state.json.lock.d` (the state writer)
- `$RUN_PATH/units/.claim.lock.d` (preflight/distill queue claims)
- `$RUN_PATH/seed/.claim.lock.d` (apply queue claims)
- every `$RUN_PATH/project/*/.create.lock.d` (per-project create prelude)

For each lockdir that exists:
1. If a `holder.pid` file is inside it and `kill -0 <pid>` succeeds, a live process holds it - leave it alone (a worker is mid-write).
2. Otherwise read its age (`stat -f %m "$lockdir"` on macOS / `stat -c %Y "$lockdir"` on Linux; compare to `date +%s`):
   - age > 30s and no live holder: SEVERITY=WARN (likely a SIGKILL/power-loss orphan). PROPOSE: `rmdir "<lockdir>"`.
   - age > 10 min regardless: SEVERITY=CRITICAL. PROPOSE: `rmdir "<lockdir>"`.
   - age < 30s: leave alone (likely a live writer mid-operation); report as PASSED.
This mirrors the auto-heal that `/claude-migrate:resume` performs; `health` only surfaces it as a finding and proposes the `rmdir`, never running it.

### Check 3: Orphaned in-progress units
For BOTH queues - `$RUN_PATH/units/in-progress/` and `$RUN_PATH/seed/in-progress/`:
- An item there with an mtime > 30 min old and no matching worker heartbeat in the recent `run.log` is likely orphaned (its worker died after claiming but before releasing).
- SEVERITY=WARN. PROPOSE the requeue back to `pending/` with a retry tag (this is exactly what `/claude-migrate:resume` does automatically):
  ```bash
  # units queue:
  bash ${CLAUDE_PLUGIN_ROOT}/bin/release.sh "<orphan-item-path>" requeue orphaned
  # seed queue item: resume re-derives its status from seed/UNNN.json; prefer:
  /claude-migrate:resume <run-name>
  ```
- Do NOT propose requeueing an item whose lock is held by a live PID (Check 2). Surface that ambiguity instead.

### Check 4: Counter-sum invariants (§3.3) - run on EVERY invocation
Assert every invariant against live state. A broken invariant means a bug, a manual edit, or a half-completed move corrupted the bookkeeping:
```bash
jq -r '
  .counters as $c
  | [ ($c.chats_total == ($c.preflight_pending + $c.preflight_in_progress + $c.preflight_done + $c.preflight_failed)),
      ($c.kept        == ($c.distill_pending  + $c.distill_in_progress  + $c.distill_done  + $c.distill_failed)),
      ($c.kept        == ($c.seeded_units + $c.doc_only_units)),
      ($c.seeded_units== ($c.seed_pending + $c.seed_in_progress + $c.seed_done + $c.seed_failed)),
      ($c.projects_total == ($c.projects_pending + $c.projects_created)) ]
  | to_entries[] | "\(.key): \(.value)"
' "$RUN_PATH/state.json"
```
Map index 0->chats_total, 1->kept(distill), 2->kept(routing), 3->seeded_units(seed queue; auto mode only), 4->projects_total. Index 3 only applies when `output.mode == "auto"` (the seed queue is sized to `seeded_units`, not `kept`). Any `false` -> SEVERITY=CRITICAL.
- Additional pre-pass invariant (auto mode, before `status=passed`): `projects_created == projects_finalized`. If `current_step` is at/after `finalize` and these differ -> SEVERITY=CRITICAL: "a project never swapped to steady - never reach done in migration mode."
- PROPOSE (do NOT auto-run): rebuild the offending counters from filesystem ground truth, then re-run health. Show the exact `state.sh set/inc/dec` calls needed, derived from the queue-dir counts in Check 6, and tell the user to apply them one at a time and re-check the invariant after each.

### Check 5: state.json vs filesystem counter drift (per queue)
Compare each counter against the directory that IS its state:
```bash
ls "$RUN_PATH/units/pending"     2>/dev/null | wc -l   # vs .counters.preflight_pending
ls "$RUN_PATH/units/in-progress" 2>/dev/null | wc -l   # vs .counters.preflight_in_progress
ls "$RUN_PATH/units/done"        2>/dev/null | wc -l   # vs .counters.preflight_done
ls "$RUN_PATH/units/failed"      2>/dev/null | wc -l   # vs .counters.preflight_failed
ls "$RUN_PATH/units/dropped"     2>/dev/null | wc -l   # vs .counters.dropped
ls "$RUN_PATH/seed/pending"      2>/dev/null | wc -l   # vs .counters.seed_pending  (auto mode)
ls "$RUN_PATH/seed/in-progress"  2>/dev/null | wc -l
ls "$RUN_PATH/seed/done"         2>/dev/null | wc -l
ls "$RUN_PATH/seed/failed"       2>/dev/null | wc -l
ls "$RUN_PATH/briefs"/*.brief.md 2>/dev/null | wc -l   # rough vs distill_done
```
A mismatch -> SEVERITY=WARN. PROPOSE the single `state.sh set` that reconciles each drifting counter to the filesystem count (filesystem is ground truth for queue state). The repair is idempotent: re-running it after a correct value does nothing.

### Check 6: Connectors + config present
- `$RUN_PATH/source-connector.md` and `$RUN_PATH/sink-connector.md` exist?
- `$RUN_PATH/config.yaml` and `$RUN_PATH/selectors.json` exist?
- Missing -> SEVERITY=CRITICAL. PROPOSE: copy the matching template, e.g.
  ```bash
  cp ${CLAUDE_PLUGIN_ROOT}/templates/sources/export-file.md "$RUN_PATH/source-connector.md"
  ```
  or re-author via `/claude-migrate:config <run-name>`.

### Check 7: Gate verdict vs report-file mismatch
For each of `gates.pre-split`, `gates.verify`, `gates.pre-apply`: if `verdict == "PASS"` but the recorded `report` path does not exist on disk -> SEVERITY=WARN (the audit trail is broken; likely safe to proceed but unverifiable). PROPOSE: manual review - re-run the relevant `/claude-migrate:run <run>` gate to regenerate the report, or accept the gap knowingly.

### Check 8: Resume-authority drift (auto mode)
The sole resume authority for a seeded unit is `seed/<queue>/UNNN.json`; `apply/UNNN.result.json` is a report only. Scan for units whose `seed/*/UNNN.json` says `status in {seeded, awaited_ok}` but `renamed` was never reached, or `status == opened` (AMBIGUOUS - a crash may have happened mid-submit). SEVERITY=WARN. PROPOSE: `/claude-migrate:resume <run-name>` (it re-polls `seeded`, renames `awaited_ok`-not-`renamed`, and runs a SINK `dedupe_probe` on `opened` before any re-seed). Never propose deleting an `opened` unit.

### Check 9: Disk space
- `df -h .` on the run's filesystem. If < 5% free -> SEVERITY=WARN. PROPOSE: free space before the opus synthesize/verify steps (they load the full briefs corpus).

## Step 3: Report
```
claude-migrate health: <run>   (output.mode=<auto|copy-page>, step=<current_step>, status=<status>)
Checks: 9   Passed: <P>   Warn: <W>   Critical: <C>

=== CRITICAL ===
[CRIT] <finding one line>
       Cause:  <one line>
       Repair (RUN IT YOURSELF): <exact command>

=== WARN ===
[WARN] <finding one line>
       Repair (RUN IT YOURSELF): <exact command>

=== PASSED ===
ok  state.json integrity
ok  no stale locks
ok  counter-sum invariants (§3.3)
...
```
If there are zero CRITICAL/WARN findings, print "Run looks healthy. Next action: `/claude-migrate:progress <run>`."

# Hard rules
- DIAGNOSE only. NEVER apply a repair, NEVER mutate `state.json`, NEVER move or delete a queue item, NEVER `rmdir` a lock. Print the command; the user runs it.
- NEVER kill a process. If a stale lock might belong to a live worker (PID alive, or age < 30s), surface the ambiguity rather than proposing a remove.
- Every proposed repair MUST be idempotent - running it twice does no harm - and MUST route mutations through `bin/state.sh`, `bin/release.sh`, `bin/requeue.sh`, or `/claude-migrate:resume`, never a raw edit of `state.json`.
- The counter-sum invariant (Check 4) runs on every invocation; a broken invariant is always CRITICAL.
- Never display secrets or PII. Show hashes and counts only; never echo `dest_chat_url`, raw briefs, emails, or tokens.
- Never reference any specific domain; bucket and group labels come from `config.yaml`.
