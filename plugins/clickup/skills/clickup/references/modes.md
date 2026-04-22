# /clickup modes

Detailed flow for each mode. Load only the section for the current invocation.

## Table of contents

- [default](#default) — interactive ticket create
- [auto](#auto) — silent create with defaults
- [onboard](#onboard) — two-step setup wizard
- [memory](#memory) — manage learned patterns
- [status](#status) — config health check
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

Two-step wizard. Must run once per user. Writes `~/.claude/clickup/config.json`.

### Step 1 — Identity (minimal)

Ask (one `AskUserQuestion` round, 2 questions):
- Your full name
- Your work email

Write partial config with `onboarding_complete: false` and `step_1_done_at: <ts>`.

### Step 2 — Workspace research + confirmation

1. **Verify MCP auth.** If broken, prompt to authenticate first.

2. **Resolve user_id** via `mcp__clickup__clickup_resolve_assignees` using the provided email.

3. **List workspaces** (the current MCP auth scope). If >1, ask user to pick. Store `workspace_id` + `workspace_name`.

4. **Fetch teammates** via `mcp__clickup__clickup_get_workspace_members`. For each:
   - Derive first name (split on first whitespace)
   - Store: `{first_name, latin_alias, full_name, email, user_id, active: true, last_validated_at: <ts>}`
   - For Cyrillic / non-Latin names, ask user to confirm a `latin_alias` (e.g., "Михайло" → alias "Misha"). Support single shortcut: if user types "skip" for any teammate, alias = first_name lowercased.

5. **Fetch recent lists** via `mcp__clickup__clickup_get_workspace_hierarchy`. Offer the top 10 most-used lists (inferred from user's recent task activity if available; otherwise all lists in spaces user has touched). For each picked list, ask for aliases (free-text, comma-separated):
   - Example: `[Meetings Bot] Project` → `MNB, MN Service, MN, meetings bot`
   - Default alias if user types "skip": lowercased name stripped of brackets.

6. **Confirm preferences** (show defaults, allow override):
   - Default priority: `normal`
   - Default status: `backlog`
   - Default task type: `task`
   - Language: English (forced, no override)

7. **Write config** to `~/.claude/clickup/config.json` with `onboarding_complete: true`, `updated_at: <now>`. See `config-schema.md` for exact shape.

8. **If there was a pending ticket-seed** (user started with `/clickup <request>` but had no config), resume default mode now with the stored seed text.

### Resumption

If user interrupts mid-step-2 and returns later, `onboarding_complete` stays `false`. Any non-`--onboard` invocation detects this, prints "Onboarding incomplete — resuming step 2", and continues from where it left off.

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

Health check. Read-only.

### Output

```
/clickup status
─────────────────────────────────────
User:         Sashko Marchuk <sasha@…>
Workspace:    Speed&Functions (id: 90151491867)
Config age:   12 days  (OK — refresh at 30)
Teammates:    18  (3 validated >7 days ago — auto-refresh pending)
Lists:        7 aliased
Memory rules: 5 active, 1 stale (unused >60 days)
MCP auth:     OK (last verified: 12s ago)
Drafts:       2 pending (cleanup with /clickup --memory clear-drafts)
```

Never mutates state. Safe to run any time.

---

## workspace

Switch the active ClickUp workspace.

### Flow

1. Call `mcp__clickup__clickup_get_workspace_hierarchy` to list all workspaces the current auth has access to.
2. Present as an `AskUserQuestion` (single-select).
3. On pick, update `config.workspace_id` + `config.workspace_name`; re-validate teammates and lists against the new workspace (may invalidate some entries — surface them).
4. If teammates/lists differ significantly from cached values, prompt: "Run `/clickup --onboard` to refresh teammates and lists for this workspace."
