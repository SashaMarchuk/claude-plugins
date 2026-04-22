---
name: create-call
description: Google Calendar event management with Google Meet. Creates, updates, and cancels events via `npx @googleworkspace/cli`. Always attaches a configurable notes bot, checks for conflicts before creating, guards against past-time typos, and resolves attendee names against the shared `~/.claude/shared/identity.json` teammate roster (same file `/clickup` uses). Two-step onboarding writes `~/.claude/create-call/config.json` (calendar defaults + always-include list) and shares user + teammates with `/clickup`. Use when the user types `/create-call`, `/create-call --auto`, `/create-call --onboard`, `/create-call --status`, `/create-call --calendar`, or says "schedule a call", "set up a meeting", "book a call with X", "move the meeting to Y", "cancel the Z call", or references a Google Meet / Calendar event.
---

# /create-call

Universal skill for scheduling, updating, and cancelling Google Calendar events. Enforces consistent title conventions, always attaches configured notes-bot attendees, and pulls teammates from the same shared roster `/clickup` uses — so names you've already taught `/clickup` just work here too.

## Step 1: Parse $ARGUMENTS

| Flag | Mode | Details |
|---|---|---|
| (none) | Interactive create / update / cancel | `references/modes.md#default` |
| `--auto` | Silent create with defaults | `references/modes.md#auto` |
| `--onboard` | Full wizard (identity + calendar) | `references/modes.md#onboard` |
| `--onboard identity` | Re-run shared identity wizard only | `references/modes.md#onboard-identity` |
| `--onboard calendar` | Re-run create-call-local wizard only | `references/modes.md#onboard-calendar` |
| `--status` | Config health check (both files) | `references/modes.md#status` |
| `--calendar` | Switch active calendar (primary ↔ other) | `references/modes.md#calendar` |

**Precedence on conflict:** `--onboard` > `--status` > `--calendar` > `--auto` > default. Flag arguments are space-separated (`--onboard identity`, not `--onboard=identity`). Positional args after flags are the call-seed text.

## Step 2: Pre-flight (every invocation, in order)

1. **Shadow check FIRST.** If `~/.claude/skills/create-call/` exists (legacy user-level skill), the user-level skill wins over the plugin by Claude Code precedence — meaning if you're reading THIS, the legacy is NOT installed (good) or the user has already disabled it. Still, if the directory exists, prepend a loud banner on every invocation until it's gone:
   > `⚠ Legacy ~/.claude/skills/create-call/ still exists — this plugin won't take full effect until you remove it: rm -rf ~/.claude/skills/create-call`
   
   Do not HALT — the plugin can still function (the user may have intentionally disabled model-invocation on the legacy skill). But the warning is non-dismissible until the directory is gone.

2. **Read shared identity** from `~/.claude/shared/identity.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "identity missing — run `/create-call --onboard` first" (don't drag the user into interactive onboarding mid-auto).
   - In interactive mode: redirect to `--onboard identity` with one-line explanation; carry the original request as a call seed to resume after onboarding.

3. **Read create-call config** from `~/.claude/create-call/config.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "config missing — run `/create-call --onboard calendar` first".
   - In interactive mode: redirect to `--onboard calendar`; carry the seed.

4. **Validate schemaVersion** — both files must have integer `schemaVersion` ≤ the version this skill understands (currently `1`). On higher version: refuse to write, degrade to read-only with a banner. On corrupt JSON: quarantine to `<file>.corrupt-<epoch>` and re-onboard.

5. **Verify Google Workspace CLI auth.** Run `npx @googleworkspace/cli calendar calendars get --params '{"calendarId":"primary"}' 2>/dev/null | head -1`. On 401 / 403 / timeout, HALT with: "Run `! npx @googleworkspace/cli auth login --services calendar,people` and retry."

6. **Pending-seed resumption.** If a seed was carried from step 2 or step 3 (identity or calendar wizard just completed), resume default flow with that seed now.

## Step 3: Route by flag

Load the referenced section from `references/modes.md` before acting. Each mode has its own deterministic flow.

---

## Core rules (apply in EVERY mode that creates or edits an event)

Full rules + worked examples in `references/event-format.md`. Enforce:

**Title** — imperative or noun phrase. English. ≤120 chars. No bracket prefixes like `[Meeting]`, no `Re:`/`Fwd:`. If source names a project, include it naturally (not as a prefix).

**Description** — optional. If provided, short (1–3 lines). Include the meeting link + any referenced doc; nothing else.

**Timezone** — always use IANA names (`America/New_York`, `Europe/Kyiv`). Never hardcode `-04:00` / `-05:00` UTC offsets — Google handles DST.

**Attendees** — always start with the `always_include` list from `~/.claude/create-call/config.json` (typically the notes bot). Append user-requested attendees. **Never add the organizer** (`user.email` from identity.json) to the attendee list — Google auto-includes the organizer.

**Conference** — create Google Meet (`conferenceSolutionKey.type = "hangoutsMeet"`) unless user explicitly says "no video" or "phone only".

**Deduplication** — before creating, dedupe the attendee array by email (case-insensitive).

**Request ID** — derive from title-slug + unix timestamp (e.g., `weekly-sync-1712505600`) so retries don't collide.

---

## Defaults (applied unless user overrides in preview)

All values read from `~/.claude/create-call/config.json` → `defaults` + `always_include`.

| Field | Default source | Override signal |
|---|---|---|
| Calendar | `defaults.calendar` (`primary`) | "on my work calendar" / "use team calendar" |
| Timezone | `defaults.timezone` (`America/New_York`) | "in Kyiv time" / "UTC" |
| Duration | `defaults.duration_minutes` (`30`) | "15 mins", "1 hour" |
| Send updates | `defaults.send_updates` (`all`) | "silent invite" → `none` |
| Conference | `defaults.conference_type` (`hangoutsMeet`) | "no video" → skip |
| Always-include | `always_include[]` | "just me and Misha" → omit always-include |

---

## Resolution rules

### Attendee (dual-key resolver, teammates live in shared identity.json)

The roster lives in `~/.claude/shared/identity.json` under `teammates[]`. `/clickup` reads the same file — changes here are seen there.

1. NFC-normalize the typed name, strip leading/trailing whitespace + emoji.
2. **First pass** — case-insensitive match against `teammates[].latin_alias`.
3. **Second pass** — case-insensitive + NFC match against `teammates[].first_name`.
4. **Third pass** — case-insensitive match on `teammates[].email` (when user typed an email directly).
5. **Single match** → use that email.
6. **Multiple matches** → `AskUserQuestion` disambiguation (show full names + emails).
7. **Zero matches** → prompt for full email; on confirm, upsert into `teammates[]` with `sources: ["create-call"]` + `last_validated_at: null` via the atomic write helper in `references/config-schema.md`.
8. **Inactive teammate** (`active: false`) → surface banner, allow but confirm: "`X` is marked inactive (not in current ClickUp workspace). Still invite?"
9. In `--auto`: if ambiguous or attendee unresolvable AND no obvious default → refuse with one-line reason.

### Calendar

Default is `primary` (the user's own Google account). Override via `--calendar` switch or per-invocation "on the team calendar." Calendar list lives in `~/.claude/create-call/config.json` → `defaults.calendar` and the optional `calendars[]` registry.

### Conflict detection (before create)

1. Query `npx @googleworkspace/cli calendar events list --params '{"calendarId":"<cal>","timeMin":"<start>","timeMax":"<end>","singleEvents":true,"orderBy":"startTime"}' 2>/dev/null` for the proposed window.
2. If any event overlaps, surface in the preview: "You have `<title>` at `<time>`. Create anyway?"
3. In `--auto`: block if overlap ≥ 50% of proposed duration; surface "possible conflict" but proceed if overlap < 50%.

### Past-time guard

After parsing, if the resolved start is earlier than `now`:
- Interactive mode: `AskUserQuestion` "The time `<X>` has already passed today. Did you mean tomorrow?" Options: "yes, tomorrow" / "no, keep today".
- `--auto`: refuse with one-line reason. Never silently schedule in the past.

### Idempotency (retry safety)

Derive `requestId` = `<title-slug>-<unix-timestamp>`. On create failure mid-flight, search the calendar for the same `requestId` before retrying — if found, surface it instead of creating a duplicate.

---

## `--auto` safety net (refuse conditions)

Refuse creation with a one-line reason when any of these hold:

- `~/.claude/shared/identity.json` missing or incomplete (pre-flight step 2 HALT)
- `~/.claude/create-call/config.json` missing or incomplete (pre-flight step 3 HALT)
- Google Workspace CLI not authenticated
- Title missing or empty after extraction
- Date or start time missing
- At least one attendee (beyond always-include) requested but unresolvable
- Resolved start time in the past
- Conflict ≥ 50% overlap with an existing event

The spirit of `--auto` is "save with whatever exists." If what exists is too little to produce a non-garbage event, refuse. `--auto` NEVER opens interactive onboarding or any `AskUserQuestion` prompt — if setup is incomplete, it HALTs with a clear one-liner pointing to the fix command.

---

## Preview + edit (interactive mode only)

Render compact draft in a monospace block:

```
Title:     <title>
Time:      <date> <start>–<end> <timezone> (<duration>)
Calendar:  <calendar name>
Attendees: <comma-separated names + notes bot>
Meet:      will be generated
[Conflicts: <title> at <time> — if any]
```

Offer: `[1] Confirm & create  [2] Edit field(s)  [3] Cancel`.

**Edit**: multi-select — user picks one or more fields; skill re-prompts only those. Mutations persist in a draft object (do NOT regenerate the preview from source — that silently reverts prior edits).

After any edit, redraw the preview and repeat. Cancel abandons the draft.

---

## Files (user state, OUTSIDE the plugin dir — survives `/plugin update`)

- `~/.claude/shared/identity.json` — **SHARED with `/clickup`**. User profile + teammate roster. Both skills read and append.
- `~/.claude/create-call/config.json` — create-call-local. Calendar defaults, always-include attendees, behavior flags.

All JSON writes use atomic `tmp + fsync + os.replace` under `fcntl.flock` on a sentinel file — see the reference helper in `references/config-schema.md`. Readers preserve unknown keys on rewrite (forward-compat with `/clickup` fields this plugin doesn't know about).

Schemas + examples in `references/config-schema.md`.

---

## Error handling

| Error | Response |
|---|---|
| 401 / 403 auth error | HALT: "Run `! npx @googleworkspace/cli auth login --services calendar,people`" |
| 404 event not found | "Event not found. Check the event ID or search by title." |
| 409 conflict | "Event may already exist. Search for it first." |
| Network error | "CLI connection failed. Check your internet connection." |
| Attendee not in roster | Prompt for full email; upsert into shared identity.json |
| Corrupt `identity.json` or `config.json` | Quarantine to `<file>.corrupt-<epoch>` and redirect to `--onboard` |

---

## See also

- `references/modes.md` — detailed flow for every mode
- `references/event-format.md` — title, time parsing, attendee conventions with examples
- `references/config-schema.md` — identity.json + create-call/config.json formats + atomic-write helper
