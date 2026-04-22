---
name: clickup
description: ClickUp ticket creation, modification, and workspace management with enforced quality standards. Creates consistent tickets using Connextra user stories, evidence-only descriptions, fuzzy list aliases, first-name teammate resolution, bug-keyword type inference, priority-keyword inference, duplicate detection, idempotent create, and preview-and-edit confirmation. Includes a two-step onboarding wizard, persistent user config + memory files, and a stale-config reminder. Use when the user types /clickup, /clickup --auto, /clickup --onboard, /clickup --memory, /clickup --status, /clickup --workspace, or says "create a ticket", "add to backlog", "put in ClickUp", "make a task", "file a bug in ClickUp", "create a ClickUp task", or references a ClickUp list, task, or workflow.
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
| `--status` | Config health check (both files) | `references/modes.md#status` |
| `--workspace` | Switch active ClickUp workspace | `references/modes.md#workspace` |

**Precedence on conflict:** `--onboard` > `--status` > `--memory` > `--workspace` > `--auto` > default. Flag arguments are space-separated (`--onboard identity`, not `--onboard=identity`). Positional args after flags are the ticket-seed text.

## Step 2: Pre-flight (every invocation, in order)

1. **Read shared identity** from `~/.claude/shared/identity.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "identity missing — run `/clickup --onboard` first" (don't drag user into interactive onboarding mid-auto).
   - In interactive mode: redirect to `--onboard identity` with one-line explanation; carry the original request as ticket seed.
2. **Read clickup config** from `~/.claude/clickup/config.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "config missing — run `/clickup --onboard workspace` first".
   - In interactive mode: redirect to `--onboard workspace`; carry the ticket seed.
3. **Validate schemaVersion** — both files must have integer `schemaVersion` ≤ the version this skill understands (currently `1`). On higher version: refuse to write, degrade to read-only with a banner. On corrupt JSON: quarantine to `<file>.corrupt-<epoch>` and re-onboard.
4. **Read memory** from `~/.claude/clickup/memory.md`. Apply rules. If any rule is unused >60 days or applied >20 times, prepend a one-line review banner: "`💡 N memory rules may be stale — run /clickup --memory list`".
5. **Check config freshness.** If `config.updated_at` > 30 days ago, prepend: "`💡 Config is 30+ days old — run /clickup --onboard to refresh`". Non-blocking.
6. **Verify ClickUp MCP auth.** On 401 / timeout / disconnected MCP, HALT with re-auth instructions. **Never fabricate a success URL.**
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
| Priority | `normal` | urgent/ASAP/P0/burning → urgent; "high priority"/P1 → high; "low priority"/P3 → low |
| Status | `backlog` | only if user explicitly names another status |
| Task type | `task` | bug signals: `bug`, `broken`, `fails`, `failing`, `regression`, `crash`, `500`, `error`, `doesn't work`, `not working` → propose `bug`, confirm in preview |
| Tag | none | source names one, or memory rule applies |
| Dates | none | never inferred |
| Custom fields | skipped | only if user explicitly asks |

---

## Resolution rules

### Assignee (dual-key resolver, teammates live in shared identity.json)

The roster lives in `~/.claude/shared/identity.json` under `teammates[]`. `/create-call` reads the same file — changes here are seen there.

**Homoglyph-collision gate (runs before every silent single-match)**: compute the UTS #39 skeleton of the typed input (`unicodedata.normalize("NFKC", s).casefold()` + confusables-map transform). If the skeleton matches an EXISTING teammate AND raw byte-strings differ (i.e. visually identical but distinct records), FORCE disambiguation — never silent-match. Legitimate pure-script names (all-Cyrillic, all-Latin) never trigger this (no skeleton collision with anyone else). Only lookalike collisions trigger it. This precedence is load-bearing and overrides any "silent-allow" rule elsewhere.

1. NFC-normalize the typed name; strip leading/trailing whitespace (`re.sub(r"[\s​‌‍⁠﻿]+", "", ...)` — ASCII + zero-width + BOM); strip emoji. Use `str.casefold()` (NOT `.lower()`) for all case-insensitive comparisons (handles Turkish İ/i; German ß/ss correctly).
2. **First pass** — casefold match against `teammates[].latin_alias`. (ASCII common case — most hits land here.)
3. **Second pass** — casefold + NFC match against `teammates[].first_name`. (Cyrillic users typing their own name.)
4. **Third pass** — casefold match on `teammates[].email` (when user typed an email).
5. **Single match** → fill silently.
6. **Multiple matches** → prompt disambiguation (show full names + emails).
7. **Zero matches** → freeform prompt for full email. Validate against `^[^@\s"'\\<>]+@[^@\s"'\\<>]+\.[^@\s"'\\<>]+$` AND reject any domain with non-ASCII characters (IDNA mixed-script attack defense). On failure, re-prompt with the reason. On valid email, upsert into `teammates[]` with `sources: ["manual"]` + `last_validated_at: null` via the atomic write helper. A later MCP refresh will enrich with `external_ids.clickup` + `full_name`.
8. **Re-validation guard**: before assigning, check `teammate.active == true`. On deactivated user, block; force re-prompt.
9. In `--auto`: if ambiguous or deactivated AND no memory rule resolves unambiguously → refuse with one-line reason.

### List (alias → fuzzy hierarchy)

1. Match user-named list (case-insensitive) against `config.lists[].aliases`.
2. **Alias hit** → resolve to stored `list_id`; verify still exists and not archived via `mcp__clickup__clickup_get_list`. If renamed, update alias silently. If archived/missing, refuse with "list not found — re-onboard."
3. **No alias hit** → call `mcp__clickup__clickup_get_workspace_hierarchy`, fuzzy-match top 3 candidates, surface for user confirm.
4. In `--auto`: if no alias hit AND no single high-confidence fuzzy match → refuse.

### Duplicate detection (before create)

1. Search open tickets in target list via `mcp__clickup__clickup_filter_tasks` (include_closed=false).
2. Compute lemmatized token overlap between candidate title and each open ticket's title.
3. **Interactive mode**: surface top 3 at ≥70% overlap. User picks `create anyway` / `link to existing` / `cancel`.
4. **`--auto` mode**: only block at ≥90% overlap. Below that, proceed silently.
5. Also compare source-language keywords (before translation) to catch cross-language dupes.

### Idempotency (retry safety)

1. Generate UUID idempotency key per invocation.
2. **Before** calling `mcp__clickup__clickup_create_task`, write draft to `~/.claude/clickup/drafts/<uuid>.json`.
3. Include the key as a marker in the ticket description (hidden HTML comment: `<!-- ck:<uuid> -->`) so retries can find partial successes.
4. On create timeout/error, search the list for the key before re-creating.

---

## `--auto` safety net (refuse conditions)

Refuse creation with a one-line reason when any of these hold:

- No source context ≥40 chars in current or previous turn (thin-context refusal)
- Assignee missing AND no memory rule resolves it
- List ambiguous (no alias hit AND no single high-confidence fuzzy match)
- Resolved assignee is deactivated

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
```

Offer: `[1] Confirm & create  [2] Edit field(s)  [3] Cancel`.

**Edit**: multi-select — user picks one or more fields; skill re-prompts only those. Mutations persist in a draft object (do NOT regenerate the preview from source — that would silently revert prior edits).

After any edit, redraw the preview and repeat. Cancel deletes the draft snapshot.

---

## Files (user state, OUTSIDE the plugin dir — survives `/plugin update`)

- `~/.claude/shared/identity.json` — **SHARED with `/create-call`**. User profile + teammate roster (first_name, latin_alias, full_name, email, external_ids, active, sources, last_validated_at). Both skills read and append.
- `~/.claude/clickup/config.json` — clickup-local. Workspace, lists + aliases, defaults, behavior flags. No `user` or `teammates` here.
- `~/.claude/clickup/memory.md` — learned patterns + corrections (markdown, human-editable).
- `~/.claude/clickup/drafts/` — per-invocation idempotency snapshots.

All JSON writes use atomic `tmp + fsync + os.replace` under `fcntl.flock` on a sentinel file — see the reference helper in `references/config-schema.md`. Readers preserve unknown keys on rewrite (forward-compat with `/create-call` fields this plugin doesn't know about).

Schemas + examples in `references/config-schema.md`.

---

## See also

- `references/modes.md` — detailed flow for every mode
- `references/ticket-format.md` — title + description rules with examples and anti-patterns
- `references/config-schema.md` — config.json and memory.md formats
