# Architecture

`claude-migrate` moves chats and projects from one Claude.ai account to another. It is a resume-able
state machine over a filesystem work-queue. The pipeline NEVER branches on the source/sink kind: the active
input and output are markdown CONTRACT files (`source-connector.md` / `sink-connector.md`) copied into the
run directory, and two universal dispatcher skills (`source` / `sink`) execute a fixed set of operations
against whichever contract is present. This keeps the core provider-neutral and domain-neutral: no chat
content, project name, or bucket label is ever hardcoded.

The single deliverable that ALWAYS gets produced is a byte-exact, self-contained copy page (`out/index.html`).
That is the reliable floor. When a pre-authenticated browser is reachable AND the user actively opts in, the
plugin ALSO runs confirmation-gated browser automation that seeds and renames chats hands-free. Either way the
run reaches a defined terminal state.

## Pipeline state machine (resume-able, gate-blocked)

`current_step` is a HARD ENUM enforced inside `bin/state.sh set` (any other value exits 7). Each arrow is a
transition recorded atomically in `state.json`. A kill at any point leaves the run resumable via
`/claude-migrate:resume`.

```
init
 -> pre-split-gate     [GATE 1: /ultra]  export readable? counts sane? connectors+config coherent?
                                          users.json NOT copied? isolation honored?
 -> split              extract: SOURCE enumerate + extract_unit + extract_projects (+ unit_project_ref)
                                -> units/pending/ + project/<PNN__slug>/   (SERIAL, single parse)
 -> preflight          value/bucket/dup score per unit   (PARALLEL fan-out). ALWAYS runs.
                                --no-preflight only swaps the scoring engine, never the structure.
 -> filter-gate        BLOCKS -> user runs /claude-migrate:confirm :
                                G-FILTER + G-NAMING + G-ONBOARD + G-MEMORIES + G-COST (pre-distill)
 -> distill            distill-brief: each KEPT unit -> one paste-ready first message   (PARALLEL, sonnet)
 -> synthesize         synthesize-project: per-project instructions x2 for projects with >=1 kept chat
                                (SERIAL, opus; reads the confirmed assignment map)
 -> build-page         build-copy-page: assemble the self-contained copy page   (SERIAL) -- ALWAYS
 -> verify-gate        [GATE 2: /ultra]  adversarial brief==source audit + headless byte-exact verify
 -> ready              MANUAL migration can proceed; the copy page is the dependable deliverable
 -> pre-apply-gate     browser sink only: BLOCKS -> /claude-migrate:confirm (G-AUTO-REOFFER + G-LOGIN/G-BROWSER)
                                then [GATE 3: /ultra]
 -> apply              SINK browser, IN-SESSION SERIAL: create projects (locked prelude)
                                then seed -> awaitFirstTurn -> rename
 -> finalize           browser sink only: swap every created project migration -> steady (strip OK protocol)
 -> done
 -> failed
```

Terminal-state rules:

- `ready` is reached with a fully working, byte-exact-verified copy page even if the user never enters AUTO.
  Declining AUTO at `ready` leaves the run at `ready`, and that IS success.
- `pre-apply-gate -> apply -> finalize` is entered ONLY when `output.mode == "browser"` (AUTO). For
  `output.mode == "copy-page"`, `ready` IS terminal: `status=passed` and `current_step` stays `ready`.
- The controller (`run`) NEVER prompts. When the next step is an interactive gate (`filter-gate`, the user
  portion of `pre-apply-gate`, or any blocked gate), `run` sets `status=blocked` + `blocked_reason` and
  returns the next command to type. The user invokes `/claude-migrate:confirm` (or `resume`), which performs
  the AskUserQuestion round, clears the block, and re-invokes `run`.

## The three gate categories

| Category | Who runs it | Gates |
|---|---|---|
| `/ultra` MACHINE gates | `run` (it may call the Skill tool for `/ultra:run`; non-interactive) | `pre-split` (GATE 1), `verify` (GATE 2), `pre-apply` (GATE 3, browser only) |
| USER gates | `confirm` (and `init` for the entry pair) | G-FILTER, G-NAMING, G-ONBOARD, G-MEMORIES, G-COST, G-AUTO-REOFFER |
| LOGIN / IDENTITY gates | `confirm` / `resume` | G-INPUT, G-OUTPUT (at `init`), G-LOGIN, G-BROWSER |

`bin/state.sh set` re-reads the relevant `gates.*.verdict` INSIDE the write lock and refuses to advance into a
gated step unless that gate is `PASS` (exit 8). Read and write happen under the same lock, so a concurrent
writer cannot flip the verdict between the check and the advance.

## state.json -- single source of truth

Located at `<cwd>/.planning/claude-migrate/<run>/state.json`. Created by `bin/state.sh init`; mutated ONLY
through `bin/state.sh` (locked, `rename(2)`-atomic, jq-injection-defended, run-name-allowlisted). Never edit
it by hand and never write it from a skill body.

```jsonc
{
  "run": "old-to-new-2026",                  // ^[A-Za-z0-9_-]+$ allowlist (blocks path traversal)
  "created_at": "2026-06-02T...Z",
  "updated_at": "2026-06-02T...Z",
  "current_step": "preflight",               // HARD ENUM -> state.sh exit 7 otherwise
  "status": "running",                       // pending | running | blocked | passed | failed
  "blocked_reason": null,                    // filter-gate | login | browser-lost | cost | auto-reoffer | finalize | ultra-missing

  "input": {
    "mode": "export",                        // export | live
    "export_path": "/abs/unzipped/export",   // export mode (absolute)
    "source_account_email_hash": null        // sha256 of users.json email; sanity-only; NEVER the clear value
  },

  "output": {
    "mode": "auto",                          // auto = browser sink + copy page ; copy-page = page only
    "user_chose_auto": false,                // true only if AUTO was ACTIVELY selected (not Enter-on-default)
    "browser": {
      "transport": null,                     // profile | cdp | extension | browser-use | null
      "endpoint": null,                      // e.g. "http://127.0.0.1:9222"
      "authed": false,                       // true only after the auth probe sees the composer/avatar marker
      "dest_account_email_hash": null        // sha256 of destination account email; set at prepare/login
    }
  },

  "profile": {
    "tier": "large",                         // small | medium | large | xl
    "preflight_model": "haiku",
    "distill_model": "sonnet",
    "synth_model": "opus",
    "validator_model": "opus",               // brief==source audit; MUST differ from distill_model (runtime-enforced)
    "ultra_gate_tier": "--large",
    "parallelism": 4,                         // worker terminals for preflight/distill
    "seed_parallelism": 1,                    // v0.1.0: SERIAL apply (=1). >1 reserved for the CDP-library future path.
    "seed_delay_ms": 1500,                    // pacing between submissions
    "ok_wait_ms": 45000,                      // bounded await-first-turn
    "breaker_threshold": 3,                   // consecutive transport/auth failures before circuit-break
    "capture_screenshots": false,             // per-attempt screenshots OFF by default
    "max_brief_tokens": 7000,                 // doc_only overflow trigger
    "inline_card_limit": 60,                  // copy-page inline-vs-lazy threshold
    "inline_byte_limit": 1500000
  },

  "gates": {
    "pre-split":  { "verdict": "pending", "report": null },
    "filter":     { "verdict": "pending", "report": null, "user_confirmed": false },
    "verify":     { "verdict": "pending", "report": null },
    "pre-apply":  { "verdict": "pending", "report": null }
  },

  "decisions": {                             // sticky AskUserQuestion answers; never re-asked on resume
    "preflight_value_scan": true,            // default ON (off => deterministic-heuristics-only engine)
    "naming_convention": "keep",             // keep | "custom:<scheme>"
    "onboarding_ok_protocol": "ok-then-strip", // ok-then-strip | strip-myself | none
    "memories": "skip",                      // skip | paste-to-memory | fold-into-project
    "cost_acknowledged": false,
    "auto_reoffer_ack": false,               // mandatory "looks right, proceed" in AUTO mode
    "project_assignment": {}                 // { "UNNN": "PNN__slug" | null }  user-confirmed map; null = standalone
  },

  "counters": { /* see "Counter invariants" below */ },

  "cost_estimate": { "in_tokens": 0, "out_tokens_est": 0, "usd_low": 0, "usd_high": 0, "model_blend": null },
  "last_checkpoint": null
}
```

## Filesystem work-queue (a unit's DIR location IS its state)

Resume = re-read `state.json` + scan these dirs. Each unit's directory location plus the counters fully
encode where the run stands; there is no hidden in-memory progress.

```
.planning/claude-migrate/<run>/
|-- state.json + state.json.lock.d
|-- .gitignore                          # excludes source/ seed/ apply/ out/payloads/ *.png run.log state.json checkpoints/
|-- config.yaml                         # tier, thresholds, naming, parallelism, bucket role->display-label map
|-- selectors.json                      # ALL claude.ai UI facts (ARIA/role/URL/rate-limit marker/auth marker)
|-- source-connector.md                 # COPY of templates/sources/<mode>.md  (user-editable)
|-- sink-connector.md                   # COPY of templates/sinks/<mode>.md   (user-editable)
|-- source/                             # INPUT landing: conversations.json, projects/, memories.json
|                                       #   (users.json is NEVER copied here -- PII; read for hash only)
|-- units/  pending/ in-progress/ done/ failed/ dropped/    # UNNN__<slug>.md  (preflight + distill queue)
|-- value/  UNNN.value.json             # preflight output per chat (categorical + deterministic est_tokens)
|-- briefs/ UNNN.brief.md  UNNN.name.txt
|-- project/
|   `-- <PNN__slug>/                     # PER-PROJECT, keyed by stable enumerate idx
|       |-- instructions-migration.md
|       |-- instructions-steady.md
|       |-- knowledge/<doc>.md
|       `-- .create.lock.d              # per-project create-lock (NOT one global lock)
|-- seed/   pending/ in-progress/ done/ failed/    # UNNN.json  (browser-sink apply queue; sized to seeded_units)
|-- apply/  UNNN.result.json  [UNNN.attempt-K.png if capture_screenshots]   # REPORT artifact only
|-- out/    index.html  README.md  .gitignore  payloads/UNNN.json
|-- validation/  gate1-*.md  gate2-*.md  gate3-*.md  verify-*.json
|-- checkpoints/ <iso>.json
|-- state/  requeue-archive/
`-- run.log                             # JSONL; every reason/last_error pre-redacted
```

Per-project layout notes:

- Projects are keyed by a stable `PNN__slug` derived from the enumerate index (sorted by source project uuid).
  This is what makes a multi-project export deterministic: two projects never collide into a single flat
  `instructions-*.md`, and output never depends on iteration order.
- `synthesize-project` runs ONLY for a project that has at least one kept chat assigned to it in
  `decisions.project_assignment`. A project with zero kept chats is logged and skipped, never created.
- `project/<PNN__slug>/.create.lock.d` serializes the per-project creation prelude during `apply`. SINK
  `create_project` probes the destination for an existing project of the target name and adopts it if found,
  so re-runs are idempotent.

## Two filesystem queues + their lifecycle scripts

Two queues run on the same atomic-move pattern as `ultra-analyzer`. Both use a `mkdir`-based claim lock
(portable, no `flock` on macOS), refuse symlinks, and adjust exactly two counters per move so the per-queue
sum invariant always holds.

| Queue | Dir | Sized to | Counter pair prefix | Worker |
|---|---|---|---|---|
| `units` | `units/{pending,in-progress,done,failed,dropped}/` | `chats_total` | `preflight_*` | `preflight-value` then `distill-brief` |
| `seed` | `seed/{pending,in-progress,done,failed}/` | `seeded_units` | `seed_*` | `apply-unit` (in-session, serial) |

- **`claim.sh <run-path> <queue>`** -- `queue` is `units` or `seed`. Atomically moves the first `pending/*` to
  `in-progress/` under a `.claim.lock.d` mkdir lock; refuses symlinks at both dir and file level. On success:
  `dec` the queue's `*_pending` and `inc` its `*_in_progress`. Prints the absolute claimed path. Exit 1 = no
  work.
- **`release.sh <item-path> <done|failed|requeue> [reason]`** -- derives queue + run-path FROM the path, so the
  signature is uniform across both queues. Two-stage move (rename to a temp name in the same dir, then to the
  destination) so a sweep never catches a half-moved file. Adjusts the queue's two counters preserving the
  invariant. The `reason` is passed through the `[REDACTED:*]` regex set (`references/pii-policy.md`) BEFORE it
  is appended as a JSONL line to `run.log`.
- **`requeue.sh <run-path> <basename> <reason>`** -- the GATE-2 path: moves a `done/` brief back to `pending/`
  with a retry tag, archives the prior brief + verdict under `state/requeue-archive/`, decrements
  `distill_done` and (only if the prior verdict was PASS) `briefs_verified_ok`, increments `distill_pending`.
  A `verify`-gate requeue of a hallucinated brief MUST re-add to the seed queue without breaking the seed
  invariant.

## SOURCE connector -- 7 ops (universal dispatcher `skills/source`)

The pipeline never branches on the input mode. `bin/adapter.sh <run-path> <op> [args]` verifies
`source-connector.md` exists, then dispatches to `/claude-migrate:source`, which reads the contract and runs
exactly ONE of these operations. Two SOURCE contracts ship: `templates/sources/export-file.md` (DEFAULT) and
`templates/sources/browser.md` (live).

| Op | Input | Output |
|---|---|---|
| `enumerate` | run config | JSON array of unit **uuids** (NOT positional idx). `source` sorts ascending and assigns `UNNN`. |
| `extract_unit` | unit uuid | normalized `{idx,uuid,name,created_at,messages:[{sender,text}],attachments_text,image_refs,raw_token_est}` |
| `extract_projects` | run config | `[{pid_uuid,name,prompt_template,knowledge_docs:[{filename,content}],is_starter}]` (sorted by uuid -> `PNN`) |
| `unit_project_ref` | unit uuid | `project_uuid` or `null`. The connector owns whether a real join key exists; the export connector returns `null` (no FK). |
| `account_check` | run config | `{verified_account_email_hash}`. Sanity-only; NEVER writes PII. |
| `citation_anchor` | unit uuid | `[EXPORT:conversations.json#idx]` / `[CHAT:uuid]` / `[URL:...]` |
| `forbidden_fields` | run config | redact/strip list (PII; cookies/tokens for browser) |

The `export-file` connector reads `conversations.json` once via `node bin/parse-export.cjs` using a pinned
canonical text rule: prefer `message.text`; else join `content[]` `type==="text"` blocks in order; skip
`thinking`/`tool_use`/`tool_result`; append `attachments[].extracted_content`; note an absent image as
`[image existed: NAME -- not in export]`; empty human turns become `[no text]`. The `browser` connector runs a
MANDATORY secret-strip pass (cookies, localStorage/sessionStorage, JWT/Bearer, CSRF hidden fields,
Authorization) before writing anything; a connector returning raw HTML is non-conformant and the controller
refuses it.

## SINK connector -- 7 ops (universal dispatcher `skills/sink`)

`bin/sink-adapter.sh <run-path> <op> [args]` dispatches to `/claude-migrate:sink`. Two SINK contracts ship:
`templates/sinks/copy-page.md` (the reliable floor, ALWAYS emitted) and `templates/sinks/browser.md` (the
optional accelerator). The browser sink consumes the SAME `briefs/` the copy page shows.

| Op | Input | Output |
|---|---|---|
| `prepare` | run config | connect browser + auth check + capture `dest_account_email_hash` / scaffold copy page |
| `dedupe_probe` | `{brief_opening_normalized, project_handle?}` | `{exists, dest_chat_url?}` -- search destination for a chat whose first user message matches (resume safety) |
| `create_project` | `{name, instructions_migration}` | `{project_handle, adopted:bool}` -- probe-then-adopt-or-create; sets `instructions_mode=migration` |
| `seed_unit` | `{brief, target_name, project_handle?}` | `{status, dest_chat_url?}` -- verifies the project is in migration mode before its FIRST seed |
| `finalize_unit` | `{dest_chat_url, target_name}` | rename-after-first-turn (browser) / no-op (copy-page) |
| `finalize_run` | run config | swap each project migration -> steady (`instructions_mode=steady`, `projects_finalized++`); per-project failure -> block |
| `rate_limit_check` | none | `{rate_limited:bool}` from the `selectors.json` cap marker |

### Bucket ROLE enum (closed)

`GROUPED | STANDALONE | REFERENCE | DROP`. The core switches on the role enum ONLY. `config.yaml` supplies a
human display label per role (for example role `GROUPED` may be labeled "Project chats"); it may NOT add or
remove roles. `preflight-value` emits only `KEEP | REFERENCE | DROP` and NEVER `GROUPED`. A `KEEP` chat becomes
`GROUPED`-or-`STANDALONE` at `confirm` via the user's explicit assignment. `DROP` units move to
`units/dropped/` and are never deleted from the source.

## The non-negotiable apply order + await contract

`seed -> await first turn -> rename`. claude.ai auto-titles a chat from the first exchange AFTER the first
reply, so renaming before the first turn would be overwritten. `await_first_turn` blocks on "first assistant
turn rendered", bounded by `ok_wait_ms`; the literal `OK` is a confirmation only, never the blocking
condition.

Write-ahead order in `apply-unit`:

1. Write `seed/UNNN.json status=opened` atomically BEFORE clicking submit.
2. First action after a successful submit = atomic write `status=seeded` + `dest_chat_url`.
3. Capture `first_reply`. If it is not a bare OK (trim, strip trailing punctuation, case-insensitive, length
   <= 5) -> set `ok_protocol_miss=true`, increment the counter, STILL rename.
4. `await` timeout -> stay `seeded` + `last_error=ok_timeout` (never `failed`; resume re-polls).

`seed/UNNN.json` is the SOLE resume authority. `apply/UNNN.result.json` is a report artifact only.

### Per-seed sub-state (`seed/UNNN.json`)

```jsonc
{
  "idx": 12,
  "bucket": "GROUPED",                  // GROUPED | STANDALONE | REFERENCE  (DROP never enters seed)
  "target_name": "<title from briefs/UNNN.name.txt>",
  "brief_path": "briefs/12.brief.md",
  "project_ref": "P01__alpha",          // PNN__slug when GROUPED; null when STANDALONE/REFERENCE
  "status": "pending",                  // pending | opened | seeded | awaited_ok | renamed | done | skipped | failed
  "dest_chat_url": null,                // captured atomically on first successful submit
  "first_reply": null,                  // captured raw; used to compute ok_protocol_miss
  "ok_protocol_miss": false,
  "attempts": 0,
  "error_class": null,                  // transport | auth | content | selector | rate_limited
  "last_error": null                    // pre-redacted
}
```

Resume rules: `done` -> skip. `in-progress` (crashed) -> re-claim. `opened` -> AMBIGUOUS: run SINK
`dedupe_probe` before any re-seed; if a matching chat exists, adopt it (`status=seeded`, record URL) and do NOT
re-submit. `seeded` not `awaited_ok` -> poll for the first turn (bounded by `ok_wait_ms`); on timeout stay
`seeded` + `last_error=ok_timeout`. `awaited_ok` not `renamed` -> just rename, never re-seed. `rate_limited`
-> `status=pending`, re-claimable, never `failed`. Rename is idempotent and retryable.

## Concurrency + determinism map

| Step | Parallel unit | Mechanism | Bound | Model |
|---|---|---|---|---|
| `preflight` | one chat | `bin/launch-worker.sh <run> preflight` x N terminals, each `claim.sh units` | `parallelism` | haiku (or deterministic-heuristics-only if `--no-preflight`) |
| `distill` | one KEPT chat | `bin/launch-worker.sh <run> distill` x N | `parallelism` | sonnet |
| `apply` | one chat | IN-SESSION SERIAL; `launch-seed.sh` advises pacing | 1 (v0.1.0) | UI only (no API spend) |

Serial-only stages: `split` (single parse), the dedup post-pass, `synthesize` (reads the confirmed assignment
map), `build-page` / `verify` (single artifact), the project-creation prelude inside `apply`, and all gates.

Determinism guarantees:

- `UNNN` = sorted-uuid order, identical across export/live and across re-extractions. Live `enumerate` MUST
  return uuids.
- `est_tokens` is computed deterministically by `bin/parse-export.cjs` (chars/4 for EN, chars/3 for
  Cyrillic/CJK; pad the Opus estimate +35%). The model returns only categorical values; money never depends on
  a non-deterministic gate.
- Dedup representative = lowest `idx` (= lowest sorted uuid), computed in a SERIAL post-pass over `value/*.json`
  after preflight drains, never inside a parallel worker. Duplicates are surfaced at G-FILTER for explicit
  pick, never auto-dropped.
- `--no-preflight` keeps the SAME structure and gate locations; it only swaps the scoring engine to
  deterministic-heuristics-only and sets every non-DROP chat to KEEP. It NEVER bypasses `filter-gate` or
  G-COST.

Workers are launched as independent `claude --print` subprocesses via `bin/launch-worker.sh`, each wrapped in
`timeout`/`gtimeout`; the launcher FATAL-exits if neither binary exists. The launcher uses `set -uo pipefail`
(not `-e`) so its 3-attempt retry loop can read `$rc` after each non-zero exit; exit 124 (timeout) does not
retry. The unit path is wrapped in BEGIN/END markers so the worker treats it as quoted DATA, not directives,
and the basename passes an allowlist + injection-marker reject. No MCP sub-agents run inside a pipeline stage;
the `/ultra` swarm is invoked ONLY at the three gates.

## Counter invariants

These are enforced by every queue move and reported as a finding by `/claude-migrate:health` on drift.

```jsonc
"counters": {
  "chats_total": 0,
  "preflight_pending": 0, "preflight_in_progress": 0, "preflight_done": 0, "preflight_failed": 0,
  "kept": 0, "dropped": 0,
  "seeded_units": 0, "doc_only_units": 0,
  "distill_pending": 0, "distill_in_progress": 0, "distill_done": 0, "distill_failed": 0,
  "briefs_verified_ok": 0, "briefs_verified_fail": 0,
  "seed_pending": 0, "seed_in_progress": 0, "seed_done": 0, "seed_failed": 0,
  "seeded": 0, "renamed": 0, "ok_protocol_miss": 0,
  "projects_total": 0, "projects_pending": 0, "projects_created": 0, "projects_finalized": 0
}
```

- `chats_total == preflight_pending + preflight_in_progress + preflight_done + preflight_failed`
- `kept == distill_pending + distill_in_progress + distill_done + distill_failed`
- `kept == seeded_units + doc_only_units` (doc_only units never enter the seed queue)
- (browser sink) `seeded_units == seed_pending + seed_in_progress + seed_done + seed_failed` (the seed queue is
  sized to `seeded_units`, NOT `kept`)
- `projects_total == projects_pending + projects_created`
- before `status=passed` (browser): `projects_created == projects_finalized`

Every script that moves a work-item adjusts exactly two counters to preserve the relevant invariant. A
`verify`-gate requeue of a hallucinated brief decrements `briefs_verified_ok` (only if the prior verdict was
PASS) and re-adds the seed unit to `seed_pending`, never breaking the seed invariant.

## OK-protocol lifecycle (create-then-strip)

1. `synthesize-project` emits per project TWO instruction variants: `instructions-migration.md` (contains the
   line telling the model the FIRST message in any chat is a migration brief, reply exactly `OK`, then work
   normally) and `instructions-steady.md` (that line removed).
2. SINK `create_project` sets the migration variant and `instructions_mode=migration`.
3. Each chat is seeded, awaits its first turn (ideally `OK`), then is renamed.
4. SINK `finalize_run` swaps every created project to the steady variant (`instructions_mode=steady`,
   `projects_finalized++`). Copy-page mode prints a trailing "swap to steady-state" card per project instead.

Hard rule: never reach `done` with any project in migration mode. A `finalize_run` per-project failure sets
`status=blocked` (NOT done) with the un-stripped project list and the steady file path, and the run is
resumable.

## Browser connection + identity guard

`bin/browser-probe.sh` detects a transport in priority order and writes the winner to `state.output.browser`:
the `@playwright/mcp` persistent profile (DEFAULT), then Playwright over CDP at `http://127.0.0.1:9222`
(also the engine behind `verify-copy-page.cjs`), then the `browsermcp` extension, then `browser-use` as a last
resort. Login is NEVER automated: if the auth marker (composer / avatar) is absent, the run blocks with
`blocked_reason=login` and hands back to `confirm`/`resume` ("log in, then `/claude-migrate:resume`").

GATE 3 identity invariant: if `dest_account_email_hash` and `source_account_email_hash` both exist and are
EQUAL, HARD-STOP ("source and destination appear to be the SAME account"). A missing hash is a soft warning at
the filter gate, not a stop.

On locator failure the apply step degrades automatically: accessibility-snapshot retry -> `browser-use`
agentic -> the always-emitted copy-page floor. The documented escape hatch is the verified copy page, not
"edit the selectors by hand". A circuit breaker stops claiming after `breaker_threshold` consecutive
`transport`/`auth`-class failures, sets `status=blocked` (`blocked_reason=browser-lost`), re-probes, and fires
G-BROWSER.

## Further reading

- `docs/EXTENDING.md` -- how to add a future source or sink connector without touching the core stages.
- `tests/README.md` -- the AC-* acceptance-criteria catalog and behavioral UAT steps.
- `references/auto-title-gotcha.md` -- the seed/await/rename law in full.
- `references/pii-policy.md` -- the canonical `[REDACTED:*]` regex set and the `users.json` / `memories.json` rules.
- `references/login-policy.md` -- the never-automate-login rule and the dest != source identity guard.
