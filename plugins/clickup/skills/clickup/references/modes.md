# /clickup modes

Detailed flow for each mode. Load only the section for the current invocation.

## Table of contents

- [default](#default) — interactive ticket create
- [auto](#auto) — silent create with defaults
- [onboard](#onboard) — full wizard (identity → workspace)
- [onboard-identity](#onboard-identity) — shared identity wizard only
- [onboard-workspace](#onboard-workspace) — clickup-local wizard only
- [memory](#memory) — manage learned patterns
- [status](#status) — health check of both files
- [workspace](#workspace) — switch active ClickUp workspace

---

## default

Interactive ticket creation. Required-field gating. Preview confirmation.

### Flow

1. **Extract from source context** (current conversation, pasted text, attached message):
   - Intent (what the ticket is about)
   - Beneficiary role (for the Connextra line — see `ticket-format.md`)
   - Bug signals (keywords that suggest `task_type=bug`)
   - Priority signals (urgent / ASAP / P0 / high / low)
   - Proposed solution (if user described one)
   - Acceptance criteria (if user listed them)
   - Links (URLs, meetings, PR refs)
   - Requester (name/role)
   - List name or alias (if mentioned)
   - Assignee first name (if mentioned)

2. **Mark each extraction**: `found` with value, or `missing`.

3. **Resolve list** (see `SKILL.md` → Resolution rules → List).

4. **Resolve assignee** (see `SKILL.md` → Resolution rules → Assignee).

5. **Ask only the missing must-haves** (consolidated single `AskUserQuestion` round):
   - Assignee (if unresolved)
   - List (if ambiguous)
   - Beneficiary role (if missing AND source hints at one)

   Skip questions for fields ClickUp owns natively unless user explicitly opts in.

6. **Duplicate check** (see `SKILL.md` → Resolution rules → Duplicate detection).

7. **Compose title** (see `ticket-format.md` → Title rules).

8. **Compose description** (see `ticket-format.md` → Description rules).

9. **Preview** in the format from `SKILL.md` → Preview + edit.

10. **User confirms** → call `mcp__clickup__clickup_create_task` with:
    - `list_id` (from resolved list)
    - `name` (title)
    - `markdown_description` (full description with hidden idempotency marker)
    - `assignees` (array of user_ids)
    - `priority` (normal/high/urgent/low)
    - `status` (backlog)
    - `task_type` (task/bug/milestone/feature)
    - `tags` (if any)
    - Start/due dates (if any)

11. **Return task URL** + a one-line summary.

12. **Offer memory save**: if the user corrected any field materially (e.g., changed title verb, changed assignee from suggestion), ask: "Save this as a memory rule for next time?" On yes, append to `memory.md`.

---

## auto

Silent create. Skip gating. No preview.

### Flow

1. **Safety net check first** (see `SKILL.md` → `--auto` safety net). If any refuse-condition hits, HALT with one-line reason.

2. **Extract + resolve** exactly as in `default` mode steps 1–4, but never ask questions. Use defaults + memory rules for everything unresolved.

3. **Duplicate check** at the `--auto` threshold (≥90% overlap blocks; surface 1-liner "possible duplicate: <url> — proceeding").

4. **Compose title + description** exactly as in `default`.

5. **Create immediately** via `mcp__clickup__clickup_create_task`.

6. **Return task URL** + 2-line summary (title + resolved fields).

No memory-save prompt in `--auto` (by design — the user is optimizing for speed, not learning).

---

## onboard

Full wizard. Runs `onboard-identity` → `onboard-workspace` back-to-back. Skips whichever slice is already complete.

1. If `~/.claude/shared/identity.json` missing or `onboarding_complete != true` → run [onboard-identity](#onboard-identity).
2. If `~/.claude/clickup/config.json` missing or `onboarding_complete != true` → run [onboard-workspace](#onboard-workspace).
3. If a ticket seed was carried in, resume [default](#default) with that seed.

---

## onboard-identity

Writes `~/.claude/shared/identity.json` — **shared with `/create-call`**. Read-only for every subsequent skill that needs user + teammates.

### Flow

1. **Verify MCP auth (best-effort).** If ClickUp MCP is connected, teammate enrichment is fast and rich. If disconnected or auth broken, **do NOT HALT** — proceed with identity-only (name + email). Print a one-line banner: "`ClickUp MCP offline — identity captured; run /clickup --onboard identity again online to enrich teammates.`" Teammates get added lazily as the user invokes `/clickup <name>` and the resolver misses.

2. **Ask identity** (single `AskUserQuestion` round, 2 questions):
   - Your full name
   - Your work email

3. **Resolve user_id** via `mcp__clickup__clickup_resolve_assignees` using the provided email (MCP-connected only). Store under `user.external_ids.clickup`. If MCP is offline, leave `external_ids` empty — fills on next online run.

4. **Fetch teammates** via `mcp__clickup__clickup_get_workspace_members` (MCP-connected only; default workspace — full workspace selection happens in `onboard-workspace`). For each member:
   - Derive `first_name` (split on first whitespace).
   - Build record: `{first_name, latin_alias, full_name, email, external_ids: {clickup: <user_id>}, active: true, sources: ["clickup"], last_validated_at: <now>}`.
   - **Batch Cyrillic alias prompts**: collect ALL Cyrillic/non-Latin `first_name`s into one consolidated `AskUserQuestion` round — ask user to confirm `latin_alias` for each in a single batch (one question per teammate is rendered as ONE question card with sub-items, NOT N separate rounds). Single shortcut: if user types "skip" for any teammate, alias = first_name lowercased and ASCII-stripped.
   - **Preserve unknown keys**: if a teammate record already exists in identity.json (seeded earlier by `/create-call` manual add), upsert by email — merge fields, preserve any keys this skill doesn't know about, bump `last_validated_at`, append `"clickup"` to `sources`.

5. **Write via atomic helper** (see `config-schema.md` → "Reference write helper"). Use `fcntl.flock` on `~/.claude/shared/.identity.json.lock` for the entire read-modify-write. Set `schemaVersion: 1`, `onboarding_complete: true`, `updated_at: <now>`.

6. **Identity wizard never touches create-call-only fields** — if a teammate has fields added by `/create-call` (e.g., future `external_ids.google`), keep them intact.

### Resumption

If the user interrupts mid-flow, `onboarding_complete` stays `false` in identity.json. Any subsequent invocation of either skill detects this, prints "Identity onboarding incomplete — resuming", and continues.

---

## onboard-workspace

Writes `~/.claude/clickup/config.json` (clickup-local). Assumes `~/.claude/shared/identity.json` is complete; if not, redirects to [onboard-identity](#onboard-identity) first.

### Flow

1. **List workspaces** via `mcp__clickup__clickup_get_workspace_hierarchy`. If >1, `AskUserQuestion` to pick. Store `workspace.id` + `workspace.name`.

2. **Fetch recent lists** for the chosen workspace. Offer the top 10 most-used lists (inferred from user's recent task activity if available; otherwise all lists in spaces user has touched).
   - First consolidated `AskUserQuestion` round: user picks which of the top 10 they want aliased (multi-select).
   - Second consolidated `AskUserQuestion` round: one card per picked list, asking for aliases (free-text, comma-separated). If 5 lists were picked, this is ONE round with 5 questions, NOT 5 sequential rounds.
   - Example: `[Meetings Bot] Project` → `MNB, MN Service, MN, meetings bot`.
   - Default alias if user types "skip": lowercased name stripped of brackets.

3. **Confirm defaults** (show, allow override):
   - `priority`: `normal`
   - `status`: `backlog`
   - `task_type`: `task`
   - `language`: `en` (forced, no override)

4. **Write config** to `~/.claude/clickup/config.json` via atomic helper + flock on `~/.claude/clickup/.config.json.lock`. Fields: `schemaVersion: 1`, `onboarding_complete: true`, `updated_at: <now>`, `workspace`, `lists`, `defaults`, `behavior: {}`.

5. **If switching workspaces** (the user had a different `workspace` before): any teammates in `identity.json` whose `external_ids.clickup` is NOT in the new workspace's member list get `active: false`. Surface this as a banner. Do not delete — other skills (like `/create-call`) still use the email + name.

6. **If a ticket seed was carried in**, resume [default](#default) now.

---

## memory

Manage learned patterns in `~/.claude/clickup/memory.md`.

### Subcommands

- `--memory` (no subcommand) → `list` (default)
- `--memory list` → print all entries with added_at + last_applied_at + application_count
- `--memory add "<rule>"` → append a new entry with `added_at: <now>`, `last_applied_at: null`, `application_count: 0`
- `--memory remove <id>` → remove entry by ID (shown in `list`)
- `--memory clear` → wipe all entries (require confirmation)

### Rule format (one per section in memory.md)

```markdown
## rule-<id>
**Rule:** Assign all auth-related tickets to Andy.
**Pattern:** source text mentions "auth", "login", "password", "oauth"
**Action:** set assignee = Andy
**Added:** 2026-04-22
**Last applied:** 2026-04-20
**Applied count:** 7
```

### Apply logic (read by default + auto modes)

On each run, after extraction, scan memory rules. For each rule where `Pattern` matches source text, apply its `Action` — unless the user has explicitly overridden that field in this invocation. Increment `Applied count` and update `Last applied`.

### Staleness

On `--status` or when pre-flight banner triggers, flag:
- Rules unused in last 60 days → "candidate for removal"
- Rules applied >20 times → "confirmed useful, leave alone"

---

## status

Health check across BOTH files. Read-only.

### Output

```
/clickup status
─────────────────────────────────────
identity.json    (~/.claude/shared/)
  User:          Sashko Marchuk <sasha@…>
  Teammates:     18  (3 validated >7 days ago — auto-refresh pending)
  Schema:        v1  ✓
  Shared with:   /clickup, /create-call

clickup/config.json
  Workspace:     Speed&Functions (id: 90151491867)
  Lists:         7 aliased
  Config age:    12 days  (OK — refresh at 30)
  Schema:        v1  ✓

Memory rules:    5 active, 1 stale (unused >60 days)
MCP auth:        OK (last verified: 12s ago)
Drafts:          2 pending (cleanup with /clickup --memory clear-drafts)
```

Never mutates state. Safe to run any time.

---

## workspace

Switch the active ClickUp workspace. Only mutates `~/.claude/clickup/config.json` (workspace + lists). Teammates in shared `identity.json` keep their email + name; only their `active` flag flips.

### Flow

1. Call `mcp__clickup__clickup_get_workspace_hierarchy` to list all workspaces the current auth has access to.
2. Present as an `AskUserQuestion` (single-select).
3. On pick, atomically update `~/.claude/clickup/config.json` with new `workspace.id` + `workspace.name`. Re-fetch lists for the new workspace; replace `lists[]`.
4. **Fetch new workspace members**. For each teammate in `~/.claude/shared/identity.json`:
   - If their `external_ids.clickup` IS in the new workspace → bump `last_validated_at`, ensure `active: true`.
   - If their `external_ids.clickup` is NOT in the new workspace → set `active: false`, keep all other fields (email, name, `/create-call` still uses them).
5. Prompt: "Run `/clickup --onboard workspace` if you want to refresh lists + add aliases for this workspace."
