# /create-call modes

Detailed flow for each mode. Load only the section for the current invocation.

## Table of contents

- [default](#default) — interactive create / update / cancel
- [auto](#auto) — silent create with defaults
- [onboard](#onboard) — full wizard (identity → calendar)
- [onboard-identity](#onboard-identity) — shared identity wizard only
- [onboard-calendar](#onboard-calendar) — create-call-local wizard only
- [status](#status) — health check of both files
- [calendar](#calendar) — switch active calendar

---

## default

Interactive mode. Detects intent (create / update / cancel) from the user's phrasing.

### Intent detection

| Intent | Signals | Route |
|---|---|---|
| **Create** | "schedule", "create", "set up", "book", "call with" | Create flow (Steps 1–5) |
| **Update** | "move", "reschedule", "change", "update", "add attendee" | Update flow (Step 6) |
| **Cancel** | "cancel", "delete", "remove" | Cancel flow (Step 7) |

If genuinely ambiguous, `AskUserQuestion` once to disambiguate.

### Create flow

1. **Extract from source**:
   - Title (imperative or noun phrase)
   - Date (absolute or relative — convert relative using `currentDate`)
   - Start time (parse "2pm", "6:45 AM ET", "14:00")
   - Duration (default from config, override signals: "15 mins", "1 hour")
   - Timezone (default from config, override: "in Kyiv time", "UTC")
   - Attendees (names to resolve)
   - Description / notes
   - Calendar override (if user named one)

2. **Resolve attendees** (see SKILL.md → Resolution rules → Attendee). For each name not in `~/.claude/shared/identity.json` → prompt, then upsert via atomic helper.

3. **Build attendee array**: start with `config.always_include[]` (notes bot), append resolved attendees, dedupe by email, exclude organizer (`identity.user.email`).

4. **Past-time guard** (see SKILL.md). `AskUserQuestion` if start is in the past.

5. **Conflict check** (see SKILL.md). Query Google Calendar, surface overlaps in preview.

6. **Compose title** (see `event-format.md` → Title rules).

7. **Preview + confirm** in the format from SKILL.md → Preview + edit.

8. **User confirms** → call `npx @googleworkspace/cli calendar events insert` with:
   - `calendarId`, `conferenceDataVersion: 1`, `sendUpdates: "all"`
   - Body: `summary`, `description`, `start {dateTime, timeZone}`, `end {dateTime, timeZone}`, `attendees`, `conferenceData.createRequest` (with `requestId` + `conferenceSolutionKey: {type: "hangoutsMeet"}`)

9. **Return**: title, time, Meet link, attendees, calendar link, event ID. The event ID is needed for future update/cancel.

### Update flow (Step 6)

User may provide event ID, or a title + approximate time.

1. **Find event** if no ID: `events list` with `q=<search term>` + time window. Multiple matches → `AskUserQuestion`.
2. **Apply update** via `events patch` — only include changed fields in the `--json` body.
3. Show updated summary.

### Cancel flow (Step 7)

1. **Find event** (same as update).
2. **Confirm**: `AskUserQuestion` "Cancel `<title>` on `<date>` at `<time>`? Attendees will be notified."
3. **Delete** via `events delete` with `sendUpdates: "all"`.

---

## auto

Silent create. Skip preview. No interactive prompts beyond the safety-net refusals.

### Flow

1. **Safety-net check first** (see SKILL.md → `--auto` safety net). On refuse condition, HALT with one-line reason.
2. **Extract + resolve** as in default Steps 1–3, but never ask questions. Use defaults for everything unresolved.
3. **Past-time refuse** — don't silently schedule in the past.
4. **Conflict check** at the `--auto` threshold (≥ 50% overlap blocks; < 50% surfaces "possible conflict" banner and proceeds).
5. **Create immediately** via `events insert`.
6. **Return** event URL + 2-line summary.

---

## onboard

Full wizard. Runs `onboard-identity` → `onboard-calendar` back-to-back. Skips whichever slice is already complete.

1. If `~/.claude/shared/identity.json` missing or `onboarding_complete != true` → run [onboard-identity](#onboard-identity).
2. If `~/.claude/create-call/config.json` missing or `onboarding_complete != true` → run [onboard-calendar](#onboard-calendar).
3. If a call seed was carried in, resume [default](#default) with that seed.

---

## onboard-identity

Writes `~/.claude/shared/identity.json` — **shared with `/clickup`**. Read-only for every subsequent skill that needs user + teammates.

> **Note**: if `/clickup` onboarding has already run on this machine, identity.json exists with a richer teammate roster (pulled from ClickUp workspace members). This wizard detects that state and skips to confirmation instead of re-prompting.

### Flow

1. **Check existing state**:
   - If `identity.json` exists AND `onboarding_complete: true` AND user says `--onboard identity` explicitly (forced re-run) → proceed but warn: "Identity already complete. Re-running will re-confirm your name + email. Teammates are preserved."
   - If missing → proceed.

2. **Ask identity** (single `AskUserQuestion` round, 2 questions):
   - Your full name
   - Your work email

3. **Try to enrich via ClickUp MCP** (best-effort):
   - If ClickUp MCP is connected: call `mcp__clickup__clickup_resolve_assignees` with the email to get `user_id`. Store under `user.external_ids.clickup`.
   - If not connected: leave `external_ids` empty — fills on next online run of `/clickup --onboard`.

4. **Try to enrich teammates via ClickUp MCP** (best-effort, same fallback):
   - If MCP connected: `mcp__clickup__clickup_get_workspace_members`. For each member, upsert into `teammates[]` keyed by email. For Cyrillic names, ask user to confirm `latin_alias` (same flow as clickup's `onboard-identity`).
   - If not connected: skip. Teammates get added lazily as the user invokes `/create-call <name>` and the resolver misses.

5. **Write via atomic helper** (see `config-schema.md`). Use `fcntl.flock` on `~/.claude/shared/.identity.json.lock`. Set `schemaVersion: 1`, `onboarding_complete: true`, `updated_at: <now>`.

6. **Preserve unknown keys** — if a teammate record already has `external_ids.google` or other fields added by a future plugin, keep them intact.

### Resumption

If interrupted, `onboarding_complete` stays `false`. Any subsequent `/clickup` or `/create-call` invocation detects this, prints "Identity onboarding incomplete — resuming", and continues.

---

## onboard-calendar

Writes `~/.claude/create-call/config.json`. Assumes `~/.claude/shared/identity.json` is complete; if not, redirects to [onboard-identity](#onboard-identity) first.

### Flow

1. **Auto-detect calendar + timezone**:
   - `npx @googleworkspace/cli calendar calendarList list --params '{}' 2>/dev/null` — list calendars the user can access.
   - `npx @googleworkspace/cli calendar settings get --params '{"setting":"timezone"}' 2>/dev/null` — resolve the primary calendar's timezone.

2. **Confirm defaults** (single `AskUserQuestion` round, consolidated):
   - Default calendar: show auto-detected primary, allow override.
   - Default timezone: show auto-detected, allow override (IANA names).
   - Default duration: `30` minutes (prefill, allow override).
   - Always-include notes-bot email: prefill `notes.bot@speedandfunction.com` (allow override OR "skip, I don't use a notes bot").

3. **Confirm behavior flags** (prefilled, allow override):
   - `confirm_before_create`: `true`
   - `check_conflicts`: `true`
   - `past_time_check`: `true`

4. **Write config** to `~/.claude/create-call/config.json` via atomic helper + flock on `~/.claude/create-call/.config.json.lock`. Fields: `schemaVersion: 1`, `onboarding_complete: true`, `updated_at: <now>`, `defaults`, `behavior`, `always_include[]`.

5. **If a call seed was carried in**, resume [default](#default) now.

---

## status

Health check across BOTH files. Read-only.

### Output

```
/create-call status
─────────────────────────────────────
identity.json    (~/.claude/shared/)
  User:          Sashko Marchuk <sasha@…>
  Teammates:     18
  Schema:        v1  ✓
  Shared with:   /clickup, /create-call

create-call/config.json
  Calendar:      primary
  Timezone:      America/New_York
  Duration:      30 min default
  Always-include: notes.bot@speedandfunction.com
  Schema:        v1  ✓

Google CLI auth:  OK (last verified: 4s ago)
Legacy shadow:    ~/.claude/skills/create-call/  ⚠  remove when done migrating
```

Never mutates state. Safe to run any time.

---

## calendar

Switch the active default calendar. Only mutates `~/.claude/create-call/config.json` (`defaults.calendar`).

### Flow

1. `npx @googleworkspace/cli calendar calendarList list --params '{}' 2>/dev/null` to fetch all calendars the current auth has access to.
2. `AskUserQuestion` (single-select) with the list.
3. On pick, atomic-write `defaults.calendar` in `~/.claude/create-call/config.json`.
4. Confirm: "Active calendar is now `<name>`. Future events default here unless overridden."
