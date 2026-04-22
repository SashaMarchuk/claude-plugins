---
name: init
description: Bootstrap a new analyzer run. Creates .planning/ultra-analyzer/<run-name>/ with state.json, config template, and seeds template. Use when starting a new analysis of ANY corpus (Mongo, filesystem, HTTP API, browser, SQLite, JSONL, etc.).
allowed-tools: Bash, Read, Write
---

# Role
Initialize a new analyzer run. Runs ONCE per analysis. No pipeline execution here — this is pure bootstrap. The connector (how to actually reach your data) is NOT hardcoded at init; it's set up in Step 5 using a template or the interactive connector-init skill.

# Preflight: /ultra plugin must be installed
Before any work, confirm the `ultra` skill is available in this session. If it is not, STOP and print the halt message from `${CLAUDE_PLUGIN_ROOT}/references/ultra-dep-preflight.md` verbatim — do NOT create files or edit state. This prevents the user from investing 5–15 min editing `config.yaml` / `seeds.md` only to hit the Gate 1 halt later. On Claude Code v2.1.110+ the dependency is auto-installed via `plugin.json` `dependencies`, so this preflight is normally a no-op.

# Invocation
  /ultra-analyzer:init <run-name> [connector-hint]

Where:
- `run-name` is a slug (e.g. `coaching-q2`, `security-audit-2026`, `repo-docs-audit`)
- `connector-hint` is an OPTIONAL free-form label (e.g. `mongo`, `fs`, `github-api`, `custom`). Default: `custom`. Informational only — used for display. Actual routing is determined by the `connector.md` you'll create in Step 5.

# Protocol

## Step 1: Validate arguments
- `$ARGUMENTS` must contain at least a run-name. Parse first token as run-name, second (if present) as connector-hint.
- If run-name is empty → print usage and exit.
- Default connector-hint: `custom`.

## Step 2: Bootstrap directory + state
Run:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh init <run-name> <connector-hint>
```
This creates `.planning/ultra-analyzer/<run-name>/` with:
- `state.json` — status=pending, current_step=init, profile=large (default)
- `topics/{pending,in-progress,done,failed}/`
- `findings/`, `validation/findings/`, `synthesis/`, `checkpoints/`, `state/`

If state.sh exits code 2 (run already exists), abort with a clear message: use a different run-name or delete the existing run.

## Step 3: Write config.yaml template
Copy `${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template` to `.planning/ultra-analyzer/<run-name>/config.yaml`. Substitute `{{RUN_NAME}}` with the run name.

## Step 4: Write seeds.md template
Copy `${CLAUDE_PLUGIN_ROOT}/templates/seeds.md.template` to `.planning/ultra-analyzer/<run-name>/seeds.md`. Substitute `{{RUN_NAME}}`.

## Step 5: Connector bootstrap (present options, do NOT write connector.md automatically)
Do NOT copy a connector template without user direction — guessing wrong wastes time.

Print the options:

```
Choose a connector setup path:

A) Copy a shipped template (edit it for your exact source):
     cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/mongo.md      <run>/connector.md
     cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/fs.md         <run>/connector.md
     cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/http-api.md   <run>/connector.md
     cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/browser.md    <run>/connector.md
     cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/sqlite.md     <run>/connector.md
     cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/jsonl.md      <run>/connector.md

B) Interactive interview → generate custom connector.md:
     /ultra-analyzer:connector-init .planning/ultra-analyzer/<run-name>

C) Write connector.md from scratch (see docs/EXTENDING-SOURCES.md for the contract):
     touch <run>/connector.md  # then fill in the 6 operations
```

If the user already passed a matching `connector-hint` AND a template of that exact name exists → offer to auto-copy with their confirmation.

## Step 6: Print next steps

```
✓ Initialized run: <run-name>
  Location: .planning/ultra-analyzer/<run-name>/
  Connector hint: <connector-hint>
  Profile: large (default — change with /ultra-analyzer:set-profile)

NEXT STEPS:
  1. Choose connector (Step 5 options above).
  2. Edit .planning/ultra-analyzer/<run-name>/config.yaml
     — run stakeholder, primary_question, budgets, coverage
  3. Edit .planning/ultra-analyzer/<run-name>/seeds.md
     — author domain-specific P1/P2/P3 investigation seeds.
     This is THE magic ingredient. Without it the pipeline cannot produce sharp findings.
     Need help deciding what to ask? Run: /ultra-analyzer:explore <run-name>
  4. Run: /ultra-analyzer:run
     — advances to pre-discover /ultra gate on config + seeds + connector
```

## Step 7: Exit
Do NOT advance the pipeline. User must complete Steps 1-3 above, then explicitly call `/ultra-analyzer:run`.

# Hard rules
- Never auto-generate seeds from scratch. Seeds require hand-authored domain knowledge — Gate 1 (pre-discover) refuses runs with empty or template-only seeds.
- Never auto-pick a connector template without user confirmation. Guessing = silent wrong data for the whole pipeline.
- Never overwrite an existing run. User must choose a different name or manually delete.
- Never skip creating the `state/` subdirectory — downstream skills (discover-topics) write schemas.json there.
