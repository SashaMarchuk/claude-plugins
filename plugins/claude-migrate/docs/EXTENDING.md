# Extending: Add a New Source or Sink Connector

`claude-migrate` is connector-driven. The pipeline NEVER branches on the input or output kind: the active
input is a `source-connector.md` contract and the active output is a `sink-connector.md` contract, both copied
into the run directory. Two universal dispatcher skills, `skills/source/SKILL.md` and `skills/sink/SKILL.md`,
read whichever contract is present and execute a fixed set of operations against it.

Adding a new source (a different export shape, a live extraction, a future provider's archive) or a new sink
(a different destination surface) is therefore ADDITIVE. You write a contract file. You never edit a core
stage (`extract`, `preflight-value`, `distill-brief`, `synthesize-project`, `build-copy-page`, `apply-unit`),
never edit the dispatchers, and never add a mode enum to `config.yaml` or `state.json`.

> **Never edit shipped templates in place.** Files under `${CLAUDE_PLUGIN_ROOT}/templates/sources/` and
> `${CLAUDE_PLUGIN_ROOT}/templates/sinks/` carry a copy-first banner and are overwritten on `/plugin update`.
> Always copy a template into your run directory first, then edit the copy. The paths below follow this rule.

Two paths: **copy-and-edit a shipped contract**, or **author one interactively** via `/claude-migrate:config`.

## What stays untouched

Every operation routes through `bin/adapter.sh` (source) or `bin/sink-adapter.sh` (sink), which know NOTHING
about the specific source/sink. The behavior is entirely in the per-run contract markdown. Concretely:

- The 8-step state machine (`init -> ... -> done`) is unchanged.
- The two universal dispatchers (`source`, `sink`) are unchanged.
- The closed bucket-ROLE enum (`GROUPED | STANDALONE | REFERENCE | DROP`) is unchanged. A new source maps its
  units onto `KEEP | REFERENCE | DROP` value tiers at preflight; it never invents a role.
- The counter invariants, the two filesystem queues, and the gate locations are unchanged.

If a proposed connector seems to require a new core step, a new state-machine transition, or a new role, STOP:
it is out of scope for an additive connector. Open it as a SPEC change instead.

## Path A: Copy a shipped contract

If the new source/sink is close to one we ship, this is fastest. The shipped contracts are:

- Sources: `templates/sources/export-file.md` (the default; reads a Claude data export ZIP),
  `templates/sources/browser.md` (live extraction from the old account).
- Sinks: `templates/sinks/copy-page.md` (the byte-exact copy page, always emitted),
  `templates/sinks/browser.md` (confirmation-gated browser automation).

```bash
# In your cwd, after /claude-migrate:init <run-name>:
cp ${CLAUDE_PLUGIN_ROOT}/templates/sources/export-file.md .planning/claude-migrate/<run-name>/source-connector.md
cp ${CLAUDE_PLUGIN_ROOT}/templates/sinks/browser.md       .planning/claude-migrate/<run-name>/sink-connector.md
```

Then edit the copies in `.planning/claude-migrate/<run-name>/`:

- Replace placeholders (paths, URLs, ARIA names, env var names) with your specifics.
- Tune the budget / pacing section to your rate limits.
- Add source-specific or sink-specific forbidden patterns (PII, cookies, tokens).

Smoke-test the source contract before running the pipeline:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh .planning/claude-migrate/<run-name> enumerate
```

A non-empty JSON array of unit uuids means the source contract is viable. Smoke-test the sink contract with
its cheapest read op:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/sink-adapter.sh .planning/claude-migrate/<run-name> rate_limit_check
```

## Path B: Author one interactively

If no shipped contract fits:

```bash
/claude-migrate:config .planning/claude-migrate/<run-name>
```

The `config` skill interviews you for the operation set, the access mechanism, the unit of analysis, the
citation format, and the forbidden-data list, then writes a tailored `source-connector.md` or
`sink-connector.md` into the run directory and smoke-tests `enumerate` (source) or `prepare`/`rate_limit_check`
(sink) automatically. It NEVER auto-picks a connector and NEVER hardcodes a secret; auth must resolve from env
or from a pre-authenticated browser session at invocation time.

## SOURCE contract -- the 7 operations

Every `source-connector.md` MUST define these seven sections. The universal `skills/source/SKILL.md` reads your
file and runs exactly ONE per dispatch.

| Operation | Args | Return shape |
|---|---|---|
| `enumerate` | run config | JSON array of unit **uuids** (NOT positional idx). The `source` skill sorts ascending and assigns `UNNN`. |
| `extract_unit` | unit uuid | `{idx,uuid,name,created_at,messages:[{sender,text}],attachments_text,image_refs,raw_token_est}` |
| `extract_projects` | run config | `[{pid_uuid,name,prompt_template,knowledge_docs:[{filename,content}],is_starter}]` (sorted by uuid) |
| `unit_project_ref` | unit uuid | `project_uuid` or `null`. Your connector owns whether a real join key exists. Return `null` when there is no FK. |
| `account_check` | run config | `{verified_account_email_hash}`. Sanity-only. NEVER write the clear email. |
| `citation_anchor` | unit uuid | a unique, parseable string, e.g. `[EXPORT:conversations.json#idx]`, `[CHAT:uuid]`, `[URL:...]` |
| `forbidden_fields` | run config | redact/strip list (PII; cookies and tokens for any browser-backed source) |

### SOURCE contract structure

```markdown
**This is a shipped template.** **Copy it to your run directory before editing** -- direct edits to this
file will be wiped on `/plugin update`.

# Source connector: <short-name>
Source type: <free-form, e.g. "Claude data export ZIP" / "Live old-account browser session">
Authentication: <env var | pre-authenticated browser | none -- never hardcode secrets>

## enumerate
<concrete, runnable instructions. MUST return unit uuids so UNNN is stable across modes.>

## extract_unit
<how to produce the normalized unit. State the canonical text rule: which message field wins, which
content-block types to skip, how attachments fold in, how an absent image is noted, how an empty turn reads.>

## extract_projects
<how to read project instructions + knowledge docs. Mark starter/example projects is_starter:true so they DROP.>

## unit_project_ref
<return a real join key per unit, or "Not applicable -- return null." when the source has no FK.>

## account_check
<how to derive the source account email HASH only. Never write the clear value, never copy users.json.>

## citation_anchor
<exact format string; must be unique AND parseable.>

## forbidden_fields
<how to derive the redact/strip list -- static from config + connector-detected patterns.>

## Budget constraints
<size caps, pagination, per-extraction limits.>

## Known limitations
<read-only? lossy fallback? legal note?>
```

A live or browser-backed SOURCE contract MUST also specify a MANDATORY secret-strip pass (cookies,
localStorage/sessionStorage, JWT/Bearer, CSRF hidden fields, Authorization) that runs AFTER extraction and
BEFORE writing anything to disk, redacting to `[REDACTED:*]`. A connector that returns raw HTML is
non-conformant and the controller refuses it. Reuse the canonical regex set from `references/pii-policy.md`;
do not invent your own.

## SINK contract -- the 7 operations

Every `sink-connector.md` MUST define these seven sections. The universal `skills/sink/SKILL.md` reads your
file and runs exactly ONE per dispatch. A SINK that has no destination automation (like the copy page)
implements the write ops as no-ops or as a rendered card, but it MUST still define all seven sections.

| Operation | Args | Return shape |
|---|---|---|
| `prepare` | run config | connect + auth-check + capture `dest_account_email_hash`, OR scaffold the output artifact |
| `dedupe_probe` | `{brief_opening_normalized, project_handle?}` | `{exists, dest_chat_url?}` -- the resume-safety probe |
| `create_project` | `{name, instructions_migration}` | `{project_handle, adopted:bool}` -- probe-then-adopt-or-create; sets `instructions_mode=migration` |
| `seed_unit` | `{brief, target_name, project_handle?}` | `{status, dest_chat_url?}` -- verify the project is in migration mode before its FIRST seed |
| `finalize_unit` | `{dest_chat_url, target_name}` | rename after the first turn, or a no-op for a non-automated sink |
| `finalize_run` | run config | swap each project migration -> steady; on per-project failure, signal block (never silently pass) |
| `rate_limit_check` | none | `{rate_limited:bool}` from a destination cap marker |

### SINK contract structure

```markdown
<!-- This is a shipped template. Copy it to your run directory before editing -- direct edits will be wiped on /plugin update. -->

# Sink connector: <short-name>
Sink type: <free-form, e.g. "Self-contained copy page" / "Pre-authenticated browser">
Authentication: <pre-authenticated browser session | none -- never hardcode credentials>

## prepare
<connect + auth marker probe + capture dest_account_email_hash; OR scaffold the output artifact.>

## dedupe_probe
<search the destination for a chat whose first user message matches the normalized opening. Resume safety.>

## create_project
<probe-then-adopt-or-create. Idempotent across re-runs. Set the migration instruction variant.>

## seed_unit
<open a new chat (in-project for GROUPED, standalone otherwise), PASTE the brief (never type char-by-char),
submit. Verify the project is in migration mode before the first seed.>

## finalize_unit
<await the first assistant turn (bounded by ok_wait_ms), then rename. No-op for a non-automated sink.>

## finalize_run
<swap every created project to the steady instruction variant; on per-project failure, signal block.>

## rate_limit_check
<read the destination cap marker; a rate_limited unit goes back to pending with backoff, never failed.>

## Budget constraints
<seed pacing (seed_delay_ms), destination message cap, breaker threshold.>

## Known limitations
<v0.1.0 apply is in-session serial; any tab-parallel path is future work.>
```

All UI-coupled facts for a browser SINK live in `selectors.json` as ARIA names / role / text locators
(resilient), NEVER CSS paths. The contract references those facts; it does not embed brittle selectors inline.

## Hard rules

- The universal `skills/source/SKILL.md` and `skills/sink/SKILL.md` are NEVER modified to support a new
  source/sink. All source-specific and sink-specific logic lives in per-run contract files and per-type
  templates under `templates/sources/` and `templates/sinks/`.
- Never add a mode enum or a source-type/sink-type field to `config.yaml` or `state.json`. The contract file
  is authoritative; `input.mode` / `output.mode` only select copy-page-vs-browser at the SINK level and
  export-vs-live at the SOURCE level, both already in the closed schema.
- Never add a new bucket ROLE. Map your units onto `KEEP | REFERENCE | DROP` at preflight; `GROUPED` vs
  `STANDALONE` is decided by the user at `confirm`, never by a connector.
- A SOURCE `enumerate` MUST return uuids so `UNNN` (sorted-uuid order) stays stable and deterministic across
  modes and re-extractions. A connector that returns positional indices breaks determinism.
- Never leak auth tokens or PII into a contract file, a unit file, a brief, a result artifact, or `run.log`.
  Tokens resolve from env or from the pre-authenticated browser at invocation time; PII passes the
  `[REDACTED:*]` set in `references/pii-policy.md`.
- GATE 1 (`/ultra` pre-split) reviews your contract for completeness. If it flags a missing operation section
  or an incoherent config, fix it before the run advances to `split`.
- A SINK with no destination automation still defines all seven operations (write ops as no-ops or rendered
  cards). The dispatcher always has all seven to call.

## Checklist before relying on a new connector

- [ ] All 7 operation sections present (source) or all 7 (sink).
- [ ] Copy-first banner at the top, in the right form for the file type (markdown banner for `.md`).
- [ ] Source: `enumerate` returns a non-empty uuid array; `UNNN` is sorted-uuid stable across two runs.
- [ ] Source: `extract_unit` handles empty turns, attachments, and absent images without inventing content.
- [ ] Source (live/browser): secret-strip pass runs before any write; no raw HTML escapes.
- [ ] Sink: `prepare` captures `dest_account_email_hash`; `create_project` is probe-then-adopt (idempotent).
- [ ] Sink: `finalize_run` swaps every project to steady and signals block on any per-project failure.
- [ ] Citation anchors are unique AND parseable.
- [ ] `forbidden_fields` is non-empty for any source/sink touching PII or credentials.
- [ ] Tiny-export end-to-end: `/claude-migrate:run` reaches GATE 1 PASS, splits, scores, and builds a verified
      copy page.

## Contributing a contract upstream

If a connector is general-purpose enough that others would benefit, contribute the tested contract as a new
shipped template (keeping the copy-first banner):

```bash
cp .planning/claude-migrate/<run-name>/source-connector.md ${CLAUDE_PLUGIN_ROOT}/templates/sources/<type>.md
# or sink-connector.md -> templates/sinks/<type>.md
```

Then update `README.md`'s directory layout and `docs/ARCHITECTURE.md`'s shipped-connector lists, and add a
fixture-backed assertion in `tests/run.sh` so the new contract stays covered by `bash tests/run-all.sh`.
