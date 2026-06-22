---
name: clickup
description: ClickUp ticket creation, modification, and workspace management with enforced quality standards. Creates consistent tickets using Connextra user stories, evidence-only descriptions, fuzzy list aliases, first-name teammate resolution, bug-keyword type inference, priority-keyword inference, duplicate detection, idempotent create, and preview-and-edit confirmation. Includes a two-step onboarding wizard, persistent user config + memory files, and a stale-config reminder. Use when the user types /clickup, /clickup --auto, /clickup --onboard, /clickup --memory, /clickup --status, /clickup --workspace, or says "create a ticket", "add to backlog", "put in ClickUp", "make a task", "file a bug in ClickUp", "create a ClickUp task", or references a ClickUp list, task, or workflow.
user-invocable: false
---

# /clickup

Universal skill for creating and managing ClickUp tickets. Enforces consistent title + description conventions so every teammate writes the same way. Onboarding builds a personal config; memory captures learned preferences.

## Step 1: Parse $ARGUMENTS

| Flag | Mode | Details |
|---|---|---|
| (none) | Interactive ticket create | `references/modes.md#default` |
| `--auto` | Silent create with defaults | `references/modes.md#auto` |
| `--onboard` | Full wizard (identity + workspace) | `references/modes.md#onboard` |
| `--onboard identity` | Re-run shared identity wizard only | `references/modes.md#onboard-identity` |
| `--onboard workspace` | Re-run clickup-local wizard only | `references/modes.md#onboard-workspace` |
| `--memory [add\|list\|remove\|clear]` | Manage learned patterns | `references/modes.md#memory` |
| `--status` | Config health check (both files + connection) | `references/modes.md#status` |
| `--connect` | Investigate transports, pick one, remember it | `references/modes.md#connect` |
| `--connect show` | Read-only connection view (alias for status block) | `references/modes.md#connect` |
| `--workspace` | Switch active ClickUp workspace | `references/modes.md#workspace` |
| `--reload` | Reconcile config.lists with workspace state | `references/modes.md#reload` |
| `--reload --mode=incremental` | Force incremental even on large diff | `references/modes.md#reload` |
| `--reload --mode=full` | Force route to onboard-workspace with archive carry-forward | `references/modes.md#reload` |

**Precedence on conflict:** `--onboard` > `--status` > `--connect` > `--memory` > `--workspace` > `--reload` > `--auto` > default. Flag arguments are space-separated (`--onboard identity`, not `--onboard=identity`). Positional args after flags are the ticket-seed text.

**Transport is never hardcoded.** Every ClickUp side-effect goes through a named capability operation (`op.*`) whose per-transport realization (ClickUp MCP / `clickup-cli` / REST) lives ONLY in `references/connection.md`. Which transport runs is whatever `config.connection` resolves to (Step 2.5). This file never names a transport primitive.

**`--onboard --auto` is REJECTED at parse time.** If `$ARGUMENTS` contains BOTH `--onboard` AND `--auto` (in any order, with or without a sub-arg like `--onboard identity`), HALT BEFORE any pre-flight step with the one-liner:

```
refusing --onboard --auto: onboarding must be interactive (AskUserQuestion required). Run `/clickup --onboard` alone first, then retry `/clickup --auto "<seed>"`.
```

Rationale: `--onboard` requires `AskUserQuestion` rounds (see `references/modes.md` → `onboard-identity` Step 2/3/4/7); `--auto` explicitly bans interactive prompts ("silent create with defaults"). The combined invocation has no valid execution — either AskUserQuestion opens (violating `--auto`) or onboarding silently skips (violating `--onboard` precedence). An LLM resolves this differently each run; the only safe behaviour is parse-time refusal. Closes PLG-clickup-F5.

**`--reload --auto` is REJECTED at parse time.** If `$ARGUMENTS` contains BOTH `--reload` AND `--auto` (in any order), HALT BEFORE any pre-flight step with the one-liner:

```
refusing --reload --auto: list-reconciliation requires interactive confirm. Run `/clickup:reload` alone.
```

Rationale: reload's diff is presented in a confirm card (`[1] Apply / [2] Cancel / [3] Pick aliases for new lists first`). `--auto` bans interactive prompts. Silently rewriting the user's `lists[]` + aliases is a data-loss vector. Mirrors the parse-time refuse for `--onboard --auto` immediately above.

**`--connect --auto` is REJECTED at parse time.** If `$ARGUMENTS` contains BOTH `--connect` AND `--auto` (in any order), HALT BEFORE any pre-flight step with the one-liner:

```
refusing --connect --auto: choosing a transport requires interactive investigation (AskUserQuestion required). Run `/clickup:connect` alone first, then retry `/clickup --auto "<seed>"`.
```

Rationale: `## connect` investigates all three transports and the user must CHOOSE one (`AskUserQuestion`) — the choice is never silent. `--auto` bans interactive prompts. The combined invocation has no valid execution; the only safe behaviour is a parse-time refuse. Mirrors `--onboard --auto` / `--reload --auto`.

**Seed-text 4 KB cap (pre-extract truncation).** Any seed text — pasted transcript, previous-turn context carried forward, positional args — longer than **4096 bytes** (UTF-8 encoded) is truncated BEFORE the extract step. Truncation point: the nearest **sentence boundary** (period, question mark, exclamation mark, or newline) at or before the 4096-byte mark. If no sentence boundary exists in the first 4096 bytes, fall back to the nearest whitespace; if none, hard-cut at 4096 bytes. After truncation, show the user an explicit banner:

```
[SEED-TRUNCATED: <N> bytes dropped at sentence boundary]
```

Where `<N>` is the byte count of the dropped tail. The banner is load-bearing — the operator must know that downstream extraction saw only the truncated prefix, not the full paste. Rationale: the evidence-only rule is the only fence against attacker-controlled bulk paste; a 4 KB cap bounds the blast radius of a pasted tracking pixel / prompt injection / `@mention` flood without degrading legitimate ticket-creation flows (most seed texts are well under 4 KB). Closes PLG-clickup-F14.

## Step 2: Pre-flight (every invocation, in order)

1. **Read shared identity** from `~/.claude/shared/identity.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "identity missing — run `/clickup --onboard` first" (don't drag user into interactive onboarding mid-auto).
   - In interactive mode: redirect to `--onboard identity` with one-line explanation; carry the original request as ticket seed.
2. **Read clickup config** from `~/.claude/clickup/config.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "config missing — run `/clickup --onboard workspace` first".
   - In interactive mode: redirect to `--onboard workspace`; carry the ticket seed.

**Step 2.5 — Resolve connection (which transport to use).** Read `config.connection`. This runs for EVERY ClickUp-touching mode (default create, `--auto`, `--reload`, `--workspace`, `--onboard workspace` — anything that calls an `op.*`). If `connection` is absent OR `connection.configured != true` (connection has never been investigated — the gate, see `references/config-schema.md` → `connection`):
   - **In `--auto` mode**: HALT with "connection not configured — run `/clickup:connect` first" (never drag `--auto` into `AskUserQuestion`; mirrors the identity/config auto-halts above). No write, no data touched.
   - In interactive mode: redirect to `references/modes.md#connect` with a one-line explanation; carry the ticket seed forward (same pattern as the identity/workspace redirects). **Never create or mutate a ticket without an investigated, chosen connection on disk** — and never silently pick a transport.
   - In `--status` mode: report "connection: not configured" and do NOT detour.

   When `configured == true`, run the resolver in `references/connection.md` → Resolver: build the available list (preference first, then `fallback_order`), bind `ACTIVE` for the whole invocation, and surface a banner if a fallback is used instead of the preferred transport. The resolved transport is what Step 6's probe and every later `op.*` dispatch through.

3. **Validate schemaVersion** — both files must have integer `schemaVersion` ≤ the version this skill understands (currently `2`; readers accept `{1, 2}` during the v1 → v2 back-compat window — see `references/config-schema.md` → Shared-contract constants). Writers always emit `2`, and `/clickup:connect` / `--onboard` upgrade a v1 file to `2` on mutation, so a v2 file written by this skill must NOT be treated as "higher version". On a genuinely higher version (`> 2`): refuse to write, degrade to read-only with a banner. On corrupt JSON: quarantine to `<file>.corrupt-<epoch>` and re-onboard.
4. **Read memory** from `~/.claude/clickup/memory.md`. Apply rules. If any rule is unused >60 days or applied >20 times, prepend a one-line review banner: "`💡 N memory rules may be stale — run /clickup --memory list`".
5. **Check config freshness.** If `config.updated_at` > 30 days ago, prepend: "`💡 Config is 30+ days old — run /clickup --onboard to refresh`". Non-blocking.
6. **Verify the resolved transport's auth with `op.probe()`.** Run `op.probe()` against the transport bound in Step 2.5 (the realization per transport — MCP / `clickup-cli` / REST — lives in `references/connection.md` → Realization; this file never names it). Classify the return via named dispatch — DO NOT collapse into a single "fail" bucket:
   - **`auth-ok`** — probe returns a usable result (a non-empty workspace tree, or `clickup-cli auth check` exit 0, or a 200 from the REST user endpoint). Proceed.
   - **`auth-fail`** — HTTP 401 / 403, "not authenticated" / "invalid token" / "disconnected" / any explicit credential-rejection. Try the next transport in `fallback_order` (per the resolver); if none reaches `auth-ok`, HALT with the per-transport re-auth fix hint from `references/connection.md` → Fix hints (e.g. the MCP re-auth step, `clickup-cli setup`, or the REST token hint).
   - **`retryable-network`** — timeout, connection refused, DNS failure, HTTP 5xx, or the transport process unreachable. Retry ONCE after 2s backoff; on second failure try the next transport in `fallback_order`, else HALT with "ClickUp unreachable (rc=retryable-network). Check network/transport, then retry /clickup." Do NOT escalate to `auth-fail` — a transient network error is not a credential problem.
   - **`other`** — any unclassified error (malformed response, unexpected shape). HALT with the raw error and rc=other; never silently proceed.

   **Never fabricate a success URL.** The probe MUST fire on EVERY invocation — do not skip under context pressure. If you cannot name the resolved transport's probe call or classify its return in your own words, you have not verified auth.
7. **Re-validate teammates lazily.** If any `teammates[].last_validated_at` > 7 days (or `null`), silently fetch workspace members; diff against identity; surface significant changes (removed users, renames) as a banner. Updates go to `~/.claude/shared/identity.json` via the atomic helper in `references/config-schema.md`.

## Step 3: Route by flag

Load the referenced section from `references/modes.md` before acting. Each mode has its own deterministic flow.

---

## Core rules (apply in EVERY mode that creates or edits a ticket)

Full rules + worked examples in `references/ticket-format.md`. Enforce:

**Title** — imperative verb + subject + qualifier. English. ≤80 chars. No `[Bug]` / `[Feature]` / `[Task]` prefixes, no list-name prefixes, no ticket numbers. Must pass the test: "To complete this ticket, I need to ___." Generate with a pre-translate buffer of ≤72 chars to leave room for EN expansion; regenerate (drop adjectives/qualifiers) rather than truncate mid-word.

**Description** — English. Always open with the Connextra line:

```
As a [beneficiary role], I want [goal], so that [benefit].
```

Omit the line entirely if the beneficiary role is not extractable from source. Role = who benefits, not who requested. The requester goes in the optional "Requested by" section.

**Evidence-only** — never invent acceptance criteria, metrics, stakeholders, timelines, impact statements, or business-value boilerplate.

**No field duplication** — never restate assignee, tag, priority, status, dates in the body. Those live in ClickUp's native fields.

**Optional sections** — render ONLY when source provides content: `Context`, `Proposed Solution`, `Acceptance Criteria`, `Open Questions`, `References`, `Requested by`. If nothing extractable beyond the user story, the description is just the Connextra line.

---

## Defaults (enforced unless user overrides in preview)

| Field | Default | Override signal |
|---|---|---|
| Language | English | none — always EN |
| Priority | `normal` | urgent/ASAP/P0/burning → urgent; "high priority"/P1 → high; "low priority"/P3 → low. Resolved via the **4-tier precedence** in `references/config-schema.md` → "Application order": (1) explicit CLI flag > (2) keyword-in-turn > (3) memory rule > (4) default. Keyword-in-turn WINS over memory — e.g. memory rule "Daria = P1" + source "low priority typo for Daria" → priority=low. |
| Status | `backlog` | only if user explicitly names another status |
| Task type | `task` | bug signals: `bug`, `broken`, `fails`, `failing`, `regression`, `crash`, `500`, `error`, `doesn't work`, `not working` → propose `bug`, confirm in preview |
| Tag | none | source names one, or memory rule applies |
| Dates | none | never inferred |
| Custom fields | skipped | only if user explicitly asks |

---

## Resolution rules

### Assignee (dual-key resolver, teammates live in shared identity.json)

The roster lives in `~/.claude/shared/identity.json` under `teammates[]`. `/g-event` reads the same file — changes here are seen there.

**Homoglyph-collision gate (runs before every silent single-match AND before every zero-match upsert)**: compute the UTS #39 skeleton on the **RAW typed input, BEFORE the zero-width / BOM strip in step 1** (`unicodedata.normalize("NFKC", raw).casefold()` + confusables-map transform). Order is load-bearing: if the strip runs first, a BOM-prefixed record like `﻿Misha` collapses to `Misha` and skeleton-matches an existing `Misha` as identical bytes — the gate would never fire even though the distinct-record signal was the very BOM the strip just erased. Compute the skeleton BEFORE the strip, and compare BOTH the skeleton AND the raw byte-string to every existing teammate's skeleton+raw. If the skeleton matches an EXISTING teammate AND raw byte-strings differ (i.e. visually identical but distinct records), FORCE disambiguation — never silent-match. This gate ALSO runs on the zero-match upsert path (step 7 below) BEFORE a new teammate is written: compute the skeleton of the typed local-part AND the full email AND compare against every existing `teammates[].email` skeleton; on collision, FORCE disambiguation between the existing and proposed record — do NOT silent-upsert. Legitimate pure-script names (all-Cyrillic, all-Latin) never trigger this — no skeleton collision with anyone else. This precedence is load-bearing and overrides any "silent-allow" rule elsewhere.

1. **FIRST**: compute raw-skeleton for the homoglyph gate above (RAW bytes, PRE-strip). **THEN**: NFC-normalize the typed name; strip leading/trailing whitespace (`re.sub(r"[\s​‌‍⁠﻿]+", "", ...)` — ASCII + zero-width + BOM); strip emoji. Use `str.casefold()` (NOT `.lower()`) for all case-insensitive comparisons (handles Turkish İ/i; German ß/ss correctly). Order matters: skeleton-on-raw BEFORE strip — if this order is violated, the BOM-prefix attack in the gate prose above slips through.
2. **First pass** — casefold match against `teammates[].latin_alias`. (ASCII common case — most hits land here.)
3. **Second pass** — casefold + NFC match against `teammates[].first_name`. (Cyrillic users typing their own name.)
4. **Third pass** — casefold match on `teammates[].email` (when user typed an email).
5. **Single match** → fill silently.
6. **Multiple matches** → prompt disambiguation (show full names + emails).
7. **Zero matches** → freeform prompt for full email. Validate against `^[^@\s"'\\<>]+@[^@\s"'\\<>]+\.[^@\s"'\\<>]+$` AND reject any domain with non-ASCII characters (IDNA mixed-script attack defense) AND reject any domain OR any domain-label that begins with `xn--` (IDN punycode rejection — `xn--pple-43d.com` is pure ASCII but unpacks to `аpple.com` with Cyrillic `а`, so the non-ASCII check alone is bypassable). THEN — BEFORE the upsert — run the homoglyph gate defined above on the zero-match path: compute the skeleton of the typed local-part AND the full email AND compare against every existing `teammates[].email` skeleton; on collision (raw bytes differ but skeletons match — e.g. Cyrillic-local-part `rаchel@corp.com` vs existing Latin-local-part `rachel@corp.com`), FORCE disambiguation between the existing and the proposed record. Do NOT silent-upsert. On failure, re-prompt with the reason. On valid email that passes ALL gates (regex + non-ASCII + `xn--` + skeleton-collision), upsert into `teammates[]` with `sources: ["manual"]` + `last_validated_at: null` via the atomic write helper. A later MCP refresh will enrich with `external_ids.clickup` + `full_name`.
8. **Re-validation guard**: before assigning, check `teammate.active == true`. **Missing `active` field is treated as `false`** — a teammate record with no `active` key is BLOCKED from mention/assign resolution until explicitly activated by `/clickup` workspace-sync. This is load-bearing: JS `undefined == true` is `false` (safe) and Python `None == True` is `False` (safe), but a prose-only contract could otherwise be read as "treat missing as truthy". The explicit rule is: **no `active: true` literal present → blocked, no exceptions**. Cross-references the v2 schema addition at `references/config-schema.md` → `teammates[].active` field rule, which pins the same default on-read for v1 → v2 migration. On deactivated user OR missing-active user, block; force re-prompt / re-onboard. Closes PLG-clickup-F13.
9. In `--auto`: if ambiguous or deactivated AND no memory rule resolves unambiguously → refuse with one-line reason.

### List (alias → fuzzy hierarchy)

1. Match user-named list (case-insensitive) against `config.lists[].aliases`.
2. **Alias hit** → resolve to stored `list_id`; verify still exists and not archived via `op.get_list`. If renamed, update alias silently. If `archived: true` on the stored record, refuse with `"list <name> archived — re-onboard or pick a different list"`. If the `id` is not present in the `op.get_list` response and the stored record does NOT have `archived: true`, refuse with `"list not found — run /clickup:reload to reconcile (id may have been deleted) or re-onboard"`. If renamed (id present, name differs), update the stored `name` silently — alias resolution is by id, not name.
3. **No alias hit** → call `op.get_hierarchy`, fuzzy-match top 3 candidates, surface for user confirm.
4. In `--auto`: if no alias hit AND no single high-confidence fuzzy match → refuse.

### Duplicate detection (before create)

1. Search open tickets in target list via `op.find_tasks` (include_closed=false).
2. **Pinned similarity metric — deterministic under identical inputs.** Compute the **Jaccard coefficient** on **casefolded, NFKC-normalised word tokens** between the candidate title and each open ticket's title:
   - **Tokenise**: split on Unicode whitespace + ASCII punctuation `[\s\.,;:!?\(\)\[\]\{\}"'`\-/\\]+`. Drop empty tokens.
   - **Normalise each token**: `unicodedata.normalize("NFKC", tok).casefold()`. (Casefold — NOT `.lower()` — handles Turkish İ/i and German ß correctly; NFKC collapses compatibility variants like fullwidth digits.)
   - **Stopword removal** (fixed list, documented — do NOT expand arbitrarily): `{"a","an","and","are","as","at","be","by","for","from","has","have","in","is","it","its","of","on","or","that","the","to","was","were","will","with"}`. English-only; source-language keyword compare at step 5 handles other languages.
   - **Build two sets** `A` (candidate tokens) and `B` (existing-ticket tokens) from the remaining tokens.
   - **Jaccard** = `|A ∩ B| / |A ∪ B|`. If `|A ∪ B| == 0` (both titles empty after stopword removal), overlap = 0.
   This metric is pinned so two runs on the same inputs always agree on whether the 70% / 89.5% / 90% bands trigger.
3. **Interactive mode**: surface top 3 at Jaccard `>= 0.70` overlap. User picks `create anyway` / `link to existing` / `cancel`.
4. **`--auto` mode**: only block at Jaccard `>= 0.895` overlap (pinned threshold — deliberately just below the 0.90 boundary to catch near-identical titles that LLM-generated phrasing drift would otherwise slip past). Below that, proceed silently. Above, HALT with "possible duplicate: <url> (Jaccard=<value>, threshold 0.895)".
5. Also compare source-language keywords (before translation) to catch cross-language dupes. Same metric (Jaccard on casefolded-NFKC tokens); stopword set is English-only, so non-English token sets skip stopword removal (the information content of e.g. "і", "та" is minimal but they'd dilute the set; if this becomes a problem in practice, add a per-language stopword map under config — do NOT silently expand the English list).

### Idempotency (retry safety)

1. Generate UUID idempotency key per invocation. **Must be UUIDv4.** Pin the regex gate below on the generated key AND on any externally-provided UUID (e.g. any future `/clickup --retry <uuid>` flag or task-id parse path) BEFORE any filesystem operation:

   ```
   ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$
   ```

   This is load-bearing: it rejects path-traversal payloads like `../../etc/passwd`, empty strings, shell-metachar injection, and non-v4 UUIDs (v1/v3/v5) in one check. A value that fails this regex MUST NOT be used to compose any path under `~/.claude/clickup/drafts/` — HALT with "invalid UUID — refusing to compose draft path". Today the UUID is LLM-generated so traversal is not immediately exploitable, but this gate is the load-bearing defense for any future feature that accepts a user-provided UUID (command-line retry flag, crash-recovery path, etc.).
2. **Before** calling `op.create_task`, write draft to `~/.claude/clickup/drafts/<uuid>.json` — ONLY after the UUID passed the regex gate above.
3. Include the key as a marker in the ticket description (hidden HTML comment: `<!-- ck:<uuid> -->`) so retries can find partial successes under any transport.
4. **The moment `op.create_task` returns, record the new `task_id` + `url` into the draft** (`api_response` / `task_url`). This is the transport-independent retry anchor — it does not depend on the marker surviving in the stored description (which is unverified for `clickup-cli` — see `references/connection.md` → VERIFY-AT-IMPL).
5. **A create error is "outcome unknown", never "failed".** On timeout / 5xx / dropped connection, the task may exist. Before ANY retry OR fallback create — including a create on a *different* transport per the resolver's `fallback_order` — run `op.find_by_marker(uuid, list_id)` on the transport about to be used. If the marker (or the draft-recorded id) is found, adopt that task and return its url; do NOT create a duplicate. This closes the cross-transport double-create window.

---

## `--auto` safety net (refuse conditions)

Refuse creation with a one-line reason when any of these hold:

- No source context ≥40 chars in current or previous turn (thin-context refusal)
- Assignee missing AND no memory rule resolves it
- List ambiguous (no alias hit AND no single high-confidence fuzzy match)
- Resolved assignee is deactivated
- **Connection not configured** (`config.connection.configured != true`) — HALT with "connection not configured — run `/clickup:connect` first" (per Step 2.5; never silently pick a transport in `--auto`).
- **Capability gap with no silent fix** — the ticket needs a field the resolved transport can't set (e.g. `task_type=bug` on `clickup-cli`) AND no more-capable transport is available to borrow AND `connection.auto_borrow != true`. `--auto` does NOT borrow across transports silently (the unattended user can't see the hop). Refuse with the one-liner in `references/connection.md` → Degradation tier 3. (Interactive mode instead surfaces the borrow in the preview `Degrades:` row.)

The spirit of `--auto` is "save with whatever exists." If what exists is too little to produce a non-garbage ticket, it's better to refuse than to fabricate.

---

## Preview + edit (interactive mode only)

Render compact draft in a monospace block:

```
Title:    <title>
List:     <list name> (<alias>)
Assignee: <full name>
Priority: <priority>
Status:   <status>
Type:     <task|bug|...>
Tag:      <tag or "none">
Degrades: <only if a capability borrow/degradation applies, e.g. "clickup-cli can't set task_type=bug → will borrow mcp for this create">
```

The `Degrades:` line is rendered ONLY when the resolved transport cannot natively satisfy a requested field (see `references/connection.md` → Degradation) — it makes any cross-transport borrow visible before the create. Omit the line entirely when the active transport satisfies everything.

Offer: `[1] Confirm & create  [2] Edit field(s)  [3] Cancel`.

**Edit**: multi-select — user picks one or more fields; skill re-prompts only those. Mutations persist in a draft object (do NOT regenerate the preview from source — that would silently revert prior edits).

After any edit, redraw the preview and repeat. Cancel deletes the draft snapshot.

---

## Files (user state, OUTSIDE the plugin dir — survives `/plugin update`)

- `~/.claude/shared/identity.json` — **SHARED with `/g-event`**. User profile + teammate roster (first_name, latin_alias, full_name, email, external_ids, active, sources, last_validated_at). Both skills read and append.
- `~/.claude/clickup/config.json` — clickup-local. Workspace, lists + aliases, defaults, behavior flags, and the **`connection` block** (chosen transport + fallback order + probe cache + `rest_token_ref` POINTER — never a token value). No `user` or `teammates` here. See `references/config-schema.md` → `connection`.
- `~/.claude/clickup/memory.md` — learned patterns + corrections (markdown, human-editable).
- `~/.claude/clickup/drafts/` — per-invocation idempotency snapshots (also hold the post-create `task_id`/`url` retry anchor).

**Secrets:** a ClickUp token (for REST or referenced from `clickup-cli`) is NEVER written to any file, draft, snapshot, status output, or chat — `config.connection.rest_token_ref` holds only a pointer (`env:<NAME>` or `cli-config`). See `references/connection.md` → Secret handling.

All JSON writes use atomic `tmp + fsync + os.replace` under `fcntl.flock` on a sentinel file. The canonical identity.json lock is **`~/.claude/shared/identity.json.lock`** (NO leading dot — sibling of `identity.json`, not a dotfile). This path is the cross-plugin contract shared with `/g-event`; any deviation breaks mutual exclusion. See the reference helper in `references/config-schema.md`. Readers preserve unknown keys on rewrite (forward-compat with `/g-event` fields this plugin doesn't know about).

Schemas + examples in `references/config-schema.md`.

---

## See also

- `references/connection.md` — transports, the `op.*` capability contract, per-transport realization, capability/degradation matrix, the resolver, and secret handling. **The only file that names a transport primitive.**
- `references/modes.md` — detailed flow for every mode (including `## connect`)
- `references/ticket-format.md` — title + description rules with examples and anti-patterns
- `references/config-schema.md` — config.json (incl. the `connection` block) and memory.md formats
