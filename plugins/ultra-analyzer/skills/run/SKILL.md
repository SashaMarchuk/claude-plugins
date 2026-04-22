---
name: run
description: Advance the analyzer pipeline by one step based on state.json. Runs gates (/ultra) at critical boundaries, pauses for user action when blocked. Idempotent and resume-safe.
allowed-tools: Bash, Read, Write, Skill
---

# Role
Pipeline controller. Reads state.json, determines next step, executes it, updates state. Stops at gates or on error. Never skips steps.

# Invocation
  /ultra-analyzer:run [run-name]

If `run-name` omitted, look for `.planning/ultra-analyzer/<single-run>/` — if exactly one exists, use it; if multiple, error with a list.

# Protocol

## Step 1: Locate run
- Parse run-name from `$ARGUMENTS`.
- If absent: `ls .planning/ultra-analyzer/` — if exactly one dir, use it; else print available runs and exit.
- RUN_PATH = `.planning/ultra-analyzer/<run-name>/`
- Abort if `$RUN_PATH/state.json` missing — tell user to call `/ultra-analyzer:init` first.

## Step 2: Read current state + profile
```bash
CURRENT_STEP=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .current_step)
STATUS=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .status)
ULTRA_TIER=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .profile.ultra_gate_tier)   # e.g. "--large"
SYNTH_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get $RUN_PATH .profile.synthesizer_model) # e.g. "opus"
```
The tier drives gate rigor. User can change mid-run with `/ultra-analyzer:set-profile`.

## Step 3: Dispatch by current_step

### current_step == "init"
- Verify user has edited config.yaml and seeds.md (both must exist AND not equal their templates).
  - Compare `sha256(config.yaml)` against `sha256(templates/config.yaml.template)` — if identical, block with "edit config first".
  - `seeds.md` must have at least one non-comment, non-template line under "## P1 seeds".
- If validation passes, advance `current_step = "pre-discover-gate"` and call this skill recursively (or return and let user re-invoke).

### current_step == "pre-discover-gate"
**This is GATE 1.** Invoke /ultra to validate config + seeds + connector.

**Preflight: verify /ultra is installed.** Before invoking, confirm the `ultra` skill is available. If it is not (Skill tool returns skill-not-found or the skill is not listed in the current session's available skills), HALT with this message and do NOT advance state:

> `ultra-analyzer` requires the `ultra` plugin from the same marketplace. Install it first:
> ```
> /plugin install ultra@SashaMarchuk/claude-plugins
> ```
> Then re-run `/ultra-analyzer:run`.

Gate 1 cannot be bypassed. Failing the preflight sets `status = blocked`.

Use the Skill tool to invoke `ultra` with the tier read from `state.profile.ultra_gate_tier`:
```
args: $ULTRA_TIER --task=analyzer-gate1-<run-name> Review analyzer run bootstrap for soundness. Read: <RUN_PATH>/config.yaml, <RUN_PATH>/seeds.md, <RUN_PATH>/connector.md. Criteria: (1) seeds have sufficient P1/P2/P3 count — not template placeholders; (2) connector.md implements all 6 contract operations with concrete, runnable instructions; (3) connector auth / env-vars are declared (not hardcoded); (4) budget tiers realistic for corpus scale; (5) forbidden_fields / forbidden_patterns are plausible for the source. Produce verdict PASS or FAIL with specific remediation. Write report to <RUN_PATH>/validation/gate1-<timestamp>.md.
```

Parse the /ultra verdict:
- **PASS** → set `state.ultra_gates["pre-discover"].verdict = "PASS"`, checkpoint, advance `current_step = "discover"`, return control to user with "Gate 1 PASS. Run /ultra-analyzer:run again to proceed to discover."
- **FAIL** → set verdict = FAIL, status = blocked, write remediation summary in output. DO NOT advance. User must edit config/seeds and re-run.

### current_step == "discover"
Invoke the discover-topics skill (delegates to the connector for schema sampling).
```
claude --print "/ultra-analyzer:discover-topics <RUN_PATH>"
```
Wait for completion. Verify `topics/pending/` is non-empty and `state.counters.topics_total > 0`. If not, mark status=failed and abort with diagnostic.

If successful, checkpoint, advance `current_step = "analyze"`, and tell user:
```
✓ Discover complete. N topics generated.
Next: open 1-5 terminals and run:
  bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-terminal.sh <RUN_PATH>
Or run /ultra-analyzer:run to start a single-terminal worker inline.
```

### current_step == "analyze"
Two modes:
1. **Inline single-terminal**: invoke `launch-terminal.sh` as a blocking subprocess. User waits.
2. **Multi-terminal**: user already running launch-terminal.sh elsewhere. We poll state counters until all topics resolved.

Default to mode 2 (poll). If `counters.topics_pending + in-progress == 0`, all topics resolved.

When complete: verify `counters.findings_passed / counters.topics_total >= 0.5` as a sanity floor. If below 50%, mark status=blocked — something is systemically wrong, user must investigate.

If healthy, checkpoint, advance `current_step = "pre-synthesize-gate"`.

### current_step == "pre-synthesize-gate"
**This is GATE 2.** Invoke /ultra for findings review before synthesis. Tier from `state.profile.ultra_gate_tier`.

```
args: $ULTRA_TIER --task=analyzer-gate2-<run-name> Review findings corpus before synthesis. Seeds: <RUN_PATH>/seeds.md. Findings: <RUN_PATH>/findings/. Validator verdicts: <RUN_PATH>/validation/findings/. Criteria: (1) coverage vs seeds — did topics drift?; (2) denominator discipline — no bare "% of users" claims without subset qualifier; (3) divergent redundancy pairs flagged not averaged; (4) any PASS finding that should be FAIL. Produce verdict PASS or revise-list. Write to <RUN_PATH>/validation/gate2-<timestamp>.md.
```

- **PASS** → checkpoint, advance `current_step = "synthesize"`.
- **FAIL with revise-list** → for each flagged topic basename, call:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/bin/requeue.sh $RUN_PATH <topic-basename> <reason-slug>
  ```
  This moves the topic from `done/` back to `pending/` with a retry tag, archives the prior findings + verdict under `state/requeue-archive/`, and decrements `counters.topics_done` and `counters.findings_passed` to keep state consistent. Do NOT advance. Set status = blocked. User must re-run workers, then re-run Gate 2.

### current_step == "synthesize"
Invoke with the model declared by the active profile (usually Opus for large/xl, Sonnet for small/medium):
```
claude --plugin-dir ${CLAUDE_PLUGIN_ROOT} --model $SYNTH_MODEL --print "/ultra-analyzer:synthesize-report <RUN_PATH>"
```
Wait. Verify `synthesis/REPORT.md` exists and is non-trivial (>2KB). If ok, checkpoint, advance `current_step = "done"`, status = passed.

### current_step == "done"
Print final summary: path to REPORT.md, counters, timings. Exit cleanly.

### current_step == "failed"
Print last error from run.log. Exit non-zero.

## Step 4: Always checkpoint
After every state transition, run:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh checkpoint $RUN_PATH
```

# Hard rules
- Never skip Gate 1 or Gate 2. Both are mandatory before their respective steps.
- Never advance past a FAIL gate without explicit user action (edit + re-run).
- Never mutate state.json outside of bin/state.sh (or bin/requeue.sh for gate-2 done→pending moves). Concurrent workers write to counters — state.sh uses mkdir-based locking to serialize.
- If any subprocess exits non-zero, set status=failed and persist the error to run.log. Do NOT silently retry at this level (worker-level retries happen in launch-terminal.sh).
