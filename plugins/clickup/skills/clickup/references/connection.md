# Connection layer — transports, capability contract, resolver

This file is the **single source of transport truth** for `/clickup`. It is the **only** file in the plugin that may name a concrete transport primitive — an `mcp__clickup__*` tool, a `clickup-cli` subcommand, or a REST endpoint. SKILL.md and `references/modes.md` call the **named operations** defined here (`op.*`); they never name a transport. A regression test (`CONN-3`) asserts no `mcp__clickup__` literal survives outside this file.

Nothing here hardcodes *which* transport runs. The active transport is whatever `config.connection` resolves to (§Resolver). On first use, when `config.connection.configured != true`, the plugin must investigate → ask → remember (see `modes.md` → `## connect`) — it must **never silently pick a transport**.

## Table of contents

- [Operations (the capability contract)](#operations)
- [Per-transport realization](#realization)
- [Canonical encodings](#encodings)
- [Capability matrix + degradation policy](#degradation)
- [Resolver algorithm](#resolver)
- [Secret handling](#secret-handling)
- [Shell + URL hygiene (injection defense)](#hygiene)
- [Fix hints (for status + connect)](#fix-hints)
- [VERIFY-AT-IMPL — empirical transport facts](#verify)

---

## Operations

The plugin performs exactly these abstract operations. Every other file calls them by name. Inputs/outputs are **canonical** (transport-neutral); each adapter translates to/from its transport's shape.

| # | Operation | Used by | Canonical input → output |
|---|---|---|---|
| 1 | `op.probe()` | preflight (every invocation), connect | none → `{rc}` |
| 2 | `op.get_hierarchy()` | list fuzzy-match, workspace, reload | none → workspace tree |
| 3 | `op.get_list(id)` | alias-hit verification | `list_id` → list record \| not-found |
| 4 | `op.get_members()` | teammate sync, identity onboard | none → `[{user_id, full_name, email}]` |
| 5 | `op.resolve_assignees(names)` | identity onboard, assignee fill | name/email → matches |
| 6 | `op.find_tasks(filter)` | duplicate detection, task-collaborator discovery | structural filter → tasks |
| 7 | `op.find_by_marker(uuid, list_id)` | idempotency retry search | uuid + list → matching task \| none |
| 8 | `op.get_task(id)` | reload verify, retry confirm, post-condition checks | `task_id` → task |
| 9 | `op.create_task(canonical)` | default + auto create | canonical payload → `{id, url}` |
| 10 | `op.update_task(id, fields)` | edit flows, CLI assignee degradation | fields → `{id, url}` |
| 11 | `op.create_comment(id, text)` | link-to-existing dup action | text → `{id}` |
| 12 | `op.get_custom_fields(id)` | custom-field opt-in, REST task_type resolution | `list_id` → fields |

`op.find_by_marker` is a **first-class operation, not a flavour of `op.find_tasks`** — it is load-bearing for retry safety and its realization differs sharply per transport (the CLI `task search` has no free-text/description query, so the marker is found by listing the target list and scanning each task's `description`). See [realization](#realization) and the idempotency notes in `SKILL.md` → Idempotency.

---

## Realization

The literal mapping. **This table is the only place these primitives appear.**

| Op | MCP | CLI (`clickup-cli`, alias `clkup`) | REST (`curl` → `api.clickup.com`) |
|---|---|---|---|
| `probe` | `mcp__clickup__clickup_get_workspace_hierarchy` (non-empty result ⇒ ok) | `clickup-cli auth check` (exit code only; rc=0 ⇒ ok) | `GET /api/v2/user` with the Authorization header |
| `get_hierarchy` | `mcp__clickup__clickup_get_workspace_hierarchy` | compose `clickup-cli workspace` + `space` + `folder` + `list --output json` | `GET /api/v2/team` → `/space` → `/folder` → `/list` |
| `get_list` | `mcp__clickup__clickup_get_list` | `clickup-cli list get <id> --output json` | `GET /api/v2/list/{id}` |
| `get_members` | `mcp__clickup__clickup_get_workspace_members` | `clickup-cli member list --output json` (or derive from team payload); roster may be partial | `GET /api/v2/team` (members[] on the team object) |
| `resolve_assignees` | `mcp__clickup__clickup_resolve_assignees` / `mcp__clickup__clickup_find_member_by_name` | `op.get_members` + the local dual-key match the resolver already specifies | `GET /api/v2/team` + local dual-key match |
| `find_tasks` | `mcp__clickup__clickup_filter_tasks` / `mcp__clickup__clickup_search` | `clickup-cli task list --list <id> --output json` (structural filters only — no free-text query) | `GET /api/v2/list/{id}/task?...` or `/team/{id}/task` |
| `find_by_marker` | `mcp__clickup__clickup_filter_tasks` on the list, then scan each task's `description`/`text_content` for `<!-- ck:<uuid> -->` | `clickup-cli task list --list <id> --output json` then scan each task's `description` (verified: the list payload includes `description` + `text_content`) | `GET /api/v2/list/{id}/task?include_closed=true` then scan `description`/`text_content` |
| `get_task` | `mcp__clickup__clickup_get_task` | `clickup-cli task get <id> --output json` | `GET /api/v2/task/{id}` |
| `create_task` | `mcp__clickup__clickup_create_task` (`markdown_description`, `assignees[]`, `priority` STRING, `task_type`, `tags[]`, dates) | `clickup-cli task create --list --name --description --status --priority <1-4> --assignee <single> --tag <single> --due-date --parent` — **no `task_type`, single `--assignee`, markdown unverified** | `POST /api/v2/list/{id}/task` (`markdown_content`, `assignees[]`, `priority` <1-4>, `custom_item_id`=task_type, `tags[]`) |
| `update_task` | `mcp__clickup__clickup_update_task` | `clickup-cli task update <id> --name --status --priority <1-4> --add-assignee --rem-assignee --description` (**no task_type** — verified) | `PUT /api/v2/task/{id}` |
| `create_comment` | `mcp__clickup__clickup_create_comment` | `clickup-cli comment create <task_id> ...` | `POST /api/v2/task/{id}/comment` |
| `get_custom_fields` | `mcp__clickup__clickup_get_custom_fields` | `clickup-cli field list --list <id> --output json` | `GET /api/v2/list/{id}/field` |

MCP re-auth primitive (used by [fix hints](#fix-hints), not an `op`): `mcp__clickup__authenticate`.

The MCP column is **1:1 with the plugin's pre-1.5.0 behaviour** — a user who chooses `mcp` at the connect prompt gets byte-identical 1.4.0 behaviour.

---

## Encodings

Canonical (transport-neutral) field values, mapped once here:

- **Priority** — canonical string enum, **closed**: `{urgent, high, normal, low}`. MCP passes the `string` verbatim. CLI and REST map `urgent=1, high=2, normal=3, low=4`. This is the single canonical map; it is always satisfiable (no degradation). The "no priority / unset" ClickUp state is **out of scope** — the plugin default is `normal`; CLI cannot express unset, so unset is never emitted.
- **Description** — canonical markdown string. MCP → `markdown_description`. REST → `markdown_content`. CLI → `--description` (markdown rendering UNVERIFIED — see [VERIFY-AT-IMPL](#verify)).
- **Assignees** — canonical `[user_id, ...]`. MCP and REST take the array. CLI takes a single `--assignee` on create (degradation below).
- **task_type** — canonical string `{task, bug, feature, milestone, ...}`. MCP sets it by name; REST sets `custom_item_id` (a numeric id, resolved via `op.get_custom_fields` / `task-type list` — see degradation note); CLI cannot set it on create or update.
- **Idempotency marker** — `<!-- ck:<uuid> -->` is carried inside the description under **every** transport. It is the retry anchor; do not drop it. (CLI marker round-trip is a VERIFY-AT-IMPL item with a defensive fallback below.)

---

## Degradation

The rule across every asymmetry: **never silently drop a field the user asked for.**

| Capability | mcp | rest | cli | Degradation when the active transport lacks it |
|---|---|---|---|---|
| `task_type` ≠ default | yes | yes | **no** (no `--task-type` on create or update) | capability-aware borrow → surface, never drop |
| multiple assignees | yes | yes | **no** (single `--assignee`) | borrow; or CLI: create with `assignees[0]`, then loop `op.update_task --add-assignee` for the rest, then **verify** (below) |
| markdown description | yes | yes | unverified | VERIFY-AT-IMPL; until verified, CLI passes markdown to `--description` and emits a one-time "may not render markdown" note |
| named member resolution | native | list+match | list+match | none — REST/CLI run the local dual-key match the resolver already specifies |
| priority | yes | yes | yes | none — canonical map |
| workspace-wide member roster | yes | yes | partial | CLI warns the roster may be partial |

**Three-tier degradation policy:**

1. **Lossless** — priority, markdown on MCP/REST, single-assignee tickets, named resolution. The adapter translates; no user-visible change.
2. **Capability-aware borrow** — when `op.create_task` needs a capability the active transport lacks, FIRST check whether a more-capable transport is in the resolved `available[]` (even if it is not `primary`). If yes, run **this one operation** on that transport and emit a one-line banner: `ℹ This ticket needs task_type=bug, which clickup-cli can't set — using mcp for this create. Your default stays 'cli'.` The stored `primary` is **not** changed; only `connection.last_resolved` records the borrow. **Borrow target preference for `task_type`: MCP first** (it sets the type by name, matching the plugin's vocabulary); only borrow REST for `task_type` if MCP is unavailable, and then first resolve the canonical type name to a `custom_item_id` via `op.get_custom_fields` (cache it alongside lists; mark this REST path VERIFY-AT-IMPL).
3. **Surface, never drop** — when no more-capable transport is available:
   - **Interactive** → `AskUserQuestion`: `[1] create without task_type (stays 'task'), set it later in ClickUp / [2] cancel and run /clickup:connect to add mcp or rest`.
   - **`--auto`** → a NEW refuse condition (see SKILL.md `--auto` safety net): `refusing: ticket needs task_type=bug but only clickup-cli is available (cannot set type). Run /clickup:connect or drop the bug-type requirement.`

**`--auto` never borrows silently.** Borrow crosses transports, which `--auto` users (running unattended) cannot see. Gate it on `connection.auto_borrow` (default **false**). With `auto_borrow:false`, a capability gap in `--auto` goes straight to tier-3 refuse — it does **not** borrow. Interactive mode always shows the borrow in the preview `Degrades:` row before the create, so the cross-transport hop is confirmed with eyes open.

**Multi-assignee post-condition (CLI).** After the create + `--add-assignee` loop, run `op.get_task` and assert the stored assignee set equals the canonical set. On mismatch, do **not** return a bare success — return: `ticket created (<url>) but only N of M assignees applied: <missing list>. Add the rest in ClickUp or re-run.`

---

## Resolver

Run once at preflight (SKILL.md Step 2.5), binding `ACTIVE` for the whole invocation.

```
resolve_transport():
  cfg = config.connection
  if cfg is absent OR cfg.configured != true:
      # NEVER silent-pick. Interactive: route to `## connect`. --auto: HALT "run /clickup:connect first".
      route_to_connect_or_halt()

  order = dedup([cfg.primary] + cfg.fallback_order)   # e.g. ["mcp","rest","cli"]; primary first
  available = []
  for t in order:
      rc = op.probe(t)                                 # four buckets + "absent"
      record rc into cfg.last_probe (advisory cache)
      if rc == "auth-ok": available.append(t)

  if available is empty:
      HALT with a per-transport rc summary + fix hints (see Fix hints). Do NOT silently degrade to read-only.

  ACTIVE = available[0]                                # highest-preference reachable transport
  if ACTIVE != cfg.primary:
      banner: "preferred transport <primary> is <rc>; using fallback <ACTIVE>"   # substitution is always visible
```

Then every operation dispatches `op.X(args) → ADAPTER[ACTIVE].X(args)`, with `available[]` consulted for the capability-aware borrow.

**Create is "outcome unknown", never "failed".** A transport-level error on `op.create_task` (timeout, 5xx, dropped connection) must be treated as **outcome unknown** — the task may have been created. Before **any** retry OR fallback create on a *different* transport, run `op.find_by_marker(uuid, list_id)` on the transport about to be used; if the marker is found, adopt that task (return its url) instead of creating a duplicate. This closes the cross-transport double-create window. (See SKILL.md → Idempotency.)

**Default fallback order** (written by the connect wizard): `primary` first, then the remaining reachable transports ranked by capability richness `mcp > rest > cli`. Removing a transport from `fallback_order` is the only hard opt-out (the find-call `off` analog); a `fallback_order` of just `[primary]` means "primary only, fail loud if it is down".

---

## Secret handling

The only ClickUp token on a typical machine lives in clickup-cli's own `config.toml`. These rules are non-negotiable.

1. **Store a pointer, never a value.** `connection.rest_token_ref` is `"env:<NAME>"` or `"cli-config"` — never the token. A token VALUE is never written to `config.json`, `drafts/`, `.snapshots/`, run artifacts, status output, or chat (not even masked). A negative test (`CONN-10`) asserts no `pk_`/`tk_`-shaped literal exists anywhere under `plugins/clickup/`, and the runtime write helpers (the `connection` `atomic_update` closure, the drafts writer, the status renderer) explicitly exclude any resolved token — they persist only enums, pointers, and probe rc values.
2. **Validate the pointer on read.** `connection.rest_token_ref` MUST match `^(env:[A-Z_][A-Z0-9_]*|cli-config)$`. Anything else (it is user-writable and round-trips unvalidated) ⇒ treat REST as `absent` with a fix hint; never feed an unvalidated name to a shell. Resolve `env:NAME` via a one-shot `python3 -c 'import os;...os.environ.get(NAME)'`, never via shell expansion of a config-supplied name.
3. **Tiered by plugin secret exposure** — prefer the transports that need no secret handling:
   - **MCP** — the plugin touches no token at all (recommended default).
   - **CLI** — the token stays inside clickup-cli's `config.toml`; the plugin only shells out to `clickup-cli`, never reads or `--token`-interpolates the value.
   - **REST** — the only transport that requires the plugin to obtain a token; opt-in, disclosed.
4. **Harvesting the CLI token for REST is opt-in and disclosed.** During `## connect`, if the user picks REST and the only token is in clickup-cli's config, the wizard asks: `[Use the token already in your clickup-cli config] / [I'll set $CLICKUP_API_TOKEN myself] / [Pick a different transport]`. The default recommendation steers to MCP/CLI to avoid touching the token. If `cli-config` is chosen, read `[auth].token` at call time with a one-shot `python3 - <<'PY'` using `tomllib` (3.11+) or a `grep -m1`-to-stdin pipe that assigns to nothing logged; the value is full-scope — disclose that in the wizard.
5. **REST token reaches `curl` via stdin/file, never argv.** Build the `Authorization: Bearer …` header with `curl --config <(...)` or `-H @-` fed from stdin / a here-doc; **never** put `Bearer $TOKEN` (or `--token <value>` to clickup-cli) on a command line — it leaks to `ps` and shell history. Never run `set -x` around a token-bearing call.
6. **Probe + status reveal presence only.** Report `auth-ok` / `absent` and `configured (clickup-cli config)` / `configured (env var)` — **never** echo the token, and never echo the specific env-var NAME (the NAME stays only inside `config.json`).

---

## Hygiene

Injection defense for the two shell-bearing transports.

- **clickup-cli args.** Every dynamic value (title, description, tag, list_id, assignee id, due-date) is arbitrary text — titles carry Connextra prose, descriptions carry source quotes, tags carry source-language keywords. Build each invocation as **separate, individually single-quoted arguments** (`--name 'value'`), never by concatenating untrusted text into one command string and never via `eval`. Single-quote the value and escape any embedded single quote with the `'\''` idiom. Pass long/markdown descriptions through a shell variable populated from a temp file (`DESC="$(cat "$tmp")"; clickup-cli task create ... --description "$DESC"`), not inline. The marker `<!-- ck:<uuid> -->` and any `--`-leading content go after their flag, never bare.
- **REST URLs.** Path segments (`list/{id}`, `task/{id}`) and query values come from config aliases and fuzzy matches — percent-encode them. Use `curl --url` with `--data-urlencode 'key=value'` for query params (and a JSON body via `--data @file` for POST/PUT), never a single hand-built URL string with interpolated ids. The `{id}` segments are numeric ClickUp ids; still validate they match `^[0-9A-Za-z_-]+$` before composing a URL.

---

## Fix hints

Per-transport remediation, surfaced by `## connect` and `/clickup:status` when a transport is not `auth-ok`:

| Transport | rc | Fix hint |
|---|---|---|
| mcp | `auth-fail` | "ClickUp MCP auth failed — run `mcp__clickup__authenticate`, then retry." |
| mcp | `absent` | "ClickUp MCP not connected — add the ClickUp MCP server, then run `/clickup:connect`." |
| cli | `absent` | "clickup-cli not found — install it, then `clickup-cli setup` to add a token + workspace." |
| cli | `auth-fail` | "clickup-cli token invalid — run `clickup-cli setup` (or `auth check` to test)." |
| rest | `absent` | "No REST token — `export CLICKUP_API_TOKEN=…` (then re-run `/clickup:connect`), or choose the `cli-config` source to reuse clickup-cli's token." |
| any | `retryable-network` | "Network/transport error — check connectivity, then retry; this is not a credential problem." |

---

## Verify

Empirical transport facts. Items marked **VERIFY-AT-IMPL** must be resolved against the live transport at implementation time, not assumed.

Resolved (recorded here):

- `clickup-cli auth check` exits 0 when authed (probe primitive). ✓
- `clickup-cli task list --list <id> --output json` includes per-task `description` **and** `text_content` — so `op.find_by_marker` works via the list payload alone, no per-task `op.get_task` needed. ✓
- `clickup-cli task create` has no `--task-type`; `clickup-cli task update` has no task_type flag (only `--add-assignee/--rem-assignee/--priority/--status/--name/--description`). So **CLI cannot set task_type at all** — the degradation borrow/refuse path is mandatory, not optional. ✓
- `clickup-cli task update` exposes `--add-assignee` / `--rem-assignee`, so multi-assignee is reachable via create+update (with the post-condition check above). ✓
- Per-task `custom_item_id` is present in the JSON — this is the field REST sets for task_type. ✓

Still **VERIFY-AT-IMPL** (resolve at runtime; do not assume):

- **CLI markdown + marker round-trip.** Does `clickup-cli task create --description '<text with <!-- ck:UUID --> marker>'` store the description so the HTML-comment marker round-trips intact (and stays hidden in render)? Resolve as a **runtime self-check**, not by writing a throwaway production task: on the FIRST CLI create of a session, after create, run `op.get_task` and assert the marker substring is present in the stored `description`. **Defensive fallback regardless of the answer:** the moment `op.create_task` returns, write the new `task_id` + `url` into the draft snapshot (`~/.claude/clickup/drafts/<uuid>.json` → `api_response`/`task_url`). Retry then matches on the draft-recorded id even if the marker did not survive — so CLI idempotency never depends solely on the marker.
- **REST `task_type` via `custom_item_id`.** Confirm the canonical type name → `custom_item_id` resolution (`op.get_custom_fields` / task-type listing) before relying on the REST `task_type` borrow path.
