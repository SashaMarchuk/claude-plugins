---
name: confirm
description: (beta) The interactive gate skill you run whenever the migration controller BLOCKS for a human decision. Runs the right gate round for the current blocked_reason - the filter-gate round (what migrates, naming, onboarding, memories, project grouping) plus the cost estimate, or the auto-reoffer + login/browser checks before browser seeding - then persists your answers, clears the block, and hands back to the controller. Use when the user types /claude-migrate:confirm, or says "confirm what migrates", "approve the migration", "run the browser accelerator".
allowed-tools: Bash, Read, Write, Skill, AskUserQuestion
---

# Role
The single home for every interactive user gate. The `run` controller never prompts - it BLOCKS with `status=blocked` + `blocked_reason` and hands the user here. `confirm` reads `blocked_reason`, runs exactly the matching AskUserQuestion round, persists each answer into `state.decisions` (sticky - never re-asked on resume), clears the block, advances `current_step`, and re-invokes `run` via the Skill tool. It owns: the filter-gate round (G-FILTER, G-NAMING, G-ONBOARD, G-MEMORIES) + GROUPED-vs-STANDALONE assignment + G-COST; and the browser-accelerator round (G-AUTO-REOFFER, G-LOGIN/G-BROWSER).

# Preflight: there must be a block to clear
Read `state.status` and `state.blocked_reason`. If `status != blocked`, print "Nothing to confirm - run `/claude-migrate:run <run-name>` to advance, or `/claude-migrate:progress <run-name>` to see where you are." and exit without asking anything. Decisions already present in `state.decisions` are STICKY - never re-ask them.

# Invocation
  /claude-migrate:confirm <run-name>

`<run-name>` is required. `RUN_PATH=".planning/claude-migrate/<run-name>"`. Abort if `state.json` is missing.

# Protocol

## Step 1: Read the block + state
```bash
STATUS=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get "$RUN_PATH" .status)
REASON=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get "$RUN_PATH" .blocked_reason)
OUT_MODE=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get "$RUN_PATH" .output.mode)
```
Dispatch by `REASON`:
- `filter-gate` → Step 2 (the filter-gate round + G-COST).
- `auto-reoffer` → Step 3 (G-AUTO-REOFFER, then login/browser).
- `login` or `browser-lost` → Step 4 (G-LOGIN/G-BROWSER only).
- `cost` → Step 2c (G-COST only, then re-evaluate).
- anything else → print "This block is not a user gate - see `/claude-migrate:health <run-name>`." and exit.

## Step 2: The filter-gate round  (blocked_reason == "filter-gate")
Run these in order. Each is one AskUserQuestion call; each answer is persisted via `state.sh set .decisions.<key>`.

### 2a. G-FILTER - what migrates (one summary question; per-item legend loop on demand)
First read the preflight scores to build the summary: count KEEP + REFERENCE vs DROP from `value/*.json`, and surface any duplicate clusters (representative = lowest idx). Ask ONE summary question. Header: **"Confirm what migrates"**, body: "Migrate N (KEEP/REFERENCE), skip M (DROP: empty / starter project / tool-only / near-duplicate)?"
- Option A (DEFAULT): **Accept recommended** - keep the scored KEEP/REFERENCE, drop the DROP set.
- Option B: **Review per-item** - enter the per-item legend loop: for EACH item, print the FULL legend (UNNN, name, bucket, value, confidence, reason, any `looks_duplicate_of`) BEFORE its AskUserQuestion call (not batched). Duplicate clusters are SURFACED for an explicit keep/drop pick - NEVER auto-dropped. An empty-body-but-meaningful-name chat is a low-confidence KEEP candidate (M-6).

Apply the decision: move DROP units to `units/dropped/` (never delete the source); KEEP/REFERENCE units stay in the queue. Update `counters.kept` / `counters.dropped` via `state.sh inc/dec` so the §3.3 invariants hold.

### 2b. GROUPED-vs-STANDALONE assignment (C2 - explicit, never re-derived)
For each KEEP/REFERENCE unit, ask whether it joins a destination project (GROUPED) or stays a standalone chat (DEFAULT = STANDALONE). Present the available `PNN__slug` projects (from `project/`). Persist the user-confirmed map:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" '.decisions.project_assignment."UNNN"' '"PNN__slug"'   # GROUPED
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" '.decisions.project_assignment."UNNN"' null               # STANDALONE
```
This map is the SOLE authority for grouping - `preflight-value` may not emit GROUPED, and resume never re-derives it.

### 2c. G-NAMING - how migrated chats are named  [default keep]
Header: **"How should migrated chats be named?"**
- Option A (DEFAULT): **Keep original** - derive a title only when a name is empty/generic.
- Option B: **Custom (date + disambiguator)** - a structured pick with a prefilled worked example `Name DD.MM tag` (UX M-4). Store the scheme string in `config.yaml` and set:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .decisions.naming_convention '"keep"'            # or "custom:<scheme>"
```

### 2d. G-ONBOARD - OK-protocol onboarding  [default ok-then-strip]
Header: **"Use the OK-protocol onboarding (reply `OK` to each brief, then auto-remove that line after seeding)?"**
- Option A (DEFAULT): **ok-then-strip** - emit BOTH instruction variants (migration + steady).
- Option B: **I'll strip it myself**.
- Option C: **No OK-protocol**.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .decisions.onboarding_ok_protocol '"ok-then-strip"'  # | strip-myself | none
```

### 2e. G-MEMORIES - only if memories.json exists  [default skip]
Skip this question entirely unless `$RUN_PATH/source/memories.json` exists. If it does, header: **"Migrate account memory? (may contain stale or third-party PII)"**
- Option A (DEFAULT): **Skip**.
- Option B: **Paste to new-account memory** (redact + size-check + preview first - Edge M-2, `references/pii-policy.md`).
- Option C: **Fold into a project** (same redact + size-check + preview).
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .decisions.memories '"skip"'  # | paste-to-memory | fold-into-project
```

### 2f. G-COST - deterministic cost estimate, BEFORE distill, BOTH modes (UX H-4)
The estimate is driven by the DETERMINISTIC `est_tokens` already in `value/*.json` (computed by the parser; never by a model). Compute `cost_estimate` (a pure function of the parsed units + active profile) and read `usd_high`, `chats_total`, and the max per-chat `est_tokens`. Show the gate ONLY if `usd_high >= 10` OR `chats_total > 75` OR any chat `est_tokens > 80000`; below all thresholds, silently proceed (set `cost_acknowledged=true`).

When shown: "Estimated $X (in-tokens Y) to distill N chats. Proceed?"
- `> $25` → HARD-STOP requiring an explicit Proceed.
- `> 75 chats` → note "long run -> resumable batches".
- `> 80k-token chat` → note it will be summarized at distill.
Browser seeding itself is $0 API (it consumes the destination message cap - noted later at pre-apply). On Proceed:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .decisions.cost_acknowledged true
```

### 2g. Persist + clear the block + hand to run
Mark the filter gate confirmed, advance, clear the block, hand off:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" '.gates.filter.user_confirmed' true
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" '.gates.filter.verdict' '"PASS"'
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .current_step distill
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .blocked_reason null
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .status running
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh checkpoint "$RUN_PATH"
```
Then invoke skill `claude-migrate:run` with argument `<run-name>` via the Skill tool. `run` advances distill -> synthesize -> build-page -> verify-gate -> ready.

## Step 3: The browser-accelerator round  (blocked_reason == "auto-reoffer")
Only reached when `output.mode == "auto"` and the run is at `ready`.

### 3a. G-AUTO-REOFFER - mandatory "looks right" ack (UX M-5)
Show the `out/index.html` path and 1-2 sample brief titles from `briefs/*.name.txt`. Ask for an explicit acknowledgement. Header: **"The copy page is verified. Proceed with browser seeding?"**
- Option A (DEFAULT): **Looks right, proceed** - sets the ack.
- Option B: **Not yet** - leave at `ready` (the copy page is already a complete success); exit without advancing.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .decisions.auto_reoffer_ack true
```

### 3b. Login + browser probe (G-LOGIN / G-BROWSER)
Probe the browser transport + auth marker:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/browser-probe.sh "$RUN_PATH"
```
Read `state.output.browser.authed` and `.transport`. Follow `${CLAUDE_PLUGIN_ROOT}/references/login-policy.md` verbatim - NEVER script credentials, 2FA, or captcha.
- **Authed** → continue to 3c.
- **Not authed / no transport** → apply the demote rules (UX H-3):
  - `user_chose_auto == false` (Enter-on-default AUTO) AND no browser → DEMOTE to copy-page and SAY SO: set `output.mode=copy-page`, print the macOS CDP launch command from the probe + "the copy page at `out/index.html` is your complete deliverable; to enable automation later, launch the browser and run `/claude-migrate:resume <run-name>`." Set `status=passed`, leave `current_step=ready`, exit.
  - `user_chose_auto == true` (explicitly chose AUTO) AND no browser → do NOT demote: `status=blocked` + `blocked_reason=login`, print the CDP launch command + "log into the NEW account, then `/claude-migrate:resume <run-name>`." Exit.

### 3c. Clear + advance + hand to run
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .current_step pre-apply-gate
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .blocked_reason null
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .status running
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh checkpoint "$RUN_PATH"
```
Invoke skill `claude-migrate:run` with argument `<run-name>` via the Skill tool. `run` runs GATE 3 (incl. `dest_hash != source_hash`) then apply -> finalize -> done.

## Step 4: Login / browser-lost only  (blocked_reason in {"login","browser-lost"})
Re-probe (Step 3b). If now authed, clear `blocked_reason`, set `status=running`, and hand to `run` (it resumes from `pre-apply-gate` or `apply`). If still not authed, re-print the login-policy halt + CDP launch command and exit (do NOT script login).

# Hard rules
- Print the FULL legend per item before each per-item AskUserQuestion call in the G-FILTER review loop - never batch the legend across items.
- GROUPED-vs-STANDALONE is captured here as an EXPLICIT user choice into `decisions.project_assignment` and is NEVER re-derived on resume.
- G-COST fires BEFORE distill in BOTH modes, driven by deterministic `est_tokens` only - never by a model score. `> $25` is a HARD-STOP needing explicit Proceed.
- G-OUTPUT phantom "both" is forbidden; the only two output modes are `auto` and `copy-page`.
- Never script login / 2FA / captcha - detect, block, ask, resume (`references/login-policy.md`).
- Never demote silently: Enter-on-default + no browser demotes WITH a message; explicit-AUTO + no browser blocks (no demote).
- Every answer is sticky in `state.decisions` and is never re-asked on resume.
- Always clear `blocked_reason` and set `status=running` before handing to `run`; never advance the pipeline yourself beyond the one step the gate unlocks.
- Never mutate `state.json` outside `bin/state.sh`. Never reference any specific domain; labels come from `config.yaml`.
