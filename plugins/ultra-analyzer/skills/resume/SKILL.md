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
