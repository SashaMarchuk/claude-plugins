---
name: help
description: Show the ultra-analyzer command guide with onboarding flow and per-step recovery. Use when the user doesn't know where to start, is stuck at a step, or wants a command reference.
allowed-tools: Bash, Read
---

# Role
Present a clear, task-oriented help screen. If `$ARGUMENTS` contains a specific step or status, focus on that. Otherwise show the full onboarding + command map.

# Preflight: /ultra plugin must be installed
Before printing the help guide, check whether the `ultra` skill is available in this session. If it is NOT, prepend the halt message from `${CLAUDE_PLUGIN_ROOT}/references/ultra-dep-preflight.md` to the normal help output (or replace it, depending on user context). This catches users who installed `ultra-analyzer` without `ultra` and are reading `help` to figure out what to do. On Claude Code v2.1.110+ the dependency is auto-installed via `plugin.json` `dependencies`, so this preflight is normally a no-op.

# Invocation
  /ultra-analyzer:help [step|command]

Examples:
- `/ultra-analyzer:help` — full reference
- `/ultra-analyzer:help init` — detail on init step
- `/ultra-analyzer:help blocked` — how to unblock a run

# Protocol

## Step 1: Parse argument
If `$ARGUMENTS` is empty → print the full reference below.
If it matches a command name (`init`, `run`, `scan`, etc.) → print that command's help + related commands.
If it matches a state/status (`blocked`, `failed`, `analyze`, etc.) → print recovery guide for that state.

## Step 2: Output the guide

Always include these sections (truncate as needed for focused asks):

### Onboarding — from zero to report

```
1. /ultra-analyzer:scan <path-or-source>   — (optional) quick assessment: is this source worth analyzing?
2. /ultra-analyzer:explore                 — (optional) socratic Q&A to figure out WHAT questions to ask
3. /ultra-analyzer:init <run-name>         — create .planning/ultra-analyzer/<run>/ skeleton
4. Pick a connector:
   a) Copy a template: cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/mongo.md <run>/connector.md
   b) OR generate one: /ultra-analyzer:connector-init <run>
5. Edit <run>/config.yaml   — connection details, budgets, forbidden fields
6. Edit <run>/seeds.md      — hand-authored P1/P2/P3 investigation questions (MANDATORY)
7. /ultra-analyzer:run      — advances state machine, pauses at /ultra Gate 1
8. After Gate 1 PASS:
     open 1-N terminals → bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-terminal.sh <run>
9. /ultra-analyzer:progress — check status anytime
10. When all topics resolved: /ultra-analyzer:run → Gate 2 → synthesize → DONE
11. Read <run>/synthesis/REPORT.md
```

### Command map

**Discovery & setup:**
- `/ultra-analyzer:scan <path>` — assess a source's size/shape before committing
- `/ultra-analyzer:explore` — interactive ideation on what to investigate
- `/ultra-analyzer:init <name> [type]` — create new run
- `/ultra-analyzer:connector-init <run>` — interview → custom connector.md
- `/ultra-analyzer:set-profile <s|m|l|xl>` — scale model choice + gate rigor + worker count

**Execution:**
- `/ultra-analyzer:run [name]` — advance state machine (idempotent)
- `/ultra-analyzer:resume [name]` — show progress + resume
- `/ultra-analyzer:next` — one-step router (reads state, says what to do)

**Monitoring:**
- `/ultra-analyzer:progress [name]` — human-readable state.json dashboard
- `/ultra-analyzer:list-runs` — all runs in this project + statuses

**Recovery:**
- `/ultra-analyzer:health [name]` — diagnose stuck/blocked states, offer fixes
- `/ultra-analyzer:pause [name]` — write handoff doc before switching contexts
- `/ultra-analyzer:help <state>` — per-state recovery guide

### State-by-state recovery

| Step | Status | What to do |
|---|---|---|
| init | pending | Edit `<run>/config.yaml` + `<run>/seeds.md` + `<run>/connector.md`. Then `/ultra-analyzer:run`. |
| pre-discover-gate | pending | `/ultra-analyzer:run` — will invoke /ultra Gate 1 on config + seeds. |
| pre-discover-gate | blocked | Gate 1 FAIL. Read `<run>/validation/gate1-*.md` for remediation. Edit config/seeds. Re-run. |
| discover | running | Wait. Then `/ultra-analyzer:run` to advance. |
| analyze | running | Open N terminals: `bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-terminal.sh <run>`. Use `/ultra-analyzer:progress` to monitor. |
| analyze | blocked | PASS-rate <50%. Inspect `<run>/validation/findings/*.json` for FAIL patterns. Usually means bad connector or bad seeds. |
| pre-synthesize-gate | pending | `/ultra-analyzer:run` — Gate 2 reviews findings corpus. |
| pre-synthesize-gate | blocked | Gate 2 flagged specific findings. Read `<run>/validation/gate2-*.md`. Those topics were requeued; re-run workers. |
| synthesize | running | Wait for Opus synthesis. Can take 2-10 min depending on corpus size. |
| done | passed | Read `<run>/synthesis/REPORT.md`. |
| failed | failed | Inspect `<run>/run.log` tail for last error. Use `/ultra-analyzer:health` for automated diagnosis. |

### Common first-time issues

1. **"seeds.md appears to be template"** → You didn't author your own seeds. Templates are placeholder only. Write 3+ real P1 questions before `run`.
2. **"no connector.md found"** → Copy a template from `${CLAUDE_PLUGIN_ROOT}/templates/connectors/` OR run `/ultra-analyzer:connector-init`.
3. **"claim lock timeout"** → Stale lock dir from a killed worker. Remove: `rmdir <run>/topics/.claim.lock.d`.
4. **"no topics generated"** → Connector's `enumerate` returned empty. Smoke-test it: `bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <run> enumerate`.
5. **Workers exit immediately** → Check `<run>/run.log` — usually missing env var ($MONGO_URI, $API_TOKEN) or connector.md malformed.

### Profile tiers (switch with `/ultra-analyzer:set-profile`)

| Tier | /ultra gate | Worker model | Validator | Topic target | Parallel terminals |
|---|---|---|---|---|---|
| small  | --small  | Haiku  | Haiku  | 15-25   | 1-2  |
| medium | --medium | Sonnet | Haiku  | 25-45   | 2-3  |
| large (default) | --large | Sonnet | Haiku | 45-70 | 3-5 |
| xl     | --xl     | Opus   | Sonnet | 70-120  | 5-10 |

# Hard rules
- NEVER invent commands that don't exist. Only list what's actually shipped in the plugin.
- When user is blocked, the first instruction should be to READ a specific file in their run (report, log, validation output) — not immediately "re-run".
- Keep output scannable — user comes here when confused, not to study a manual.
