---
name: help
description: (beta) The claude-migrate command guide: the zero-to-migrated onboarding flow, the full command map, and per-step recovery for a stuck or blocked run. Use when the user types /claude-migrate:help, or says "how do I migrate my Claude account", "where do I start with claude-migrate", "what commands does claude-migrate have", "how do I unblock the migration", "I'm stuck on the migration".
allowed-tools: Read
---

# Role
Present a clear, task-oriented help screen. If `$ARGUMENTS` names a command or a state, focus on that; otherwise show the full onboarding flow plus the command map. List ONLY commands that actually ship in this plugin. The reader is usually confused or blocked - lead them to the single next action.

# Preflight: the `ultra` plugin must be installed
claude-migrate runs its three machine-gates via `/ultra:run`. Before printing the guide, check whether the `ultra` skill is available in this session (it appears in the session's listed skills on Claude Code v2.1.110+, where it auto-installs via this plugin's `plugin.json` `dependencies`). If it is NOT available, Read `${CLAUDE_PLUGIN_ROOT}/references/ultra-dep-preflight.md` and prepend its verbatim halt message to the help output - this catches a user who installed claude-migrate without `ultra` and came to `help` to find out why nothing runs. Otherwise this preflight is a no-op.

# Invocation
  /claude-migrate:help [<command|state>]

Examples:
- `/claude-migrate:help` - full reference
- `/claude-migrate:help init` - detail on the init command
- `/claude-migrate:help blocked` - how to unblock a run
- `/claude-migrate:help apply` - what the apply step does and how to recover

# Protocol

## Step 1: Parse the argument
- Empty -> print the full reference (Step 2).
- Matches a command name (`init, run, resume, confirm, progress, verify, health, config, help`) -> print that command's detail plus its neighbors.
- Matches a step or status (`pre-split-gate, split, preflight, filter-gate, distill, synthesize, build-page, verify-gate, ready, pre-apply-gate, apply, finalize, blocked, failed, done`) -> print the recovery guide for that state.

## Step 2: Output the guide
Include these sections (truncate to the focused ask when one was given).

### What it does (one paragraph)
claude-migrate moves your Claude.ai chats and projects into a NEW Claude account. It parses your data export (or extracts live from the old account), deterministically scores each chat's value, lets you CONFIRM what migrates, distills every kept chat into one paste-ready first message, and re-creates your projects in the new account. It ALWAYS builds a byte-exact, self-contained copy page (the reliable floor, zero tooling). When a pre-authenticated browser is reachable it ALSO runs confirmation-gated automation: seed each chat, wait for the first reply, rename, then strip the onboarding instruction. Everything is a resume-able state machine.

### Onboarding - from zero to migrated
```
1. /claude-migrate:init <run-name>
     Answer G-INPUT  (default: a Claude data export folder - most reliable)
     Answer G-OUTPUT (default: AUTO browser + the copy page; or copy page only).
     init copies the connector/config/selectors templates and scaffolds the run.

2. /claude-migrate:run <run-name>
     Advances the pipeline. It runs /ultra Gate 1 (export readable, counts sane,
     connectors coherent, users.json not copied), parses the source, then scores
     every chat. It BLOCKS at the filter gate and names the next command.

3. Fan out the value scan (when run tells you to):
     open up to <parallelism> terminals and in each run
       bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-worker.sh <run-name-path> preflight
     Watch it drain with /claude-migrate:progress <run-name>.

4. /claude-migrate:confirm <run-name>
     Confirm what migrates: KEEP/REFERENCE/DROP, chat naming, the OK-protocol
     onboarding, account memories (if any), and a deterministic cost estimate.
     You also assign kept chats to projects (grouped) or leave them standalone.

5. Fan out the distill pass (when run tells you to):
       bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-worker.sh <run-name-path> distill
     run then synthesizes per-project instructions and builds the copy page,
     runs /ultra Gate 2 + a headless byte-exact verify, and reaches READY.

6a. Copy-page mode: READY is DONE. Serve the page:
       cd <run-name-path>/out && python3 -m http.server     (open index.html)
6b. AUTO mode: /claude-migrate:confirm <run-name> again to ack the page and log
       into the NEW account, then run advances through /ultra Gate 3 -> apply
       (seed -> await first turn -> rename) -> finalize (swap projects to steady).

Anytime: /claude-migrate:progress  (status)  /claude-migrate:health  (diagnose)
          /claude-migrate:resume    (resume after any interruption)
```

### Command map
Setup:
- `/claude-migrate:init <run-name>` - scaffold a new run; ask G-INPUT + G-OUTPUT; copy templates.
- `/claude-migrate:config [<run-name>] [<area>]` - edit tier, parallelism, thresholds, naming, bucket labels; swap or re-author a connector.

Drive the pipeline:
- `/claude-migrate:run [<run-name>]` - advance the state machine by one step; runs the /ultra machine-gates; BLOCKS (never prompts) at a human gate and names the next command.
- `/claude-migrate:confirm <run-name>` - the interactive gate skill: the filter-gate round + cost, then later the auto re-offer + login/browser gates.
- `/claude-migrate:resume <run-name>` - crash-safe resume: requeue orphans, re-rename seeded-not-renamed, re-poll awaited-OK, re-run any blocked gate, then hand back to run.

Monitor + recover:
- `/claude-migrate:progress [<run-name>] [--verbose]` - read-only status dashboard (step, counters, gate verdicts, next action).
- `/claude-migrate:verify [<run-name>]` - re-run the copy-page gate on demand (headless byte-exact + the cross-model brief==source audit).
- `/claude-migrate:health [<run-name>]` - diagnose stale locks / orphans / counter drift / corrupt state; PROPOSES repairs, never auto-applies.
- `/claude-migrate:help [<command|state>]` - this guide.

(There is no separate worker slash command: the parallel `preflight`/`distill` workers run via `bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-worker.sh <run-path> <step>`. The `source`, `sink`, `extract`, `preflight-value`, `distill-brief`, `synthesize-project`, `build-copy-page`, and `apply-unit` skills are internal - the pipeline invokes them for you.)

### State-by-state recovery
| Step | Status | What to do |
|---|---|---|
| init | pending | Answer G-INPUT/G-OUTPUT in `init`, then `/claude-migrate:run <run>`. |
| pre-split-gate | running | `/claude-migrate:run <run>` - runs /ultra Gate 1. |
| pre-split-gate | blocked | Gate 1 FAIL. Read `<run>/validation/gate1-*.md`; fix config / connectors / source; re-run. |
| split | running | Parsing the source. When done, `/claude-migrate:run <run>`. |
| preflight | running | Open terminals: `bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-worker.sh <run-path> preflight`. Monitor with `/claude-migrate:progress`. |
| filter-gate | blocked | `/claude-migrate:confirm <run>` - confirm KEEP/REFERENCE/DROP, naming, onboarding, memories, cost. |
| distill | running | Open terminals: `bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-worker.sh <run-path> distill`. |
| synthesize | running | Building per-project instructions. Then `/claude-migrate:run <run>`. |
| build-page | running | Assembling the copy page (always built). Then `/claude-migrate:run <run>`. |
| verify-gate | running | `/claude-migrate:run <run>` - /ultra Gate 2 + headless byte-exact verify. |
| verify-gate | blocked | Gate 2 flagged briefs. Read `<run>/validation/gate2-*.md`; those units were requeued; re-run distill workers, then `/claude-migrate:run <run>`. |
| ready | passed | Copy-page mode DONE. `cd <run>/out && python3 -m http.server`, open `index.html`. |
| ready | blocked | AUTO mode: `/claude-migrate:confirm <run>` to ack the page and log into the NEW account. |
| pre-apply-gate | running | `/claude-migrate:run <run>` - /ultra Gate 3 (briefs present, both instruction variants, page verified, browser authed, dest != source account). |
| pre-apply-gate | blocked | Log into the NEW account in the connected browser, then `/claude-migrate:resume <run>`. Login is never scripted. |
| apply | running | Seeding in-session serially. Watch with `/claude-migrate:progress`. If frozen, `/claude-migrate:health <run>`. |
| finalize | running | Swapping each project to steady-state instructions. |
| finalize | blocked | A project failed to swap to steady. Finish the un-stripped list by hand, or `/claude-migrate:resume <run>`. |
| done | passed | Migration complete. Review counts in `/claude-migrate:progress` and the copy page. |
| failed | failed | Read `<run>/run.log` tail, then `/claude-migrate:health <run>` for diagnosis. |

### Common first-time issues
1. "ultra plugin not available" -> claude-migrate depends on `ultra` (auto-installs on Claude Code v2.1.110+). See the halt note above; install `ultra` from the same marketplace and restart your session.
2. "Node / Playwright missing" -> the byte-exact copy-page verify and the browser sink need a local Node + Playwright runtime. See `${CLAUDE_PLUGIN_ROOT}/references/node-playwright-preflight.md`.
3. "claim lock timeout" -> a stale lock dir from a killed worker. Diagnose with `/claude-migrate:health <run>` (it proposes the exact `rmdir`); or just `/claude-migrate:resume <run>`, which auto-heals orphans.
4. "no units after split" -> the source `enumerate` returned empty, or the export path is wrong. Re-check G-INPUT and the source path, then re-run.
5. "run says blocked but nothing prompted me" -> by design `run` never prompts; it BLOCKS and names a command. Run the command it printed (usually `/claude-migrate:confirm <run>` or `/claude-migrate:resume <run>`).
6. "the browser was lost mid-apply" -> the circuit breaker tripped after repeated transport/auth failures. Re-connect/log in, then `/claude-migrate:resume <run>`.

### The two deliverables, the two gates that matter to you
- The copy page is the reliable floor: it is ALWAYS built and byte-exact verified at READY, even if you never use the browser. Declining AUTO leaves the run at READY = success.
- AUTO automation is confirmation-gated: you approve the page (G-AUTO-REOFFER) and log in yourself (G-LOGIN); then seeding and renaming are hands-free.

### Profile tiers (switch with `/claude-migrate:config <run> tier`)
| Tier | /ultra gate | preflight | distill | synth | validator | suggested terminals |
|---|---|---|---|---|---|---|
| small  | --small  | haiku | haiku  | sonnet | sonnet | 1-2 |
| medium | --medium | haiku | sonnet | sonnet | opus   | 2-3 |
| large (default) | --large | haiku | sonnet | opus | opus | 4 |
| xl     | --xl     | haiku | opus   | opus   | sonnet | 5-10 |

# Hard rules
- List ONLY commands and steps that actually ship in this plugin. Never invent a command.
- When the user is blocked, the first instruction is to READ a specific file in their run (the gate report, `run.log`, or `value/`), not to blindly re-run.
- Keep the output scannable. The reader comes here confused, not to study a manual.
- Never reference any specific domain; bucket and group labels come from `config.yaml`, not from this guide.
- Read-only. This skill never mutates a run.
