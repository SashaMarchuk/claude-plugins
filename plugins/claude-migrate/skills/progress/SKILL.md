---
name: progress
description: (beta) Read-only status dashboard for a migration run. Reads state.json plus the queue dirs and prints the current pipeline step, counters, gate verdicts, and the single next action. Never mutates anything. Use when the user types /claude-migrate:progress, or says "where is my migration", "status of the migration run", "what step am I on", "how many chats are done".
allowed-tools: Bash, Read
---

# Role
Read-only. Render `state.json` plus a live scan of the work-queue directories into a compact, scannable status block, then state the single next action. This skill NEVER writes to `state.json`, the queue dirs, or anything else. It is safe to run at any moment, including mid-wave while workers are claiming units.

# Invocation
  /claude-migrate:progress [<run-name>] [--verbose]

- `<run-name>` optional. If omitted, auto-detect: list `.planning/claude-migrate/` and if exactly one run dir exists, use it; otherwise print the available runs and exit.
- `--verbose` adds the optional detail block (Step 5).

# Protocol

## Step 1: Locate the run
- Parse `<run-name>` from `$ARGUMENTS` (the first token that is not a flag).
- If absent: `ls .planning/claude-migrate/` - if exactly one dir, use it; else print the available runs and exit.
- `RUN_PATH=".planning/claude-migrate/<run-name>"`.
- If `$RUN_PATH/state.json` is missing, STOP: "No such run. Initialize with `/claude-migrate:init <run-name>` first, or list runs with `ls .planning/claude-migrate/`."

## Step 2: Read state
```bash
jq . "$RUN_PATH/state.json"
```
Pull the fields you will render: `run`, `created_at`, `updated_at`, `current_step`, `status`, `blocked_reason`, `input.mode`, `output.mode`, `output.user_chose_auto`, `output.browser.transport`, `output.browser.authed`, the four `gates.*.verdict` (and `gates.filter.user_confirmed`), every `counters.*`, `cost_estimate`, and `last_checkpoint`.

## Step 3: Cross-check counters against the filesystem (read-only)
The directory a unit lives in IS its state, so a quick scan corroborates the counters without trusting them blindly. Count, do not move:
```bash
for q in pending in-progress done failed dropped; do
  printf 'units/%-12s %s\n' "$q" "$(ls "$RUN_PATH/units/$q" 2>/dev/null | wc -l | tr -d ' ')"
done
for q in pending in-progress done failed; do
  printf 'seed/%-12s %s\n' "$q" "$(ls "$RUN_PATH/seed/$q" 2>/dev/null | wc -l | tr -d ' ')"
done
ls "$RUN_PATH/briefs"/*.brief.md 2>/dev/null | wc -l   # distilled briefs on disk
```
If a filesystem count disagrees with the matching counter in `state.json`, note it as a one-line "counter drift" hint and point the user at `/claude-migrate:health` (which is the skill that diagnoses and proposes a repair). Do NOT attempt to reconcile here.

## Step 4: Format output
```
claude-migrate run: <run>
  created: <created_at>    updated: <updated_at>
  input:   <input.mode>    output: <output.mode> (user_chose_auto=<bool>)
  browser: transport=<transport|none>  authed=<bool>
  status:  <status>        step: <current_step>   <blocked_reason if status==blocked>

Gates:
  pre-split: <verdict>      filter: <verdict> (user_confirmed=<bool>)
  verify:    <verdict>      pre-apply: <verdict>

Counters:
  chats     total=<chats_total>  kept=<kept>  dropped=<dropped>
  preflight pending=<P> in-progress=<IP> done=<D> failed=<F>
  distill   pending=<P> in-progress=<IP> done=<D> failed=<F>   (briefs ok=<briefs_verified_ok> fail=<briefs_verified_fail>)
  routing   seeded_units=<S>  doc_only_units=<DO>              (kept == seeded_units + doc_only_units)
  seed      pending=<P> in-progress=<IP> done=<D> failed=<F>   seeded=<seeded> renamed=<renamed> ok_protocol_miss=<M>
  projects  total=<T> pending=<P> created=<C> finalized=<Fz>

Cost estimate: in=<in_tokens> out_est=<out_tokens_est>  $<usd_low>-$<usd_high>  (blend=<model_blend|n/a>)
Filesystem cross-check: <"matches counters" | "DRIFT: <one-line> - run /claude-migrate:health">
Last checkpoint: <last_checkpoint|none>

Next action:
  <step-specific guidance - see the table below>
```
Show only the queues that apply to the run: the `seed`/`projects` lines and the browser line are meaningful only when `output.mode == "auto"`; for `copy-page` mode print "(copy-page mode - no browser seeding)" in their place.

## Next-action guidance by current_step + status

| current_step | status | next action line |
|---|---|---|
| init | pending | Answer G-INPUT/G-OUTPUT in init if not done; otherwise `/claude-migrate:run <run>`. |
| pre-split-gate | running/pending | `/claude-migrate:run <run>` - it invokes /ultra Gate 1 (export readable, counts sane, connectors coherent, users.json not copied). |
| pre-split-gate | blocked | Gate 1 FAIL. Read `<RUN_PATH>/validation/gate1-*.md`, fix config/connectors/source, then `/claude-migrate:run <run>`. |
| split | running | Parsing the source. When done, `/claude-migrate:run <run>` advances to preflight. |
| preflight | running | Open up to `profile.parallelism` terminals: `bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-worker.sh <RUN_PATH> preflight`. Re-run progress to watch the queue drain. |
| filter-gate | blocked | Confirm what migrates: `/claude-migrate:confirm <run>` (KEEP/REFERENCE/DROP split, naming, onboarding, memories, cost). |
| distill | running | Open terminals: `bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-worker.sh <RUN_PATH> distill`. Watch distill counters drain. |
| synthesize | running | Building per-project instructions. Then `/claude-migrate:run <run>`. |
| build-page | running | Assembling the copy page. Then `/claude-migrate:run <run>`. |
| verify-gate | running/pending | `/claude-migrate:run <run>` - it runs /ultra Gate 2 plus the headless byte-exact copy-page verify. |
| verify-gate | blocked | Gate 2 flagged briefs. Read `<RUN_PATH>/validation/gate2-*.md`; those UNNN were requeued; re-run distill workers, then `/claude-migrate:run <run>`. |
| ready | passed | Copy-page mode is DONE. Serve it: `cd <RUN_PATH>/out && python3 -m http.server`, open `index.html`. |
| ready | blocked (auto-reoffer) | Auto mode: `/claude-migrate:confirm <run>` to ack the copy page and connect/log into the NEW account, then seed hands-free. |
| pre-apply-gate | running/pending | `/claude-migrate:run <run>` - it runs /ultra Gate 3 (briefs present, both instruction variants, copy page verified, browser authed, dest_hash != source_hash, acks set). |
| pre-apply-gate | blocked (login/browser-lost) | Log into the NEW account in the connected browser, then `/claude-migrate:resume <run>`. Never script login. |
| apply | running | Seeding in-session serially (paced by `seed_delay_ms`). Re-run progress to watch the seed queue. If it stalls, `/claude-migrate:health <run>`. |
| finalize | running | Swapping each project to steady-state instructions. |
| finalize | blocked | A project failed to swap to steady. Read the un-stripped list; finish by hand or `/claude-migrate:resume <run>`. Never reach done with a project in migration mode. |
| done | passed | Migration complete. Review the seeded/renamed/ok_protocol_miss counts above and the copy page. |
| failed | failed | Inspect `<RUN_PATH>/run.log` tail. Then `/claude-migrate:health <run>` for a diagnosis. |

If `counters.kept == 0` at `ready`/`done`, replace the next-action line with the prominent Edge-case message: "0 chats kept - nothing to migrate. Review the DROP list in `<RUN_PATH>/units/dropped/` and the per-unit reasons in `<RUN_PATH>/value/`." Never present an empty run as a silent success.

## Step 5: Optional detail (only if `--verbose`)
- Last 20 lines of `<RUN_PATH>/run.log` (already pre-redacted at write time).
- Failed units: `ls "$RUN_PATH/units/failed"` (basenames only).
- Dropped units with their reason: read each `value/<UNNN>.value.json` `.reason` for units now in `units/dropped/`.
- Duplicate clusters surfaced at preflight: any `value/*.json` carrying `looks_duplicate_of`.
- Seed units not yet `renamed`: scan `seed/*/UNNN.json` for `status in {seeded, awaited_ok}`.

# Hard rules
- Read-only. NEVER mutate `state.json`, the queue dirs, the run config, or any artifact. No `state.sh set/inc/dec`, no `mv`, no `rm`.
- Always print the "Next action" line. The user should never have to guess what to do next.
- Never invent a counter, gate, or step that is not in `state.json` / the §3.1 enum.
- Never display secrets or PII. Render only hashes and counts; never echo `dest_chat_url`, raw briefs, emails, or tokens. The `run.log` tail is already pre-redacted - do not un-redact it.
- Never reference any specific domain; bucket and group labels come from `config.yaml` (`bucket_labels`), not from this skill.
