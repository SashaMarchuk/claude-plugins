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

This flow is **identical in both `/clickup` and `/create-call`** — onboarding from either skill produces the same identity.json populated from the maximum set of sources available on this machine. Running it from either side is equivalent; the other skill just inherits the result.

### Flow

#### Step 1 — Check existing state

- If `identity.json` exists AND `onboarding_complete: true` AND user invoked `--onboard identity` explicitly (forced re-run) → proceed with warning: "Identity already complete. Re-running refreshes teammates from all available sources; existing teammates are preserved (unknown keys round-tripped)."
- If missing or incomplete → proceed.

#### Step 2 — Ask identity (single `AskUserQuestion` round, 2 questions)

- Your full name
- Your work email

Seed the skeleton: `{schemaVersion: 1, user: {name, email, external_ids: {}}, teammates: [], onboarding_complete: false, updated_at: <now>}`.

#### Step 3 — **Confirm user identity ACROSS sources** (before teammate search)

Probe every available source for the user's own identity and echo back what was found:

- **ClickUp MCP** (best-effort): `mcp__clickup__clickup_resolve_assignees` with the email. If a single match → capture `clickup_user_id`. If multiple matches → `AskUserQuestion` to pick. If zero → note "ClickUp didn't find this email" and continue without `clickup_user_id`.
- **Google Workspace CLI** (best-effort): `npx @googleworkspace/cli calendar calendars get --params '{"calendarId":"primary"}' 2>/dev/null` — the primary calendar's `id` IS the authed user's email. If it matches the user-supplied email → good; if not → warn "Primary Google account is `<other>` — may not see your calendar events in teammate discovery. Continue anyway?".

Show a single confirmation `AskUserQuestion`:

```
Identified as:
  Full name:   <as typed>
  Work email:  <as typed>
  ClickUp:     <resolved name + user_id OR "not found">
  Google:      <primary calendar email OR "CLI not authed">

Is this you? [Yes, continue / Pick different ClickUp record / Fix email / Skip source confirmation]
```

If user picks "Fix email" → re-prompt email, re-probe. If "Skip" → continue with name+email only, no `external_ids`, teammate search limited to sources that don't need user-identity.

**Do not proceed to step 4 without this confirmation** — garbage identity poisons all downstream source queries.

#### Step 4 — Discover teammates from ALL available sources (in parallel, then merge)

Every source that is live contributes. None are required. Run all in parallel; collect per-email.

**Source A — ClickUp workspace members** (needs ClickUp MCP):

`mcp__clickup__clickup_get_workspace_members` on default workspace. For each member: `first_name` (split on first whitespace), `full_name`, `email`, `clickup_user_id`. Tag sources entry: `"clickup-workspace"`.

**Source B — ClickUp task collaborators** (needs ClickUp MCP + `user.external_ids.clickup`):

Rationale: the user asked to use "usi tasks de ya → usi assignees → ce moyi teammates." This catches contractors and cross-workspace collaborators who aren't in the current workspace's member roster.

`mcp__clickup__clickup_filter_tasks` with `assignees=[user.external_ids.clickup]`, `include_closed=false`, page size 100. For each returned task, collect `assignees[]` (and `creator` if surfaced). Union by `user_id`. Enrich missing fields with a second `clickup_get_workspace_members`-style lookup if needed. Tag sources: `"clickup-tasks"`.

If API returns ≥100 tasks, warn: "Found 100+ tasks; teammate roster may be incomplete. Re-run later to capture more." (Avoid infinite pagination in onboarding.)

**Source C — Google Calendar attendees, last 14 days** (needs Google Workspace CLI authed):

Rationale: small-meeting attendees are almost always real teammates, not conference rooms or mailing lists.

Compute `timeMin` / `timeMax` in Python (portable across macOS/Linux; no reliance on BSD vs GNU `date(1)` flags):

```python
import datetime
now = datetime.datetime.now(datetime.timezone.utc)
time_max = now.strftime("%Y-%m-%dT%H:%M:%SZ")
time_min = (now - datetime.timedelta(days=14)).strftime("%Y-%m-%dT%H:%M:%SZ")
```

Then query:

```bash
npx @googleworkspace/cli calendar events list \
  --params "$(python3 -c "import json,sys; print(json.dumps({'calendarId':'primary','timeMin':'$time_min','timeMax':'$time_max','singleEvents':True,'orderBy':'startTime','maxResults':2500}))")" \
  2>/tmp/gws_err.$$
rc=$?; err=$(cat /tmp/gws_err.$$); rm -f /tmp/gws_err.$$
```

On non-zero `rc`, classify `err` the same way as pre-flight step 5 (auth / rate-limit / other); never silently swallow.

For each returned event:

- If `attendees` array exists AND `user.email` IS in `attendees[].email` AND `attendees.length <= 15`:
  - For each attendee: take `email`, `displayName`, skip `resource: true` (rooms/equipment), skip `organizer: true` entries that match the user.
  - Derive `first_name` from `displayName` (split on whitespace) OR from email local-part before `.`/`@`.

Tag sources: `"google-calendar"`. The 15-person cap filters out large all-hands events that would flood the roster with loose acquaintances.

**Source D — Custom source** (optional, prompted):

`AskUserQuestion` after automatic sources finish:

```
Add teammates from another source?
  [Skip — I have enough]
  [Paste JSON list of {first_name, email} — I have it handy]
  [Name an MCP tool to query]
```

If "Paste JSON": accept a code-fence-delimited JSON array, parse, validate each entry has `email` + at least one of `first_name`/`full_name`/`displayName`.

If "Name an MCP tool": free-form tool name + params (e.g., `mcp__slack__list_workspace_users`). Skill attempts the call; on success parse results into teammate records; on failure fall back to next step.

Tag sources: `"custom:<label>"` where `<label>` is user-supplied or derived from the tool name.

**Source E — Manual entry** (always offered at the end):

`AskUserQuestion` with freeform textarea: "Add more teammates manually? (name + email pairs, one per line, or leave blank to skip)"

Parse lines of format `Name <email>` or `Name, email` or `Name; email`. Each entry gets `sources: ["manual"]` and `last_validated_at: null`.

#### Step 5 — Merge + deduplicate + flag review

Primary key: `email` (casefolded, NFC-normalized).

For each unique email across all sources, build one teammate record:

- `first_name` — priority: workspace > tasks > calendar > custom > manual (first non-null wins).
- `full_name` — same priority.
- `email` — canonical (casefolded).
- `external_ids.clickup` — from any ClickUp source (workspace or tasks).
- `active: true` if found in workspace; `true` still if only in tasks/calendar/custom (the user interacts with them); `false` only if explicitly deactivated later by `/clickup` workspace sync.
- `sources: [...]` — UNION of all source tags that discovered this email.
- `last_validated_at: <now>` if from any live source; `null` if manual-only.

**Flag review (only flagged entries — do NOT surface the full roster).** For each new teammate, compute these flags:

- `homoglyph`: UTS #39 skeleton of `first_name` OR email-local-part collides with an already-confirmed teammate (raw bytes differ). Typical attack: Cyrillic `а` vs Latin `a`.
- `external_domain`: email domain is NOT in user's own-email domain AND NOT in a known-safe domain list the user has already confirmed (track this in `identity.json` under `user.trusted_domains[]`, initialized at step 3 with the user's own `@domain`).
- `calendar_only`: teammate's `sources: ["google-calendar"]` only — no ClickUp corroboration. Low-trust tier.
- `new_custom`: teammate came from `"custom:<label>"` only.

Surface ONLY teammates with at least one flag in a single `AskUserQuestion` card:

```
Review flagged teammates (others accepted silently):
  ⚠ homoglyph  — Rachel (rаchel@corp.com) collides with existing Rachel (rachel@corp.com)
  ⚠ external   — Vendor Smith (vendor@external.io) — outside @speedandfunction.com
  ℹ calendar-only — Alex Kim (alex@somecorp.com) — from one meeting, not ClickUp

Actions (per teammate):
  [A] Accept — add to roster
  [R] Reject — don't add
  [T] Trust domain (for external) — add to trusted_domains[]; accept this + all current/future from same domain
```

If zero flags, skip the card entirely. Homoglyph-flagged teammates can NEVER be accepted without explicit user action — the resolver's homoglyph gate (see both SKILL.md files → "Homoglyph-collision gate") will still force disambiguation later even if the user accepts here. Flags + gate are defense-in-depth.

#### Step 6 — Source summary report

Print a compact summary (not interactive):

```
Discovered N unique teammates across M sources:
  ClickUp workspace:        X
  ClickUp task collaborators: Y  (Z new beyond workspace)
  Google Calendar (14d):    W  (V new beyond ClickUp)
  Custom (<label>):         U
  Manual:                   T
```

If any source surfaced a teammate the others missed, highlight that as "possible external contractor / contact" — useful for user review.

#### Step 7 — Batch Cyrillic alias confirmation (single textarea card)

Collect ALL teammates with non-Latin `first_name` (regex: `[^\x00-\x7F]`). Render ONE `AskUserQuestion` card (NOT N separate rounds, NOT "sub-questions" — that's not a native primitive).

The card shows a textarea with pre-filled defaults (one teammate per line, `first_name → latin_alias`), user edits inline:

```
Confirm Latin aliases for non-Latin teammates (edit the right side; leave as-is to accept):
  Михайло → Mykhailo
  Сергій → Serhii
  Олена → Olena
  Дарія → Daria
  …
```

Default transliteration uses Python's `unicodedata.normalize("NFKD", name)` then strip combining marks, then pass through a Cyrillic→Latin table:

```python
CYRILLIC_TO_LATIN = {
    "а":"a","б":"b","в":"v","г":"h","ґ":"g","д":"d","е":"e","є":"ie","ё":"io",
    "ж":"zh","з":"z","и":"y","і":"i","ї":"i","й":"i","к":"k","л":"l","м":"m",
    "н":"n","о":"o","п":"p","р":"r","с":"s","т":"t","у":"u","ф":"f","х":"kh",
    "ц":"ts","ч":"ch","ш":"sh","щ":"shch","ъ":"","ы":"y","ь":"","э":"e","ю":"iu","я":"ia",
}
def translit(name):
    out = []
    for ch in name:
        lo = ch.casefold()
        if lo in CYRILLIC_TO_LATIN:
            t = CYRILLIC_TO_LATIN[lo]
            out.append(t.capitalize() if ch.isupper() and t else t)
        elif ch.isascii():
            out.append(ch)
        else:
            out.append("")  # unknown non-ASCII → drop
    return "".join(out).strip()
```

If the transliteration yields an empty string (e.g. all-emoji or all-symbol name), fall back to the email local-part before `@`.

**Single card. Single round. Textarea, not per-teammate questions.**

#### Step 8 — Write identity.json atomically

Via the `atomic_update` helper (see `config-schema.md` → "Reference write helper"). `fcntl.flock` on `~/.claude/shared/.identity.json.lock` for the entire read-modify-write. Set `schemaVersion: 1`, `onboarding_complete: true`, `updated_at: <now>`.

#### Step 9 — Preserve unknown keys (always)

If a teammate record already exists in identity.json (e.g. added by the other skill with extra fields like `external_ids.google` or `email_aliases`), upsert by email — merge known fields, preserve unknown keys, UNION `sources[]`, bump `last_validated_at`.

### Resumption

If the user interrupts mid-flow, `onboarding_complete` stays `false` in identity.json. Any subsequent invocation of either skill detects this, prints "Identity onboarding incomplete — resuming", and continues from the next unfinished step.

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
