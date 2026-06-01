---
name: resume
description: (beta) Crash-safe resume for an interrupted migration. Dumps current progress, clears orphan locks, requeues orphaned in-progress units, re-renames any chat that already had its first turn (awaited_ok) but was not renamed, re-polls a seeded chat for its first turn, runs a destination dedupe probe on any ambiguous "opened" chat before re-seeding, re-opens a blocked user gate, then hands back to the controller. Use when the user types /claude-migrate:resume, or says "resume my migration", "continue where I left off", "I dropped the export, pick it up".
allowed-tools: Bash, Read, Write, Skill, AskUserQuestion
---

# Role
The recovery entry point. State lives entirely in `state.json` + the filesystem work queues, so resume is deterministic: re-read state, repair the few crash-fragile spots, and hand back to `run`. It is idempotent - running it twice is safe. It is a standalone skill, distinct from `run`: the dir is `skills/resume/`, the frontmatter `name` is `resume`, the suffix is `/claude-migrate:resume`, and `commands/resume.md`'s Skill-tool target is the string `resume` (Repo H-3). It NEVER forces a state change that the controller would refuse - a FAILED gate stays failed until the user fixes the cause.

# Invocation
  /claude-migrate:resume <run-name>

`<run-name>` is required. `RUN_PATH=".planning/claude-migrate/<run-name>"`. Abort if `state.json` is missing - tell the user to `/claude-migrate:init` first.

# Protocol

## Step 1: Progress dump
Invoke the `progress` skill via the Skill tool (read-only) so the user sees exactly where the run paused: `current_step`, `status`, `blocked_reason`, the queue counters, and the gate verdicts. This is the orientation step before any repair.

## Step 2: Heal orphan mkdir-locks
EXIT traps in `claim.sh` / `state.sh` / `release.sh` / `requeue.sh` do NOT fire on `kill -9` or power loss, leaving orphan lock dirs that make every subsequent `state.sh inc/set/dec` spin for 30s. Clear them BEFORE any state write. Candidate lock dirs:
- `$RUN_PATH/state.json.lock.d`
- `$RUN_PATH/units/.claim.lock.d`
- `$RUN_PATH/seed/.claim.lock.d`
- each `$RUN_PATH/project/<PNN__slug>/.create.lock.d`

For each, apply the heuristic: if a live holder PID is recorded and still running, leave it; else if the lock dir is older than 30s with no live holder, `rmdir` it (orphan from a crash); a fresh lock from a live worker is preserved:
```bash
heal_orphan_lock() {
  local lockdir="$1"
  [[ -d "$lockdir" ]] || return 0
  local pidfile="$lockdir/holder.pid"
  if [[ -f "$pidfile" ]]; then
    local pid; pid=$(cat "$pidfile" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "[resume] lock $lockdir held by live PID $pid - leaving alone" >&2; return 0
    fi
  fi
  local age_s mtime
  if stat -f '%m' "$lockdir" >/dev/null 2>&1; then mtime=$(stat -f '%m' "$lockdir")   # macOS / BSD
  else mtime=$(stat -c '%Y' "$lockdir"); fi                                            # GNU / Linux
  age_s=$(( $(date +%s) - mtime ))
  if [[ "$age_s" -gt 30 ]]; then
    echo "[resume] orphan lock at $lockdir (age=${age_s}s, no live holder) - removing" >&2
    rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir"
  else
    echo "[resume] lock $lockdir is fresh (${age_s}s) - likely a live worker; leaving alone" >&2
  fi
}
```
Idempotent: a live worker's lock survives, a crash orphan is cleared. Deeper diagnostics (counter drift) belong to `/claude-migrate:health`; resume's heal is intentionally narrow.

## Step 3: Requeue orphaned in-progress work units
Crashed workers leave units in `units/in-progress/` (preflight/distill) and seed items in `seed/in-progress/` (apply). For each, requeue back to `pending/` via `release.sh` so the counters stay invariant - never `mv` by hand:
```bash
for f in "$RUN_PATH"/units/in-progress/*.md; do
  [[ -e "$f" ]] || continue
  bash ${CLAUDE_PLUGIN_ROOT}/bin/release.sh "$f" requeue resumed-orphan
done
```
For `seed/in-progress/` items, do NOT blindly requeue - they may be mid-apply and require the per-seed inspection in Step 4 first. If a live `apply` worker may still be running in this session, do NOT requeue its in-progress units; only requeue after confirming no apply is active.

## Step 4: Per-seed crash-safe repair (browser/auto only; reads seed/UNNN.json - the SOLE resume authority)
`seed/UNNN.json` is the only resume authority; `apply/UNNN.result.json` is a report artifact only. For each `seed/UNNN.json`, branch on `status` (resume rules §3.5):
- `done` → skip.
- `renamed` → skip (rename already applied).
- `awaited_ok` (not `renamed`) → re-run rename ONLY. Never re-seed. Rename is idempotent.
- `seeded` (not `awaited_ok`) → re-poll for the first assistant turn, bounded by `ok_wait_ms`. On timeout, leave `status=seeded` + `last_error=ok_timeout` (never `failed`).
- `opened` → **AMBIGUOUS** (crash between submit and the seeded write). Run SINK `dedupe_probe` FIRST via the sink adapter; if a matching destination chat exists, adopt it (`status=seeded`, record `dest_chat_url`) and DO NOT re-submit (C-2). Only if no match exists may the unit be re-seeded.
- `rate_limited` → set `status=pending` (re-claimable; never `failed`).
- `in-progress`/`pending` → leave for `apply` to re-claim.

Drive these through `apply-unit` (invoked via the Skill tool in-session) so the same write-ahead logic applies; do not hand-edit `seed/UNNN.json`.

## Step 5: Re-open a blocked user gate
If `status == blocked` AND `blocked_reason` is a user gate (`filter-gate`, `auto-reoffer`, `login`, `browser-lost`, `cost`), hand to `confirm` rather than `run`:
```
Run /claude-migrate:confirm <run-name> to clear the <blocked_reason> gate.
```
Invoke skill `claude-migrate:confirm` with argument `<run-name>` via the Skill tool. (For `login`/`browser-lost`, `confirm` re-probes the browser per `references/login-policy.md`.) Do NOT clear a `FAIL` machine-gate or skip it - resume never magically advances past a failed gate.

## Step 6: A dropped-in export (live-mode handoff)
If `input.mode == "live"` and the run was parked waiting for an export ZIP, and the user has now placed the unzipped export, set `input.mode=export` + `input.export_path`, stage `source/` (NEVER `users.json`), swap `source-connector.md` to the export template, and continue. This is the preferred live path (trigger the official export, drop it, resume).

## Step 7: Hand to the controller
If the run is not blocked on a user gate, invoke skill `claude-migrate:run` with argument `<run-name>` via the Skill tool. It picks up from `current_step`.

# Hard rules
- The dir name, frontmatter `name`, invocation suffix, and command target are ALL the string `resume` (Repo H-3) - `resume` is a standalone skill, not an alias of `run`.
- Never force a state change the controller would refuse: a FAILED machine-gate stays FAILED until the user fixes the cause.
- `seed/UNNN.json` is the SOLE resume authority - never trust `apply/UNNN.result.json` for resume decisions, and never hand-edit `seed/UNNN.json`.
- An `opened` seed unit MUST run `dedupe_probe` before any re-seed (C-2) - never blind-resubmit.
- An `awaited_ok` unit re-runs ONLY rename; a `seeded` unit re-polls (never re-seeds); a `seeded` await timeout stays `seeded` (never `failed`).
- Requeue orphaned units only through `release.sh` (counter-safe) - never `mv` by hand; never requeue a unit a live worker may still hold.
- A blocked user gate hands to `confirm`; everything else hands to `run`.
- Never mutate `state.json` outside `bin/state.sh`. Never reference any specific domain; labels come from `config.yaml`.
