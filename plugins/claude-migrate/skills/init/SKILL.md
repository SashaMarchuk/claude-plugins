---
name: init
description: (beta) Bootstrap a new Claude-to-Claude migration run. Scaffolds .planning/claude-migrate/<run>/ with state.json, copies the source/sink connector + selectors + config templates, asks where your data comes from (G-INPUT) and how to apply it to the new account (G-OUTPUT), then hands the pipeline to the run controller. Use when the user types /claude-migrate:init, or says "migrate my Claude chats", "move my Claude account", "start a Claude migration".
allowed-tools: Bash, Read, Write, Skill, AskUserQuestion
---

# Role
Entry point for a migration. Runs ONCE per run. This skill is pure bootstrap plus the two `init`-owned user gates (G-INPUT, G-OUTPUT). It scaffolds the run directory via `bin/state.sh init`, copies the shipped connector/selectors/config/instruction templates into the run dir, records the two answers into `state.decisions`/`state.input`/`state.output`, then hands control to the `run` controller via the Skill tool. It never advances the pipeline past `init` itself - `run` owns every step transition.

# Preflight: dependencies must be present
Before any work:
1. **`ultra` plugin** - confirm the `ultra` skill is available in this session. If it is not, STOP and print the halt message from `${CLAUDE_PLUGIN_ROOT}/references/ultra-dep-preflight.md` verbatim. Do NOT create files or edit state - set nothing, advance nothing. On Claude Code v2.1.110+ the dependency auto-installs via `plugin.json` `dependencies`, so this is normally a no-op; it is a safety net for older Claude Code and `--plugin-dir` dev loads.
2. **Node + Playwright** - confirm a local Node runtime and Playwright are reachable (needed for byte-exact copy-page verification and, optionally, browser automation). If either is missing, print the halt message from `${CLAUDE_PLUGIN_ROOT}/references/node-playwright-preflight.md` verbatim and STOP without scaffolding.

Both halts are belt-and-suspenders: it is far cheaper to halt here than after the user has invested time editing config and connectors.

# Invocation
  /claude-migrate:init [<run-name>]

Where `<run-name>` is a slug matching `^[A-Za-z0-9_-]+$` (e.g. `old-to-new-2026`). If omitted, derive a default slug from the date (e.g. `migration-2026-06-02`) and confirm it with the user before scaffolding.

# Protocol

## Step 1: Validate arguments
- Parse the first token of `$ARGUMENTS` as the run-name.
- If empty, propose a date-based default (`migration-YYYY-MM-DD`).
- The run-name MUST match `^[A-Za-z0-9_-]+$`. If it does not, print usage and exit - `state.sh` enforces the same allowlist and would reject it anyway (path-traversal defense).

## Step 2: Scaffold run directory + state.json
Create the full run-dir tree and the §3.2 `state.json` schema in one call:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh init <run-name>
```
This writes `.planning/claude-migrate/<run-name>/` with `state.json` (`status=pending`, `current_step=init`, default profile tier `large`, all counters zeroed), the work-queue tree (`units/{pending,in-progress,done,failed,dropped}/`, `value/`, `briefs/`, `project/`, `seed/{pending,in-progress,done,failed}/`, `apply/`, `out/payloads/`, `validation/`, `checkpoints/`, `state/requeue-archive/`), and the run-dir `.gitignore` (§3.8). If `state.sh` exits code 2 (run already exists), STOP with: "Run `<run-name>` already exists - pick a different name or delete the existing run dir, then resume with `/claude-migrate:resume <run-name>`."

Capture the printed run path:
```bash
RUN_PATH=".planning/claude-migrate/<run-name>"
```

## Step 3: Copy shipped templates into the run dir
Copy the static templates the pipeline reads. These are copied (never symlinked) so a `/plugin update` cannot wipe a user's in-run edits:
```bash
cp ${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template      "$RUN_PATH/config.yaml"
cp ${CLAUDE_PLUGIN_ROOT}/templates/selectors.json.template   "$RUN_PATH/selectors.json"
```
Substitute `{{RUN_NAME}}` with the run name in both copies (Read the file, replace, Write back). Do NOT copy a connector yet - that depends on G-INPUT / G-OUTPUT below.

## Step 4: G-INPUT - where is the source? (AskUserQuestion)
Ask exactly one question. Header: **"Where is your source?"**
- Option A (DEFAULT): **Claude data export folder** - "Most reliable. Point me at an unzipped Claude.ai data export (Settings -> Privacy -> Export data)." Sets `input.mode = "export"`.
- Option B: **Extract live from the OLD account** - "Read your old account directly through a pre-authenticated browser; preferred path still triggers the official export ZIP." Sets `input.mode = "live"`.

Persist the choice:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .input.mode <export|live>
```
If the user chose **export**, ask for the absolute path to the unzipped export folder and store it:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .input.export_path "<abs-path>"
```
Then stage the source landing dir WITHOUT copying `users.json` (PII - see `${CLAUDE_PLUGIN_ROOT}/references/pii-policy.md`): copy `conversations.json`, `projects/`, and `memories.json` (if present) into `$RUN_PATH/source/`. `users.json` is read for an account-hash sanity check ONLY by the parser and is never copied, written, or logged.

Now copy the matching SOURCE connector template (copy-first; the user may edit it):
```bash
# export mode:
cp ${CLAUDE_PLUGIN_ROOT}/templates/sources/export-file.md "$RUN_PATH/source-connector.md"
# live mode:
cp ${CLAUDE_PLUGIN_ROOT}/templates/sources/browser.md      "$RUN_PATH/source-connector.md"
```

## Step 5: G-OUTPUT - how to apply to the NEW account? (AskUserQuestion)
Ask exactly one question with **exactly two** options (no `both` value - UX H-2). Header: **"How should I apply the migration to the NEW account?"**
- Option A (DEFAULT): **AUTO browser** - "Seed and rename the chats for you in a pre-authenticated browser, and ALWAYS also produce the byte-exact copy page as the dependable floor." Sets `output.mode = "auto"`.
- Option B: **Copy page only** - "I'll migrate by hand from a byte-exact, self-contained copy page; no browser automation." Sets `output.mode = "copy-page"`.

Persist the mode AND the active-choice flag (UX H-3 - `user_chose_auto=true` ONLY when AUTO was ACTIVELY selected, never on Enter-on-default):
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .output.mode <auto|copy-page>
# only if the user actively selected AUTO (not Enter-on-default):
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .output.user_chose_auto true
```
Copy the matching SINK connector template (the copy-page sink is ALWAYS the reliable floor and is referenced in both modes):
```bash
cp ${CLAUDE_PLUGIN_ROOT}/templates/sinks/copy-page.md "$RUN_PATH/sink-connector.md"   # copy-page mode
cp ${CLAUDE_PLUGIN_ROOT}/templates/sinks/browser.md   "$RUN_PATH/sink-connector.md"   # auto mode
```
Also copy the two project-instruction templates the synthesize step will consume:
```bash
cp ${CLAUDE_PLUGIN_ROOT}/templates/instructions/project-instructions-migration.md "$RUN_PATH/.tmpl-instructions-migration.md"
cp ${CLAUDE_PLUGIN_ROOT}/templates/instructions/project-instructions-steady.md    "$RUN_PATH/.tmpl-instructions-steady.md"
```

## Step 6: Checkpoint
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh checkpoint "$RUN_PATH"
```

## Step 7: Hand off to the run controller
G-INPUT and G-OUTPUT are the only user gates `init` owns. Every later gate is owned by `confirm`, and every step transition is owned by `run`. Invoke the `run` controller via the **Skill tool** (it carries `user-invocable: false`; the Skill tool may invoke it - ultra precedent), passing the run name verbatim:

> Invoke skill `claude-migrate:run` with argument `<run-name>`.

`run` will drive `pre-split-gate` (/ultra GATE 1), `split`, and `preflight`, then BLOCK at `filter-gate` and print "run `/claude-migrate:confirm <run-name>`". Print a concise summary to the user before handing off:
```
Initialized run: <run-name>
  Location: .planning/claude-migrate/<run-name>/
  Source:   <export | live>
  Output:   <AUTO browser + copy page | copy page only>
Handing off to the controller; you will be asked to confirm what migrates shortly.
```

# Hard rules
- Never copy `users.json` into the run dir, write it, or log its contents - read it for the account-hash sanity check only (PII; `references/pii-policy.md`).
- Never auto-advance the pipeline past `init`; `run` owns all step transitions. `init` only scaffolds, asks G-INPUT/G-OUTPUT, and hands off.
- Never overwrite an existing run - `state.sh init` exit 2 means STOP and tell the user to pick another name or resume.
- Never mutate `state.json` outside `bin/state.sh`.
- Set `output.user_chose_auto = true` ONLY when AUTO was actively chosen, never on Enter-on-default (the demote rules at G-OUTPUT depend on this distinction).
- Never reference any specific domain in prompts, defaults, or examples; bucket/group labels come from `config.yaml`, not hardcoded.
