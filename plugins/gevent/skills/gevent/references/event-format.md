# Event format rules

Load this file when composing a title, parsing time, or resolving attendees. Non-negotiable.

## Table of contents

- [Title rules](#title-rules)
- [Time parsing](#time-parsing)
- [Timezone rule](#timezone-rule)
- [Attendee rules](#attendee-rules)
- [Description rules](#description-rules)
- [JSON escaping](#json-escaping)
- [Worked examples](#worked-examples)
- [Hard stops](#hard-stops)

---

## Title rules

- **Imperative or noun phrase**. `Weekly Sync`, `Sprint Planning`, `Interview: Misha — Senior Engineer`, `Discuss Q3 roadmap`, `1:1 Sashko / Peter`. Not `Re: ...`, not `Meeting about X`.
- **English only**. Translate Ukrainian / other-language source titles unless a proper noun is load-bearing (company name, product, person).
- **≤ 120 chars** final. Calendar UIs truncate around 60; keep the informative bit in the first 50.
- **No bracket prefixes**. Not `[Meeting]`, not `[Team]`. Calendar already shows that metadata.
- **Keyword-rich**. If the meeting is about `MN Service automation`, include `MN Service automation` in the title — makes search work.
- **Test it**: would someone scrolling their Calendar next week know what this is for? If "sync" or "chat" by itself, add a qualifier.

### Title anti-patterns

| ❌ Bad | Why |
|---|---|
| `meeting` | No subject |
| `sync` | No subject |
| `Re: Thursday` | Email subject, not event title |
| `[MN] Sync` | Bracket prefix |
| `Quick call` | Vague |
| `Test meeting pls ignore` | Real users see this |

### Title good examples

- `Weekly MN Service sync`
- `Interview — Misha Skripkovsky — Senior Backend`
- `Q3 roadmap review`
- `1:1 Sashko / Peter`
- `Automation handoff — Daria + Misha`

---

## Time parsing

Convert user phrasing to ISO 8601. Always use the `currentDate` from context for relative dates.

| User says | Parsed |
|---|---|
| `6:45 AM ET` | `06:45:00` in `America/New_York` |
| `2pm` | `14:00:00` in default timezone |
| `15 mins` | duration `15` minutes |
| `1 hour` | duration `60` minutes |
| `tomorrow at 3` | date = today + 1, time = `15:00:00` |
| `Thursday` | next Thursday relative to today |
| `next week` | ambiguous — `AskUserQuestion` for specific day |
| `EOD` | 17:00 local (if user's timezone is work hours) |

**Ambiguous → ask**. Don't guess. "next week" without a weekday is a prompt-worthy ambiguity.

**Always use ISO 8601 with timezone** when writing to Google:
```json
"start": {"dateTime": "2026-04-23T14:00:00", "timeZone": "America/New_York"}
```
Never `"14:00:00-04:00"` in `dateTime` — Google resolves the offset from `timeZone`.

---

## Timezone rule

**IANA names only** (`America/New_York`, `Europe/Kyiv`, `UTC`). Never `-04:00` / `-05:00` offsets.

Reasons:
- IANA names let Google handle DST transitions automatically.
- A hardcoded `-04:00` will be wrong half the year (DST).
- A user saying "in Kyiv time" maps to `Europe/Kyiv`, not `+03:00`.

If the user says "my time" without specifying, use `defaults.timezone` from `~/.claude/gevent/config.json`.

---

## Attendee rules

1. **Always start with `always_include[]`** from config (notes bot by default).
2. **Append resolved user-requested attendees** (via dual-key resolver → see SKILL.md).
3. **Never add the organizer** (`user.email` from `~/.claude/shared/identity.json`) — Google auto-includes.
4. **Dedupe by email** (case-insensitive) before building the array.
5. **Inactive teammates**: if `teammates[].active == false`, surface a banner but allow inviting. The user may still need to meet with someone who left ClickUp.
6. **Name-only resolution fallback**: if a name resolves to multiple teammates, `AskUserQuestion`. If zero matches, prompt for full email, validate per SKILL.md rules, and upsert into `identity.json` with `sources: ["manual"]`.

### Attendee array shape

```json
"attendees": [
  {"email": "notes.bot@speedandfunction.com"},
  {"email": "misha.skripkovsky@speedandfunction.com"}
]
```

### Optional fields on attendees

Usually skip. Only set `"optional": true` if:
- The attendee record in `always_include[]` has `"optional": true` (e.g., notes bot is optional), OR
- The user explicitly says "invite X as optional."

---

## Description rules

Keep short. Only include if the user said something worth capturing:

- Agenda bullets (3–5)
- Link to a doc, PR, or ticket being discussed
- Context line ("Follow-up to yesterday's outage")

Don't include:
- Boilerplate like "Looking forward to our meeting!"
- The meeting's own title (already in `summary`)
- The Meet link (Google adds it)
- Attendee list (Google shows it separately)

If there's nothing worth saying, leave description empty.

---

## JSON escaping

**ALWAYS write the request body to a tempfile — not conditionally. Never inline user-typed strings into `--json '{...}'` on the command line.** String interpolation into a single-quoted shell arg is an injection vector: a title like `x"},"attendees":[{"email":"evil@x.com"}],"summary":"a` breaks the JSON envelope and silently rewrites the attendee list; a title containing a literal `'` closes the shell quote and enables shell-command substitution.

### Mandatory tempfile pattern (for every `events insert` / `events patch`)

1. **Build the body in Python**, not by hand:
   ```python
   import json, tempfile, time, os
   ts = int(time.time())
   tmp_path = f"/tmp/cal_event_{ts}.json"
   with open(tmp_path, "w") as f:
       json.dump(body, f, ensure_ascii=False)  # json.dump auto-escapes quotes/backslashes/control chars
   ```
   Never hand-concat JSON strings. `json.dump` is the only trusted serializer.

2. **Pass via `$(cat ...)`**, never inline:
   ```bash
   npx @googleworkspace/cli calendar events insert \
     --params '{"calendarId":"primary","conferenceDataVersion":1,"sendUpdates":"all"}' \
     --json "$(cat /tmp/cal_event_${ts}.json)" 2>/tmp/gws_err.${ts}
   rc=$?; err=$(cat /tmp/gws_err.${ts}); rm -f /tmp/gws_err.${ts} /tmp/cal_event_${ts}.json
   ```

3. **Classify stderr** on non-zero exit (same rules as SKILL.md pre-flight step 5). Never silently swallow — surface the real error to the user.

4. **Delete the tempfile in a `finally` clause**, not "on success" — orphan event bodies in /tmp are low-signal noise for a later attacker scraping `/tmp`.

### Input validation (all user-typed strings that enter the body)

Before calling `json.dump`:
- Email fields: validate against `^[^@\s"'\\<>]+@[^@\s"'\\<>]+\.[^@\s"'\\<>]+$` AND reject domains with any non-ASCII character (IDNA mixed-script defense). On failure: re-prompt.
- Summary / description / attendee `displayName`: strip ASCII control chars (`\x00-\x1f` except `\n\t`) and Unicode control categories (`Cc`, `Cf`). Length-cap to 120 (title) / 2000 (description).
- `requestId`: derive from `title_slug + ts`, where `title_slug` is `re.sub(r"[^a-z0-9-]", "", title.casefold().replace(" ", "-"))[:32]`. ASCII-only, bounded length.

### Request ID format

`<title-slug>-<unix-timestamp>` where `<title-slug>` is the title casefolded, ASCII-stripped, spaces→hyphens, max 32 chars.

Examples:
- Title `Weekly MN Service sync` + ts `1712505600` → `weekly-mn-service-sync-1712505600`
- Title `Interview — Misha Skripkovsky — Senior Backend` + ts `1712505600` → `interview-misha-skripkovsky-seni-1712505600`

Unique IDs prevent conference-creation collisions on retry.

### Request ID format

`<title-slug>-<unix-timestamp>` where `<title-slug>` is the title lowercased, ASCII-stripped, spaces→hyphens, max 32 chars.

Examples:
- Title `Weekly MN Service sync` + ts `1712505600` → `weekly-mn-service-sync-1712505600`
- Title `Interview — Misha Skripkovsky — Senior Backend` + ts `1712505600` → `interview-misha-skripkovsky-seni-1712505600`

Unique IDs prevent conference-creation collisions on retry.

---

## Worked examples

### Example 1 — Thin source

**Input**: *"schedule a 15-min sync with Misha tomorrow at 2pm"*

Resolved:
```
Title:     Sync with Misha
Time:      2026-04-23 14:00–14:15 America/New_York (15 min)
Calendar:  primary
Attendees: notes.bot@…, misha.skripkovsky@…
```

Title pulled from the one word of intent ("sync"). If user accepts, create. If user edits title to "Weekly MN Service sync," re-render preview.

### Example 2 — Rich source

**Input**: *"book a 1-hour interview with a candidate for the backend role next Thursday at 11am Kyiv time, include Peter and Misha, calendar: team"*

Resolved:
```
Title:     Interview — Backend candidate
Time:      2026-05-02 11:00–12:00 Europe/Kyiv (60 min)
Calendar:  team
Attendees: notes.bot@…, peter.ovchyn@…, misha.skripkovsky@…
```

Note: the candidate's name is unknown from the source, so title uses the role. If user edits to add the candidate's name, re-render.

### Example 3 — Update

**Input**: *"move the Automation call to 3pm"*

1. Find today's events matching `q=Automation`.
2. If 1 match: confirm "Move `<title>` from `<old_time>` to `15:00`?"
3. `events patch` with new `start` + `end` (preserve duration).

### Example 4 — Cancel

**Input**: *"cancel the Weekly Sync tomorrow"*

1. Find tomorrow's events matching `q=Weekly Sync`.
2. Confirm: "Cancel `Weekly Sync` on `2026-04-23` at `14:00`? Attendees will be notified."
3. `events delete` with `sendUpdates: "all"`.

---

## Hard stops

Before creating, verify:

- [ ] Title is non-empty and ≤ 120 chars
- [ ] Title has no bracket prefix
- [ ] Title is English (or a preserved proper noun)
- [ ] Start and end have IANA timezone names (not hardcoded offsets)
- [ ] Start is not in the past (unless user explicitly confirmed)
- [ ] Attendee array includes always-include entries from config
- [ ] Attendee array does NOT include the organizer
- [ ] Attendee array is deduped by email
- [ ] `requestId` is unique (title-slug + timestamp)
- [ ] If conflicts exist, user was informed (or `--auto` threshold passed)
