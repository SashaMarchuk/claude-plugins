---
name: config
description: (beta) Edit a migration run's settings between steps - profile tier, worker/seed parallelism, cost and brief thresholds, naming scheme, and the bucket role display labels - and re-author or swap the source/sink connector via a short interview. Writes the authoritative fields through bin/state.sh and mirrors record-only fields into config.yaml. Use when the user types /claude-migrate:config, or says "change the tier", "set parallelism", "raise the cost limit", "rename the buckets", "swap the connector", "use the live source instead of the export".
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Role
Interactively edit one run's configuration. Two surfaces: (1) run-level settings that `state.json` is authoritative for (`profile.*`, parallelism, thresholds, naming) - written through `bin/state.sh` and mirrored into `config.yaml` as a human record; (2) the bucket role display labels and other record-only knobs that live in `config.yaml`; (3) the active SOURCE/SINK connector contract (`source-connector.md` / `sink-connector.md`), which you can swap to a shipped template or re-author via interview. This skill applies changes FORWARD only and refuses edits that would corrupt work already committed (a synthesize/apply already in flight).

# Invocation
  /claude-migrate:config [<run-name>] [<area>]

- `<run-name>` optional. If omitted, auto-detect: list `.planning/claude-migrate/` and if exactly one run dir exists, use it; otherwise print available runs and exit.
- `<area>` optional shortcut: one of `tier | parallelism | thresholds | naming | buckets | source | sink`. If omitted, present the full menu (Step 2).

# Protocol

## Step 1: Locate the run + snapshot current config
- Parse `<run-name>` and the optional `<area>` from `$ARGUMENTS`.
- If `<run-name>` absent: `ls .planning/claude-migrate/` - if exactly one dir, use it; else print available runs and exit.
- `RUN_PATH=".planning/claude-migrate/<run-name>"`.
- If `$RUN_PATH/state.json` is missing, STOP: "No such run. Initialize with `/claude-migrate:init <run-name>` first."
- Read the current values to show the user what they are changing FROM:
```bash
CUR_STEP=$(bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh get "$RUN_PATH" .current_step)
jq '{profile, decisions:{naming_convention:.decisions.naming_convention}, input:.input.mode, output:.output.mode}' "$RUN_PATH/state.json"
sed -n '1,200p' "$RUN_PATH/config.yaml"
```

## Step 2: Pick an area (AskUserQuestion, unless `<area>` was given)
Use AskUserQuestion with header "Which setting do you want to change?" and options:
- Profile tier (model choice + /ultra gate rigor + suggested parallelism)
- Parallelism (worker fan-out; seed pacing)
- Thresholds (cost guardrails + max brief size + copy-page inline limits)
- Naming (how migrated chats are titled)
- Bucket labels (display names for the four roles)
- Source connector (swap or re-author the export/live contract)
- Sink connector (swap or re-author the copy-page/browser contract)

## Step 3: Forward-only safety check (refuse unsafe edits)
Before writing, gate on `CUR_STEP`:
- Tier / models: if `CUR_STEP == "synthesize"` or later (`build-page`, `verify-gate`, `ready`, `pre-apply-gate`, `apply`, `finalize`, `done`), REFUSE a tier change: "synth_model and the gate rigor are already committed for this run; a new tier applies forward only and there is no forward work left to apply it to. Start a new run if you need a different tier."
- Parallelism: safe to change any time the relevant queue has NOT fully drained; it only affects future `launch-worker.sh` terminals. Already-running workers keep the model and count they started with - say so.
- Thresholds: cost guardrails are read at the G-COST gate; refuse to lower `hard_stop_usd` retroactively if `decisions.cost_acknowledged == true` and `CUR_STEP` is past `filter-gate` (the cost was already approved). `max_brief_tokens` / inline limits are safe to change before `distill` / `build-page` respectively; warn if changed after, because existing briefs/pages will not be regenerated unless re-run.
- Naming: safe before `distill`; after `distill` the briefs already hold derived titles, so warn that a change only affects re-distilled units.
- Bucket labels: always safe (display-only).
- Connector swap: REFUSE if `CUR_STEP` is past `split` (units are already extracted under the current source contract; changing the source mid-run would desync the corpus). For sink: refuse a swap once `apply` has started. Before `split`, a swap is free.
If a change is refused, explain why and stop - do NOT partially apply.

## Step 4: Apply the change

### Tier
Validate against the closed enum `{small, medium, large, xl}`; reject others with the valid list. Set the whole `profile` sub-object so downstream skills read it without re-deriving. Per-tier values:

| tier | preflight_model | distill_model | synth_model | validator_model | ultra_gate_tier | parallelism | seed_parallelism |
|---|---|---|---|---|---|---|---|
| small  | haiku | haiku  | sonnet | sonnet | --small  | 1-2 | 1 |
| medium | haiku | sonnet | sonnet | opus   | --medium | 2-3 | 1 |
| large (default) | haiku | sonnet | opus | opus | --large | 4 | 1 |
| xl     | haiku | opus   | opus   | sonnet | --xl     | 5-10 | 1 |

Cross-model rule (runtime-enforced by `verify`): `validator_model != distill_model`. The table satisfies it; if you ever edit the table re-verify it. `seed_parallelism` stays 1 in v0.1.0 regardless of tier (in-session serial apply). Write:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .profile '<full-profile-json-object>'
```

### Parallelism
- `profile.parallelism` (integer >= 1): worker terminals for preflight/distill.
- `profile.seed_delay_ms` (integer >= 0): pacing between seed submissions in browser apply.
- `profile.seed_parallelism`: MUST remain 1 in v0.1.0. If the user asks for more, refuse and explain it is reserved for the future CDP-library path.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .profile.parallelism <N>
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .profile.seed_delay_ms <MS>
```

### Thresholds
State.json profile fields: `max_brief_tokens`, `inline_card_limit`, `inline_byte_limit`, `ok_wait_ms`, `breaker_threshold`, `capture_screenshots`. Cost guardrails (`warn_usd`, `hard_stop_usd`, `warn_chat_count`, `warn_chat_tokens`) live in `config.yaml` under `cost:` and are read at the G-COST gate. If the user turns `capture_screenshots` ON, WARN: per-attempt screenshots may capture PII; they are excluded from git by the run-dir `.gitignore`, and a banner warning fires in `apply`.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .profile.max_brief_tokens <N>
```
Then mirror the cost block into `config.yaml` (Step 5).

### Naming
- `decisions.naming_convention`: `keep` (default; derive a title only when the original name is empty/generic) or `custom:<scheme>`. For custom, drive a structured pick with a prefilled worked example (`Name DD.MM tag`) via AskUserQuestion, then store the resolved scheme string.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .decisions.naming_convention '<keep|custom:SCHEME>'
```

### Bucket labels (display-only)
The four ROLES are a closed enum (`GROUPED | STANDALONE | REFERENCE | DROP`); you may relabel how each is shown but NEVER add or remove a role. Edit the `bucket_labels:` map in `config.yaml` only (the core switches on the role enum, never on the label). Read the current labels, ask for new strings, and write `config.yaml`.

### Source / Sink connector (swap or re-author)
A connector is a markdown CONTRACT (not code) copied into the run dir. Two paths via AskUserQuestion ("Swap to a shipped template, or re-author the current one?"):
1. SWAP to a shipped template - copy it over the run's connector (overwrites the user-editable copy in the run dir, never the shipped template):
   ```bash
   # SOURCE options:  export-file (default) | browser (live)
   cp ${CLAUDE_PLUGIN_ROOT}/templates/sources/export-file.md "$RUN_PATH/source-connector.md"
   # SINK options:    copy-page (the reliable floor) | browser (accelerator)
   cp ${CLAUDE_PLUGIN_ROOT}/templates/sinks/browser.md "$RUN_PATH/sink-connector.md"
   ```
   If the swap changes `input.mode` (export <-> live) or `output.mode` (copy-page <-> auto), update the matching `state.json` field too:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .input.mode '<export|live>'
   bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set "$RUN_PATH" .output.mode '<copy-page|auto>'
   ```
2. RE-AUTHOR via interview - a connector.md MUST implement all 7 ops for its side. Interview the user for each section and Write the file. Required SOURCE sections (§5.1): `enumerate`, `extract_unit`, `extract_projects`, `unit_project_ref`, `account_check`, `citation_anchor`, `forbidden_fields`. Required SINK sections (§5.2): `prepare`, `dedupe_probe`, `create_project`, `seed_unit`, `finalize_unit`, `finalize_run`, `rate_limit_check`. Open the file with the copy-first banner and, for browser/live sources, the mandatory secret-strip note. Never hardcode a secret in a connector - reference an env var. After re-authoring, advise re-running `/claude-migrate:run` so /ultra Gate 1 re-validates the new contract.

## Step 5: Mirror record-only fields + confirm
For any state.json field that also appears in `config.yaml` (tier, parallelism, thresholds, naming, cost block, bucket_labels), update the `config.yaml` copy so the human record stays consistent (state.json remains authoritative for the fields it tracks). Then print a confirmation:
```
Config updated for run <run>:
  <field>: <old> -> <new>
  ...
Effect: applies on the NEXT step. Already-running workers keep their started settings.
Next action: /claude-migrate:run <run>   (or /claude-migrate:progress <run> to review)
```

# Hard rules
- Forward-only. NEVER alter completed work or apply a tier/model change once `synthesize` has committed it. Refuse with a clear reason rather than corrupting state.
- All `state.json` mutations go through `bin/state.sh` (locked, atomic, injection-defended). NEVER hand-edit `state.json`.
- `config.yaml` is a human record for the fields `state.json` also tracks; on conflict `state.json` wins. Keep them consistent after every change.
- The four bucket ROLES are a closed enum. You may relabel them in `config.yaml`; you may NEVER add or remove a role.
- `seed_parallelism` stays 1 in v0.1.0. Refuse any higher value.
- A re-authored connector MUST implement all 7 ops for its side and MUST NOT hardcode a secret (reference env vars). Browser/live sources MUST keep the mandatory secret-strip note.
- Never reference any specific domain in defaults, examples, or labels; use neutral placeholders (`Project Alpha`, `topic-1`).
