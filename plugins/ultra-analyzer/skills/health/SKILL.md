---
name: health
description: Diagnose a run's health and offer fixes for common failure modes. Checks stale locks, orphaned in-progress topics, corrupt state.json, counter drift, missing artifacts. Proposes repairs but does NOT auto-apply them.
allowed-tools: Bash, Read, Glob
---

# Role
Diagnostic. Runs a battery of checks against a run's state, reports findings with severity + suggested repair commands.

# Invocation
  /ultra-analyzer:health [run-name] [--fix]

With `--fix`, applies repairs automatically (with a 3-second confirmation countdown).
Without `--fix`, only reports.

# Protocol

## Step 1: Locate run (standard rules)

## Step 2: Run checks

### Check 1: state.json integrity
- File exists? Parseable JSON?
- All required top-level fields present? (`run`, `current_step`, `status`, `counters`, `ultra_gates`)
- If not: SEVERITY=CRITICAL, REPAIR="restore from latest checkpoint at <run>/checkpoints/".

### Check 2: Stale locks (PID-aware — H-6)
For each candidate lockdir (`<run>/topics/.claim.lock.d/` and `<run>/state.json.lock.d/`):

1. If `holder.pid` file exists and `kill -0 <pid>` succeeds → lock is held by
   a live worker; leave alone.
2. Otherwise compute age via `stat -f %m` (macOS) / `stat -c %Y` (Linux):
   - Age > 30s with no live holder → orphan (likely SIGKILL / power loss).
     SEVERITY=WARN, REPAIR=`rmdir <lockdir>`.
   - Age > 10 min regardless → SEVERITY=CRITICAL, REPAIR=`rmdir <lockdir>`.
   - Age < 30s → likely a live worker mid-write; leave alone.

This logic mirrors `/ultra-analyzer:resume`'s Step 1b auto-heal so a single
implementation rules both surfaces. Resume runs the heal automatically,
health surfaces it as a check + reports it.

### Check 3: Orphaned in-progress topics
- Topics in `topics/in-progress/` but no active worker process owns them.
- Heuristic: if mtime >30 min old AND no worker heartbeat in `run.log` since then → orphaned.
- REPAIR: move each back to `pending/` with retry tag:
  ```bash
  mv <topic> <run>/topics/pending/$(basename ${topic%.md})__retry-$(date +%s)-orphaned.md
  ```

### Check 4: Counter drift
- Does `counters.topics_done` match `ls topics/done | wc -l`?
- Does `counters.findings_passed` match `ls validation/findings/*.json | jq 'select(.verdict=="PASS")' | wc -l`?
- If drift detected: SEVERITY=WARN, REPAIR="rebuild counters from filesystem ground truth".

### Check 5: Missing adapter outputs
- Topics exist but `state/schemas.json` missing? discover-topics didn't finish cleanly.
- SEVERITY=CRITICAL, REPAIR="re-run /ultra-analyzer:discover-topics or rollback to init".

### Check 6: Validator coverage
- Every finding has a matching verdict in validation/findings/?
- Findings without verdict = validator skipped or crashed.
- SEVERITY=WARN, REPAIR="re-invoke validator on orphan findings".

### Check 7: Gate verdict files
- If `ultra_gates["pre-discover"].verdict == "PASS"` but no report file exists at the recorded path → state-artifact mismatch.
- SEVERITY=WARN, REPAIR=manual — likely safe, but the audit trail is broken.

### Check 8: connector.md presence + smoke-test
- `<run>/connector.md` exists?
- `bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <run> enumerate` returns non-empty?
- If either fails: SEVERITY=CRITICAL, REPAIR="run /ultra-analyzer:connector-init or copy a template".

### Check 9: Env vars required by connector
- Grep `connector.md` for `$VARNAME` references.
- Check each is set in the current environment.
- If unset: SEVERITY=CRITICAL (workers will fail), REPAIR=user must export env vars before launching.

### Check 10: Disk space
- `df -h` on the run's filesystem.
- If <5% free: SEVERITY=WARN, REPAIR="clear space before synthesis (Opus synthesis loads entire findings corpus)".

## Step 3: Report

```
ultra-analyzer health: <run-name>
Checked: 10 / Passed: 7 / Warn: 2 / Critical: 1

=== CRITICAL ===
[CRIT] connector.md smoke-test failed: enumerate returned empty
       Cause: likely missing $MONGO_URI env var
       Repair: export MONGO_URI=... && retry smoke-test

=== WARN ===
[WARN] Counter drift: state.counters.topics_done=42, ls topics/done | wc -l = 45
       Repair: bash ${CLAUDE_PLUGIN_ROOT}/bin/health-rebuild-counters.sh <run>
       (provided by --fix mode)

[WARN] 3 orphaned topics in topics/in-progress/ (mtime > 30 min)
       Repair: move back to pending/ with retry tag
       (provided by --fix mode)

=== PASSED ===
✓ state.json integrity
✓ stale locks
✓ missing adapter outputs
✓ validator coverage
✓ gate verdict files
✓ env vars
✓ disk space
```

## Step 4: If --fix
For each repairable issue, print the repair command and a 3-second countdown. On timeout or user Enter → execute. Ctrl-C to abort.

Repairs that require user involvement (set env var, restore from checkpoint, run connector-init) are never auto-applied — they're listed but left to the user.

# Hard rules
- Default is DIAGNOSE only. --fix must be explicit.
- NEVER auto-modify state.json content beyond counter rebuilds (which are verifiable against filesystem).
- NEVER auto-kill processes. If a stale lock is suspected to belong to a live worker, surface that ambiguity to the user.
- Every repair must be idempotent — running it twice does no harm.
