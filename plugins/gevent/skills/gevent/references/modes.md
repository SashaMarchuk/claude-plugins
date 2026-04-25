# /gevent modes

Detailed flow for each mode. Load only the section for the current invocation.

## Table of contents

- [default](#default) — interactive create / update / cancel
- [auto](#auto) — silent create with defaults
- [onboard](#onboard) — full wizard (identity → calendar)
- [onboard-identity](#onboard-identity) — shared identity wizard only
- [onboard-calendar](#onboard-calendar) — gevent-local wizard only
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

#### Precedence rule (load-bearing — cancel + update simultaneous)

When a single turn matches BOTH the cancel-verb set AND the update-verb set (e.g. "cancel and reschedule X to 3pm", "delete the old one and move it to Friday", "remove and re-book Misha for Tuesday"), **update wins over cancel** — route to the Update flow, NOT the Cancel flow. Rationale: cancel-then-recreate has user-visible side effects that re-scheduling does NOT — every attendee receives a cancellation email AND a fresh invite (two notifications, often interpreted as "the meeting was cancelled" because the cancellation lands first), the original event ID is destroyed (breaking any external links / Slack reminders / Sembly recordings tied to that ID), and the conferenceData (Meet link) is regenerated, invalidating bookmarks. A single `events patch` reschedule preserves the event ID, the Meet link, and any third-party hooks — and Google sends a single "updated" notification per attendee instead of two.

Algorithm:

```python
CANCEL_VERBS = {"cancel", "delete", "remove"}
UPDATE_VERBS = {"move", "reschedule", "change", "update", "add attendee", "remove attendee"}
text = phrase.casefold()
has_cancel = any(v in text for v in CANCEL_VERBS)
has_update = any(v in text for v in UPDATE_VERBS)
has_new_time = bool(re.search(r"\bto \d|at \d|on \w+day|tomorrow|next week", text))
if has_cancel and has_update:
    intent = "update"  # update wins; reschedule semantics preferred
elif has_cancel and has_new_time:
    intent = "update"  # "cancel and move to 3pm" without explicit update verb still implies reschedule
elif has_cancel:
    intent = "cancel"
elif has_update:
    intent = "update"
else:
    intent = "create"
```

Examples:
- "cancel and reschedule X to 3pm" → cancel + update + new-time → **update** (reschedule).
- "cancel X for me" → cancel only → cancel.
- "delete the meeting and move it to Friday" → cancel + update + new-time → **update** (move keeps event ID).
- "move Misha off the call" → update only (remove-attendee sub-intent) → update.
- "remove the call" → cancel only (no update verb, no new-time) → cancel.

The `/gevent:update <text>` and `/gevent:delete <text>` command shims explicitly bypass this precedence — the user has already chosen the intent at the command level. The skill's intent classifier runs only when the user invokes `/gevent` or `/gevent:schedule` without an explicit sub-command.

If — AFTER applying the precedence rule — intent is still genuinely ambiguous (e.g. "do something with the X meeting"), `AskUserQuestion` once to disambiguate. The precedence rule fires BEFORE the ambiguity prompt, so the cancel+update case never triggers a needless prompt.

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

1. **Find event** (same as update). Extract `attendees[]` from the resolved event; compute `attendee_count = len(attendees or [])` (excluding `resource: true` and declined-organizer entries).
2. **Resolve `sendUpdates` mode** — honor `config.defaults.send_updates` (same as create flow), NOT a hardcoded `"all"`. Three modes: `"all"` (Google-default blast), `"externalOnly"`, `"none"` (silent cancel; no emails). If the config value is missing or not one of the three, fall back to `"all"`.
3. **High-attendee confirmation prompt (MANDATORY when `attendee_count > 10`).** Regardless of the configured `send_updates`, when `attendee_count > 10` prompt an explicit `AskUserQuestion` to confirm the notification mode:
   ```
   Cancelling `<title>` on `<date>` at `<time>` — <attendee_count> attendees.
   How should Google notify them?
     [All attendees — send cancellation emails to all <attendee_count>]
     [External only — notify only attendees outside your domain]
     [None — silent cancel, no emails]
   ```
   The user's pick overrides `config.defaults.send_updates` for THIS cancel only. The count in the prompt is load-bearing — it is the blast-radius surface the user needs to see before clicking confirm.
4. **Confirm**: `AskUserQuestion` "Cancel `<title>` on `<date>` at `<time>`? `<attendee_count>` attendees will be notified via `<resolved_sendUpdates>`." The attendee count and resolved mode BOTH appear verbatim — never show a confirmation without the count. **L-18 — also surface the attendee-list head when count ≤ 10** (full list in the prompt body) and a count-only head when count > 10 (e.g. `"50 attendees: <first 5 emails>, … and 45 more"`). The blast-radius surface (count, mode, sample) is the user's last visual checkpoint before Google ships the cancellation emails — never collapse it to a yes/no without the count + sample.
5. **Delete** via `events delete` with `sendUpdates: <resolved_sendUpdates>` (value resolved in step 2, possibly overridden in step 3). NEVER hardcode `"all"`.

---

## auto

Silent create. Skip preview. No interactive prompts beyond the safety-net refusals.

### Flow

1. **Safety-net check first** (see SKILL.md → `--auto` safety net). On refuse condition, HALT with one-line reason.
2. **Extract + resolve** as in default Steps 1–3, but never ask questions. Use defaults for everything unresolved.
3. **Past-time refuse** — don't silently schedule in the past.
4. **Conflict check** at the `--auto` threshold per SKILL.md → Conflict detection: block on cumulative overlap ≥ 50% of proposed duration (summed across all existing events), on zero-duration proposed time falling inside an existing interval, or on any all-day event on the proposed date. Surface "possible conflict" banner and proceed only when 0 < overlap < 50% AND no all-day hit.
5. **Create immediately** via `events insert`.
6. **Return** event URL + 2-line summary.

---

## onboard

Full wizard. Runs `onboard-identity` → `onboard-calendar` back-to-back. Skips whichever slice is already complete.

1. If `~/.claude/shared/identity.json` missing or `onboarding_complete != true` → run [onboard-identity](#onboard-identity).
2. If `~/.claude/gevent/config.json` missing or `onboarding_complete != true` → run [onboard-calendar](#onboard-calendar).
3. If a call seed was carried in, resume [default](#default) with that seed.

---

## onboard-identity

Writes `~/.claude/shared/identity.json` — **shared with `/clickup`**. Read-only for every subsequent skill that needs user + teammates.

This flow is **identical in both `/clickup` and `/gevent`** — onboarding from either skill produces the same identity.json populated from the maximum set of sources available on this machine. Running it from either side is equivalent; the other skill just inherits the result.

### Flow

#### Step 1 — Check existing state

- If `identity.json` exists AND `onboarding_complete: true` AND user invoked `--onboard identity` explicitly (forced re-run) → proceed with warning: "Identity already complete. Re-running refreshes teammates from all available sources; existing teammates are preserved (unknown keys round-tripped)."
- If missing or incomplete → proceed.

#### Step 2 — Ask identity (single `AskUserQuestion` round, 2 questions)

- Your full name
- Your work email

Seed the skeleton: `{schemaVersion: 2, user: {name, email, external_ids: {}}, teammates: [], onboarding_complete: false, updated_at: <now>}`.

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

#### Step 7b — Short-alias confirmation for frequent collaborators

Teammates resolved from ClickUp typically have `latin_alias` = `first_name` (the default set in Step 5 merge). That works for short names ("Misha", "Andy") but generates noise for long ones ("Vladyslav", "Mykhailo", "Oleksandr") and misses personal nicknames the user already uses in daily work. Step 7b lets the user pick a short alias for frequent collaborators, in a single consolidated card, with sensible defaults from two prior signals: a legacy `contacts.json` (strongest) and a common-nickname table.

**Framing to the user: "frequent collaborators from your calendar."** Do NOT claim this is "people you type about most" — calendar frequency is a proxy for contact intensity, not typing intent. Be honest.

##### Inputs (carry forward from earlier steps)

- `calendar_count[email]` — `Counter()` built inside Source C. Increment for every event where `attendees.length <= 15` AND user is in attendees. Kept in-memory; NOT persisted to identity.json.
- Legacy contacts.json (reverse-indexed `{email: chosen_alias}`). Search order (first match wins):
  1. `~/.claude/skills/create-call/contacts.json` — current user-level skill
  2. `~/.claude-plugins-backup-*/skills-create-call/contacts.json` — post-migration backup, newest `mtime` wins

Load it safely:

```python
import json, glob, os, pathlib
LEGACY_CONTACTS_MAX_BYTES = 5_000_000  # L-8: size cap; reject files larger than 5 MB
def load_legacy_aliases():
    candidates = [pathlib.Path.home() / ".claude/skills/create-call/contacts.json"]
    candidates += [pathlib.Path(p) for p in sorted(
        glob.glob(str(pathlib.Path.home() / ".claude-plugins-backup-*/skills-create-call/contacts.json")),
        key=os.path.getmtime, reverse=True)]
    for p in candidates:
        # L-8: explicitly reject symlinks (avoid contacts.json → /etc/passwd attacks)
        # AND enforce a 5MB size cap (avoid memory exhaustion via 100MB symlink-or-copy).
        try:
            if p.is_symlink():
                continue
            if not p.is_file():
                continue
            if p.stat().st_size > LEGACY_CONTACTS_MAX_BYTES:
                continue
            raw = json.loads(p.read_text())
            return {v.strip().casefold(): k for k, v in raw.items() if isinstance(v, str)}
        except Exception:
            continue
    return {}
```

Missing / malformed → `{}` silently. Do NOT error.

##### Nickname table (common Ukrainian / Russian / Eastern-European hypocorisms)

Embed at spec level so Claude doesn't reinvent it. ~25 entries, keys casefolded:

```python
NICKNAME_TABLE = {
    "oleksandr":"Sasha", "aleksandr":"Sasha",
    "alexander":"Alex",
    "mykhailo":"Misha", "mikhail":"Misha", "michael":"Mike",
    "vladyslav":"Vlad", "vladislav":"Vlad", "volodymyr":"Vlad",
    "serhii":"Sergey", "sergiy":"Sergey", "sergei":"Sergey",
    "yuriy":"Yura", "yurii":"Yura", "yuri":"Yura",
    "andriy":"Andy", "andrii":"Andy", "andrey":"Andy",
    "mykola":"Nick", "nikolai":"Nick",
    "stanislav":"Stas", "viacheslav":"Slava", "vyacheslav":"Slava",
    "dmytro":"Dima", "dmitriy":"Dima", "dmitri":"Dima",
    "oleh":"Oleg",
    "kateryna":"Kate", "ekaterina":"Kate",
    "tetiana":"Tania", "tatiana":"Tania", "tatyana":"Tania",
    "olha":"Olga",
    "yuliia":"Julia", "yulia":"Julia", "iuliia":"Julia",
    "anastasiia":"Nastya", "anastasia":"Nastya",
    "kseniia":"Ksenia", "kseniya":"Ksenia",
    "maryna":"Marina", "olena":"Elena", "iryna":"Irina",
    "petro":"Peter", "pavlo":"Paul",
}
```

##### Proposal algorithm

```python
def propose_alias(tm, legacy, nicknames):
    em = tm["email"].casefold()
    if em in legacy:
        return legacy[em], "legacy"
    fn_key = tm["first_name"].casefold()
    if fn_key in nicknames:
        return nicknames[fn_key], "nickname"
    return tm["first_name"], "safe"  # safe Latin transliteration default
```

Priority: **legacy > nickname > safe**. Legacy always wins.

##### Filter + sort

Only prompt for teammates where EITHER the proposal differs from the current `latin_alias` (so idempotent re-runs skip customized entries) AND at least one of:
- has a legacy alias (strong signal — user picked it once already), OR
- `calendar_count >= 2` (met in at least two small meetings in 14d)

Sort within the card by `(has_legacy desc, calendar_count desc, first_name asc)`. Hard cap at **20 lines** for fatigue control; remaining teammates keep `latin_alias = first_name`. Document this in a card footer: `"N more teammates defaulted to first_name — re-run /gevent --onboard identity to refine."`.

##### Collision pre-pass (MANDATORY — never present a card with built-in collisions)

```python
from collections import Counter
counts = Counter(p["proposed"].casefold() for p in proposed_rows)
for row in proposed_rows:
    if counts[row["proposed"].casefold()] > 1:
        row["collision"] = True
        # auto-disambiguate: first-letter-of-last-name
        row["proposed"] = f"{row['proposed']}.{row['last_initial']}"
```

Where `last_initial` = second token of full_name's first char (falls back to first char of email-local-part after first dot). Matches Sashko's existing `julia.d` / `julia.m` / `oleg.m` pattern in legacy contacts.

##### Render the card

Single `AskUserQuestion` — same textarea primitive as Step 7 (Cyrillic). NOT sub-questions.

```
Short aliases for frequent collaborators (last 14 days by calendar meeting count;
legacy contacts.json entries are pre-applied). Edit right side; leave as-is to accept.

  Vladyslav Bevza       [10 meetings]                → Vlad
  Misha Skripkovsky     [12 meetings, legacy: misha] → Misha
  Andy Rozhylo          [5 meetings,  legacy: andy]  → Andy
  Julia Dzundza         [3 meetings]            ⚠coll → Julia.D
  Julia Manzo           [1 meeting]             ⚠coll → Julia.M
  Oleksandra Shkundia   [8 meetings,  legacy: al]    → Al
  ...

N more teammates default to first_name (re-run `--onboard identity` to refine).

Type "accept all" on a line by itself to take every proposal verbatim.
Leave a right-side blank to skip that teammate (keeps first_name).
```

##### Post-parse

1. Parse each line into `{email, proposed_alias}`. Lines with blank right-side → use `first_name`. `accept all` sentinel → use every proposal as shown.
2. Final-collision recheck (casefolded). If any duplicates remain → re-prompt with a `⚠ alias X used by A and B — disambiguate:` header. Max 2 retry rounds; 3rd attempt → auto-append `last_initial` and proceed with a **banner warning (L-11 — verbatim text, do NOT paraphrase)**:
   > `⚠ Alias-collision auto-resolved on 3rd attempt: <alias> → <alias>.<L1> (<full_name_1>) and <alias> → <alias>.<L2> (<full_name_2>). Edit ~/.claude/shared/identity.json directly to override, or re-run /gevent:onboard identity to redo aliases.`
3. Apply to `teammates[].latin_alias` via the same atomic update as Step 8 (NOT a separate write — merge into Step 8's single atomic commit).
4. Skip entirely if zero rows qualify (no fatigue on teams where Latin-first-name defaults are already good).

##### Idempotency

Re-running `--onboard identity` diffs EACH teammate's current `latin_alias` against `propose_alias(..., legacy={})` (the "auto baseline" without legacy lookup). If they match, the user hasn't customized it yet — eligible for the card. If they differ, user already picked something — skip silently, preserve.

#### Step 8 — Write identity.json atomically (stale-read guard around long-running prompt-cycles)

Via the `atomic_update` helper (see `config-schema.md` → "Reference write helper"). `fcntl.flock` on `~/.claude/shared/identity.json.lock` is held for the **ENTIRE read-modify-write** — NOT just for the final tempfile-rename. Set `schemaVersion: 2`, `onboarding_complete: true`, `updated_at: <now>`.

**Stale-read guard (M-5 — protects against concurrent /clickup or /gevent writers).** Steps 5/7/7b above run AskUserQuestion review cards based on a pre-lock snapshot. If a concurrent `/clickup` or `/gevent` invocation in another terminal mutates `identity.json` while the user is mid-prompt (a slow review-card cycle can take minutes — e.g. confirming Cyrillic aliases for 30 teammates), naively committing the user's accept/reject decisions on the stale snapshot would silently overwrite the other plugin's fresh mutation. The Step 8 commit therefore re-reads inside the flock and compares a stable hash of MATERIAL fields against the snapshot hash captured at the start of the prompt-cycle:

```python
import hashlib, json
MATERIAL_FIELDS = ("user.name", "user.email", "defaults.calendar",
                   "defaults.send_updates", "behavior.notes_bot_decided")

def material_hash(data):
    blob = []
    for path in MATERIAL_FIELDS:
        cur = data
        for seg in path.split("."):
            cur = (cur or {}).get(seg) if isinstance(cur, dict) else None
        blob.append((path, cur))
    return hashlib.sha256(json.dumps(blob, sort_keys=True).encode()).hexdigest()

def step_8_commit(identity_path, prompt_cycle_snapshot, user_decisions):
    def mutate(data):
        # Re-read happens automatically — atomic_update opens the file inside the lock.
        # Compare material-field hash from the pre-prompt snapshot vs the freshly-read data.
        if material_hash(data) != material_hash(prompt_cycle_snapshot):
            # A concurrent /clickup or /gevent write changed a material field
            # (e.g. user.email) while the AskUserQuestion review card was open.
            # Refuse the silent overwrite. In interactive mode: re-prompt the user
            # with a "config drifted while you were reviewing — re-confirm?" card.
            # In --auto / non-interactive paths: abort the commit and surface
            # a one-line reason ("identity.json drifted under flock during onboarding;
            # re-run /gevent:onboard identity").
            raise SystemExit(
                "identity.json material fields drifted during onboarding "
                "(concurrent /clickup or /gevent write detected on flock re-acquire). "
                "Re-prompt or re-run `/gevent:onboard identity` — refusing silent overwrite."
            )
        # Hash matched: apply the user's decisions onto the freshly-read data
        # (NOT onto the stale snapshot — last-writer-wins on UNKNOWN fields,
        # but the user's decisions land on the latest material state).
        apply_user_decisions(data, user_decisions)
    atomic_update(identity_path, mutate)
```

Concurrent-write semantics:
- **Material-field drift** (user.email changed by `/clickup --onboard identity` mid-prompt) → re-prompt + re-confirm (interactive) OR abort with one-line message (`--auto`). NEVER silent-overwrite the other plugin's mutation.
- **Non-material drift** (a teammate `last_validated_at` bumped, a new teammate added by `/clickup` workspace sync) → silent merge via UNION on `sources[]` and last-writer-wins on known scalar fields; the user's decisions still apply on top of the fresh roster.
- **Unknown-key drift** (a `future_field` written by a newer plugin) → preserved by the closure-key-set-diff guard in `atomic_update` (see config-schema.md M-6 contract). The flock + diff together close the race.

The lock release happens at the `with open(lock_path, "w") as lk:` context exit AFTER the tempfile rename + parent-dir fsync. A second `/clickup` writer waiting on the flock therefore sees the merged Step-8 state when it acquires; its own `atomic_update` repeats the same re-read + material-hash protocol.

#### Step 9 — Preserve unknown keys (always)

If a teammate record already exists in identity.json (e.g. added by the other skill with extra fields like `external_ids.google` or `email_aliases`), upsert by email — merge known fields, preserve unknown keys, UNION `sources[]`, bump `last_validated_at`.

### Resumption

If the user interrupts mid-flow, `onboarding_complete` stays `false` in identity.json. Any subsequent invocation of either skill detects this, prints "Identity onboarding incomplete — resuming", and continues from the next unfinished step.

---

## onboard-calendar

Writes `~/.claude/gevent/config.json`. Assumes `~/.claude/shared/identity.json` is complete; if not, redirects to [onboard-identity](#onboard-identity) first.

### Flow

1. **Auto-detect calendar + timezone**:
   - `npx @googleworkspace/cli calendar calendarList list --params '{}' 2>/dev/null` — list calendars the user can access.
   - `npx @googleworkspace/cli calendar settings get --params '{"setting":"timezone"}' 2>/dev/null` — resolve the primary calendar's timezone.

2. **Notes-bot decision (MANDATORY, explicit, no skip).** This is a dedicated `AskUserQuestion` round that runs BEFORE the rest of the calendar defaults. The wizard loops on this question until the user picks one of the three options — there is no "skip" and no default-and-proceed. The answer controls `always_include[]` AND sets `behavior.notes_bot_decided: true`.

   ```
   Auto-include a notes-bot on every event you schedule?
   [Yes — use notes.bot@speedandfunction.com (recommended)]
   [Yes — different email (e.g., your own recorder bot)]
   [No — I don't use a notes bot]
   ```

   Decision storage:
   - **Option 1** ("Yes — use default") → `always_include: [{email: "notes.bot@speedandfunction.com", tag: "notes_bot", optional: true}]`, `behavior.notes_bot_decided: true`.
   - **Option 2** ("Yes — different email") → follow-up `AskUserQuestion` asking for the email. Validate against the same regex SKILL.md uses (`^[^@\s"'\\<>]+@[^@\s"'\\<>]+\.[^@\s"'\\<>]+$`) AND reject any domain with non-ASCII characters AND **L-2**: reject if the entered email casefold-equals `identity.user.email` ("Notes-bot email cannot be your own email — the create-flow's exclude-organizer rule would silently strip it from `attendees[]`, leaving `always_include` de-facto empty. Pick a different bot address."). On failure, re-prompt with the reason. On valid email → `always_include: [{email: "<entered>", tag: "notes_bot", optional: true}]`, `behavior.notes_bot_decided: true`.
   - **Option 3** ("No — I don't use a notes bot") → `always_include: []`, `behavior.notes_bot_decided: true`. This is a valid, explicit opt-out — the empty array + flag together mean "user reviewed and declined."

   If the user dismisses the card or the response is unparseable, re-ask until one of the three options is chosen. This step must complete before step 3.

3. **Confirm remaining defaults** (single `AskUserQuestion` round, consolidated):
   - Default calendar: show auto-detected primary, allow override.
   - Default timezone: show auto-detected, allow override (IANA names).
   - Default duration: `30` minutes (prefill, allow override).

4. **Confirm behavior flags** (prefilled, allow override):
   - `confirm_before_create`: `true`
   - `check_conflicts`: `true`
   - `past_time_check`: `true`
   - `notes_bot_decided`: `true` (already set by step 2 — never editable here; surfaced for transparency only).

5. **Write config** to `~/.claude/gevent/config.json` via atomic helper + flock on `~/.claude/gevent/.config.json.lock`. Fields: `schemaVersion: 2`, `onboarding_complete: true`, `updated_at: <now>`, `defaults`, `behavior` (including `notes_bot_decided: true`), `always_include[]`.

6. **If a call seed was carried in**, resume [default](#default) now.

---

## status

Health check across BOTH files. Read-only.

### Output

```
/gevent status
─────────────────────────────────────
identity.json    (~/.claude/shared/)
  User:          Sashko Marchuk <sasha@…>
  Teammates:     18
  Schema:        v1  ✓
  Shared with:   /clickup, /gevent

gevent/config.json
  Calendar:      primary
  Timezone:      America/New_York
  Duration:      30 min default
  Always-include: notes.bot@speedandfunction.com
  Schema:        v1  ✓

Google CLI auth:  OK (last verified: 4s ago)
Legacy shadow:    [list every hit from the broadened glob in SKILL.md step 1 — `~/.claude/skills/create-call/`, `~/.claude.backup-*/skills/create-call/`, `~/.claude.bak/`, `~/.claude.old*/`, `~/.claude-backup-*/`, `~/.claude-plugins-backup-*/`]  ⚠  remove when done migrating
```

Never mutates state. Safe to run any time.

---

## calendar

Switch the active default calendar. Only mutates `~/.claude/gevent/config.json` (`defaults.calendar`).

### Flow

1. `npx @googleworkspace/cli calendar calendarList list --params '{}' 2>/dev/null` to fetch all calendars the current auth has access to.
2. `AskUserQuestion` (single-select) with the list.
3. **L-12 — validate the picked ID against `calendars[]` registry (and against `CALENDAR_ID_RE` from M-4) BEFORE writing.** If the chosen ID is not in the freshly-fetched `calendarList` AND not in `config.calendars[]`, refuse with a banner: `"Calendar <id> not in your accessible list — Google would reject. Re-pick from the list above."`. Also revalidate `CALENDAR_ID_RE` (M-4) — defense-in-depth in case a malformed ID slipped past auto-detection.
4. On pick + validation pass, atomic-write `defaults.calendar` in `~/.claude/gevent/config.json` AND upsert into `calendars[]` registry (so `--status` output reflects the canonical name + timezone).
5. Confirm: "Active calendar is now `<name>` (id: `<id>`). Future events default here unless overridden."
