---
name: resume
description: Resume an interrupted analyzer run from its last checkpoint. Alias for /ultra-analyzer:run with explicit resume semantics and a progress dump first.
allowed-tools: Bash, Read, Skill
---

# Role
Convenience wrapper. Show progress, then advance the pipeline.

# Invocation
  /ultra-analyzer:resume [run-name]

# Protocol

## Step 1: Call /ultra-analyzer:progress
Invoke the progress skill to print current state. User sees where they paused.

## Step 1b: Auto-heal orphan mkdir-locks (closes H-6)

EXIT traps in claim.sh / state.sh inc / state.sh dec / state.sh set / requeue.sh
do NOT fire on `kill -9` or power loss. The mkdir-based lock dirs persist as
orphans and every subsequent `state.sh inc/set/dec` then spins for 30s
before failing. `/resume` MUST detect and clear orphan locks BEFORE handing
off to /run.

For each candidate lockdir:
- `<RUN_PATH>/topics/.claim.lock.d`
- `<RUN_PATH>/state.json.lock.d`

Apply the heuristic:

```bash
heal_orphan_lock() {
  local lockdir="$1"
  [[ -d "$lockdir" ]] || return 0    # not held; nothing to do
  # If the lockdir owner wrote a PID file, prefer that.
  local pidfile="$lockdir/holder.pid"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid=$(cat "$pidfile" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "[resume] lock $lockdir held by live PID $pid — leaving alone" >&2
      return 0
    fi
  fi
  # Otherwise fall back on stat-mtime: lockdir older than 30s with no live
  # holder is presumed orphaned (kill -9 / power loss).
  local age_s
  if stat -f '%m' "$lockdir" >/dev/null 2>&1; then
    # macOS / BSD stat
    local mtime; mtime=$(stat -f '%m' "$lockdir")
    age_s=$(( $(date +%s) - mtime ))
  else
    # GNU stat (Linux)
    local mtime; mtime=$(stat -c '%Y' "$lockdir")
    age_s=$(( $(date +%s) - mtime ))
  fi
  if [[ "$age_s" -gt 30 ]]; then
    echo "[resume] orphan lock detected at $lockdir (age=${age_s}s, no live holder) — removing" >&2
    rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir"
    return 0
  fi
  echo "[resume] lock $lockdir is fresh (${age_s}s) — likely a live worker; leaving alone" >&2
  return 0
}
```

Run this on every candidate lockdir before Step 2. The loop is idempotent —
a fresh lock from a live worker is preserved, an old orphan is cleared.
This is what makes `kill -9 <claim-holder> && /ultra-analyzer:resume` clear
the stall instead of hanging forever on the next state.sh inc.

For deeper diagnostics (orphaned in-progress topics, counter drift), the
user should still run `/ultra-analyzer:health [--fix]` explicitly. Resume's
auto-heal is intentionally narrow: it only repairs the mkdir-locks because
those are the ONE failure mode that blocks the very next state.sh call.

## Step 2: Sanity check for in-progress topics
If `.counters.topics_in_progress > 0` AND `current_step == "analyze"`:
- These are topics claimed by a worker that never called release.sh.
- Typically means a terminal was killed mid-worker.
- Offer two options in output:
  1. Move them back to pending/ (for re-execution): `mv <RUN_PATH>/topics/in-progress/*.md <RUN_PATH>/topics/pending/`
  2. Leave them (if workers are genuinely still running in another terminal)

Do NOT auto-move. Ask user.

## Step 3: Invoke /ultra-analyzer:run
Hand off to the run controller. It will pick up from state.current_step.

# Hard rules
- Never force a state change. If state says pre-discover-gate failed, resume does not magically skip it.
- Never auto-requeue in-progress topics without user confirmation — a live worker may still be processing them.
