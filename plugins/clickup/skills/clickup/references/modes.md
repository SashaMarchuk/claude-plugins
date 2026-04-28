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
- [reload](#reload) — reconcile config.lists with the active workspace

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

Writes `~/.claude/shared/identity.json` — **shared with `/gevent`**. Read-only for every subsequent skill that needs user + teammates.

This flow is **identical in both `/clickup` and `/gevent`** — onboarding from either skill produces the same identity.json populated from the maximum set of sources available on this machine. Running it from either side is equivalent; the other skill just inherits the result.

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

Default transliteration uses Python's `unicodedata.normalize("NFKD", name)` then strip combining marks, then pass through a Cyrillic→Latin table. **The hard sign `ъ` and soft sign `ь` map to distinct marker characters (NOT empty string) to preserve distinguishability between otherwise-identical names** — closes PLG-clickup-F11 (`Миша` vs `Мишьа` would otherwise collapse to identical `Misha`, defeating the homoglyph gate):

```python
CYRILLIC_TO_LATIN = {
    "а":"a","б":"b","в":"v","г":"h","ґ":"g","д":"d","е":"e","є":"ie","ё":"io",
    "ж":"zh","з":"z","и":"y","і":"i","ї":"i","й":"i","к":"k","л":"l","м":"m",
    "н":"n","о":"o","п":"p","р":"r","с":"s","т":"t","у":"u","ф":"f","х":"kh",
    "ц":"ts","ч":"ch","ш":"sh","щ":"shch",
    # Hard/soft signs preserved as markers (NOT dropped to ""). This is load-
    # bearing: dropping both would collapse `Миша` (no sign) and `Мишьа`
    # (soft sign) to the same `Misha` latin_alias, and the homoglyph gate
    # on latin_alias would then silently accept both as identical records.
    # The markers are ASCII-safe, unambiguous, and visually signal "sign present".
    "ъ":"__","ы":"y","ь":"_","э":"e","ю":"iu","я":"ia",
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

The teammate record carries a **`translit_alias` field** (separate from `latin_alias` — kept in `identity.json` under `teammates[]`) containing the raw output of `translit()` including sign-markers. This preserves the distinguishing signal even when `latin_alias` is a user-chosen short form (e.g. `Misha`). The `translit_alias` is ONLY consumed by the collision pre-pass below — never rendered in tickets.

**Mandatory collision pre-pass on ALL new transliterations (not only UX-fatigue-filtered ones).** Before any silent upsert of a new Cyrillic-sourced teammate, run this check:

```python
def collision_prepass(new_teammate, existing_teammates):
    new_tr = translit(new_teammate["first_name"])
    new_la = new_teammate["latin_alias"]
    for existing in existing_teammates:
        ex_tr = existing.get("translit_alias") or translit(existing["first_name"])
        ex_la = existing["latin_alias"]
        # Collision: translit_alias identical OR latin_alias identical
        # (after casefold). Fires even when the Cyrillic originals differ
        # only by a sign (ь / ъ) that the marker-preserving table now
        # keeps distinct in translit_alias — but the user-chosen
        # latin_alias may still collide. Either collision forces
        # disambiguation.
        if new_tr.casefold() == ex_tr.casefold() or new_la.casefold() == ex_la.casefold():
            return ("collision", existing)
    return ("no-collision", None)
```

On collision: NEVER silent-upsert. Force `AskUserQuestion` disambiguation with the full names, Cyrillic originals, emails, and transliterated forms shown. This extends the Step 7b collision-pre-pass (previously only run on UX-fatigue-filtered short-alias proposals) to EVERY new transliteration regardless of whether the teammate surfaces in the Step 7b card. Examples:

- `Миша` (new) vs `Мишьа` (existing) with marker table: `translit_alias = "Misha"` vs `"Mish_a"` → translit_alias differs → if `latin_alias` also differs (e.g. "Misha" vs "Misha.A"), no collision; if `latin_alias` identical, collision fires on `latin_alias`.
- `Миша` (new) vs `Миша` (existing, different email, different last name): `translit_alias` identical → collision fires; disambiguation prompt required.

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
def load_legacy_aliases():
    candidates = [pathlib.Path.home() / ".claude/skills/create-call/contacts.json"]
    candidates += [pathlib.Path(p) for p in sorted(
        glob.glob(str(pathlib.Path.home() / ".claude-plugins-backup-*/skills-create-call/contacts.json")),
        key=os.path.getmtime, reverse=True)]
    for p in candidates:
        if p.is_file():
            try:
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

Sort within the card by `(has_legacy desc, calendar_count desc, first_name asc)`. Hard cap at **20 lines** for fatigue control; remaining teammates keep `latin_alias = first_name`. Document this in a card footer: `"N more teammates defaulted to first_name — re-run /clickup --onboard identity to refine."`.

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
2. Final-collision recheck (casefolded). If any duplicates remain → re-prompt with a `⚠ alias X used by A and B — disambiguate:` header. Max 2 retry rounds; 3rd attempt → auto-append `last_initial` and proceed with a banner warning.
3. Apply to `teammates[].latin_alias` via the same atomic update as Step 8 (NOT a separate write — merge into Step 8's single atomic commit).
4. Skip entirely if zero rows qualify (no fatigue on teams where Latin-first-name defaults are already good).

##### Idempotency

Re-running `--onboard identity` diffs EACH teammate's current `latin_alias` against `propose_alias(..., legacy={})` (the "auto baseline" without legacy lookup). If they match, the user hasn't customized it yet — eligible for the card. If they differ, user already picked something — skip silently, preserve.

#### Step 8 — Write identity.json atomically

Via the `atomic_update` helper (see `config-schema.md` → "Reference write helper"). `fcntl.flock` on `~/.claude/shared/identity.json.lock` (canonical cross-plugin lock path — NO leading dot; sibling of `identity.json`) for the entire read-modify-write. Set `schemaVersion: 2`, `schemaVersion_bumped_at: <now>`, `onboarding_complete: true`, `updated_at: <now>`.

#### Step 9 — Preserve unknown keys (always)

If a teammate record already exists in identity.json (e.g. added by the other skill with extra fields like `external_ids.google` or `email_aliases`), upsert by email — merge known fields, preserve unknown keys, UNION `sources[]`, bump `last_validated_at`.

### Resumption

If the user interrupts mid-flow, `onboarding_complete` stays `false` in identity.json. Any subsequent invocation of either skill detects this, prints "Identity onboarding incomplete — resuming", and continues from the next unfinished step.

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

5. **If switching workspaces** (the user had a different `workspace` before): any teammates in `identity.json` whose `external_ids.clickup` is NOT in the new workspace's member list get `active: false`. Surface this as a banner. Do not delete — other skills (like `/gevent`) still use the email + name.

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

### Staleness + auto-demotion

On `--status` or when pre-flight banner triggers, flag:
- Rules unused in last 60 days → "candidate for removal" (still auto-apply).
- Rules unused in last 90 days → **auto-demoted to `advisory`** — do NOT auto-apply at tier 3 of the 4-tier precedence. A 120-day rule is explicitly NOT applied. See `config-schema.md` → Staleness + auto-demotion for the full rule. Closes PLG-clickup-F15.
- Rules applied >20 times → "confirmed useful, leave alone" (overrides staleness flags).

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
  Shared with:   /clickup, /gevent

clickup/config.json
  Workspace:     Speed&Functions (id: 90151491867)
  Lists:         7 aliased
  Lists last validated: <duration> ago  (oldest: "<name>" <D>d ago, freshest: "<name>" <d>d ago)
                                         → run /clickup:reload  (if oldest > 30 days)
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
   - If their `external_ids.clickup` is NOT in the new workspace → set `active: false`, keep all other fields (email, name, `/gevent` still uses them).
5. Prompt: "Run `/clickup --onboard workspace` if you want to refresh lists + add aliases for this workspace."

---

## reload

Incremental reconciliation of `~/.claude/clickup/config.json` `lists[]` against the active ClickUp workspace. Preserves aliases by `id`. Surfaces renames, adds, archived/missing in a confirm card. Auto-routes massive diffs to `/clickup:onboard workspace` with `lists_archive[]` carry-forward.

### Common workflow

1. After ClickUp workspace changes (rename, add, archive), run `/clickup:reload`.
2. Review the confirm card.
3. Pick aliases for new lists in the inline prompt (single `AskUserQuestion` round, default = lowercased name stripped of brackets).
4. Confirm. Done.

### Flow

1. **Pre-flight**: inherits SKILL.md → Step 2 (identity, config, schemaVersion, MCP auth probe with the 4-bucket classification — `auth-ok` / `auth-fail` / `retryable-network` / `other`). Reload does NOT duplicate these checks.

2. **Parse `--mode`**: accept `--mode=incremental` or `--mode=full`. If neither, threshold decides.

3. **Fetch workspace hierarchy** via `mcp__clickup__clickup_get_workspace_hierarchy`. Filter to the workspace whose `id` matches `config.workspace.id`. **Empirical question for executor**: confirm whether the call returns archived lists by default; if so, filter them out (`mcp_lists = [l for l in mcp_lists if not l.get("archived")]`) before the diff. Document the empirical answer in a comment.

4. **Defensive halts** (each is a one-line refusal; do NOT mutate config):
   - If MCP returns 0 workspaces → `"workspace ${name} not visible to current MCP auth — re-onboard"`.
   - If MCP returns workspaces but `config.workspace.id` is not among them → `"active workspace ${name} (${id}) not in MCP results — auth scope changed; re-onboard"`.
   - If MCP returns 0 lists for the active workspace AND stored `lists[]` has > 0 active records → `"MCP returned 0 lists for ${name} (had ${N} stored) — refusing to auto-archive; run /clickup:status"`.
   - If two stored records share the same `id`, OR two MCP records share the same `id` → `"duplicate list_id ${id} — refusing reload (data corruption); investigate config.json or report MCP bug"`.

5. **Filter empty ids**: drop any entry from either side with empty / null / whitespace-only `id`. Defensive.

6. **Categorize the diff** (by `id`):
   - **renamed**: `s.id == m.id and s.name != m.name`.
   - **added**: `m.id not in stored_active_ids`.
   - **archived_or_missing**: `s.id not in mcp_active_ids and not s.archived`.
   - **moved (silent)**: `s.id == m.id and (s.space_id != m.space_id or s.folder_id != m.folder_id)`. Update silently; do not surface in confirm card. Future `--verbose` flag may surface.
   - **workspace_renamed (silent)**: if MCP's workspace name differs from `config.workspace.name`, update silently. Workspace renames are organizational housekeeping, not list-level operations.

7. **Threshold metric**: Jaccard on `lists[].id` sets.
   - `S = {x.id for x in stored_active}`; `M = {x.id for x in mcp_active}`.
   - `J = |S ∩ M| / |S ∪ M|` if `|S ∪ M| > 0` else 1 (no change).
   - `change_pct = round((1 - J) * 100)` for user-facing copy.
   - **Small-N guard**: if `max(|S|, |M|) <= 3` → always incremental.
   - **Threshold**: `J < 0.5` AND not small-N → route to full (with confirm).
   - **Override flags always win**: `--mode=incremental` and `--mode=full` skip the threshold.
   - The threshold value `0.5` is documented as a Schelling-point default; tunable via a future config setting (out of scope for this PR).

8. **Confirm card (incremental)** — render as monospace block. Order: header, change rows (renamed → added → archived/missing), totals + metric, snapshot path, action prompt:

   ```
   /clickup:reload — workspace "<name>"
   ─────────────────────────────────────────
    Renamed lists:                            (<N>)
      <old name> → <new name>                      (id: <id>)
                                                   aliases preserved: [<a>, <b>, ...]
    Added lists:                              (<N>)
      <name>                                       (id: <id>)
                                                   propose aliases? [text input]
    Archived/missing in MCP:                  (<N>)
      <name>                                       (id: <id>)
                                                   alias kept; resolution will refuse with archive notice

    Total: <N> changes  |  metric: Jaccard=<J>, <change_pct>% changed → incremental
    Snapshot: ~/.claude/clickup/.snapshots/<ISO>.json

   [1] Apply  [2] Cancel  [3] Pick aliases for new lists first
   ```

9. **Confirm card (massive — Jaccard `< 0.5`, not small-N, no `--mode` override)**:

   ```
   /clickup:reload — workspace "<name>"
   ─────────────────────────────────────────
   ⚠ Massive divergence detected.

    Renamed: <N>    Added: <N>    Archived/missing: <N>
    Stored <X> lists; MCP returned <Y> lists.
    Jaccard on list-ids: <J> (threshold: 0.50; <change_pct>% changed → full)

    Recommended: route to /clickup:onboard workspace with current `lists[]`
                 archived to `lists_archive[]`. The wizard will display the
                 archived aliases as a reference panel during alias entry —
                 you can copy them across to the new lists by hand. (No
                 automatic alias inheritance — the id-to-id mapping is
                 ambiguous in a massive-diff scenario.)

   [1] Route to onboard-workspace   [2] Force incremental anyway   [3] Cancel
   ```

10. **On user pick `[1] Apply` (incremental)**:
    - **Acquire flock** on `~/.claude/clickup/.config.json.lock`.
    - **Re-read** `config.json` inside the lock (M-5 stale-read guard — never trust the pre-confirm read).
    - **Re-run quarantine gate** per `atomic_update` semantics (missing/non-int `schemaVersion` → quarantine + abort).
    - **Re-compute the diff** vs MCP. If it differs from the previewed diff (concurrent writer scenario), abort with `"config changed during preview — re-run /clickup:reload"`. User re-runs.
    - **Write snapshot** to `~/.claude/clickup/.snapshots/<YYYY-MM-DDTHHMMSSZ>.json` (ISO without colons for filesystem portability) via tempfile + fsync + `os.replace` (the snapshot is itself an atomic write — never naive `open().write()`).
    - **Apply mutations** to in-memory `data`:
      - For each renamed: `data.lists[i].name = new_name; data.lists[i].last_validated_at = <now>`.
      - For each added: append `{id, name, aliases: [user-supplied list], space_id, folder_id, archived: false, last_validated_at: <now>}`.
      - For each archived_or_missing: `data.lists[i].archived = true; data.lists[i].removed_at = <now>; data.lists[i].last_validated_at = <now>`.
      - For each unchanged in MCP: bump `data.lists[i].last_validated_at = <now>`.
      - Silent updates (moved space/folder, workspace rename): apply without surfacing.
      - `data.updated_at = <now>`.
    - **Write** `config.json` via tempfile + fsync + `os.replace` + parent-dir fsync. SAME critical section.
    - **Release flock**.
    - **Prune snapshots**: keep last 5 by mtime. Failures silent (per existing `atomic_update` style).
    - **Print post-apply banner** with undo affordance:
      ```
      ✓ /clickup:reload applied (<N> changes). To undo:
        cp ~/.claude/clickup/.snapshots/<ISO>.json ~/.claude/clickup/config.json
      ```

11. **On user pick `[1] Route to onboard-workspace` (full)**:
    - **Acquire flock** on `~/.claude/clickup/.config.json.lock`.
    - **Re-read** + quarantine gate.
    - **Append** current `data.lists[]` to `data.lists_archive[]` (do NOT replace; never delete from `lists_archive[]` in this command).
    - **Write snapshot** + write config + release flock + prune snapshots (same as step 10).
    - **Invoke** the `## onboard-workspace` flow. The wizard reads `config.lists_archive[]` and, during its alias-input step (modes.md → onboard-workspace step 2), surfaces a reference panel: *"Previously aliased lists from your archive: ..."* — purely informational; user copies aliases manually if desired. No automatic id-to-id inheritance.

12. **On user pick `[2] Cancel`**:
    - No mutation. No snapshot. Banner: `/clickup:reload — cancelled, no changes`.

13. **No-diff case**: if diff is empty AND no `--mode` override changes things:
    - Acquire flock; re-read; bump `last_validated_at` on all active lists; write; release.
    - Skip snapshot (no destructive change).
    - Banner: `✓ /clickup:reload — no change since last reload (<duration> ago); last_validated_at bumped`.

### Threshold examples (math sanity)

| stored | mcp | added | removed | renamed | J | route |
|---|---|---|---|---|---|---|
| 5 | 6 | 1 | 0 | 1 | 5/6 = 0.83 | incremental |
| 7 | 7 | 0 | 0 | 7 | 7/7 = 1.00 | incremental (renames-only) |
| 10 | 10 | 0 | 0 | 0 | 1.00 | incremental (no-op; bump validated) |
| 10 | 15 | 5 | 0 | 0 | 10/15 = 0.67 | incremental |
| 10 | 10 | 5 | 5 | 0 | 5/15 = 0.33 | full |
| 1 | 1 | 0 | 0 | 1 | 1/1 = 1.00 | incremental (small-N) |
| 1 | 2 | 1 | 0 | 0 | 1/2 = 0.50 | incremental (small-N guard active) |
| 1 | 3 | 3 | 1 | 0 | 0/4 = 0.00 | incremental (small-N guard) |
| 0 | 50 | 50 | 0 | 0 | 0/50 = 0.00 | full (executor: probably refuse and route to onboard-workspace explicitly) |

### Snapshot & retention

- Path: `~/.claude/clickup/.snapshots/<YYYY-MM-DDTHHMMSSZ>.json` (no colons in filename — filesystem portability).
- Hidden subdir; matches `.config.json.lock` dot-prefix convention.
- Created `mode=0o700` if it doesn't exist; matches user-state perm convention.
- Retention: keep last 5 by mtime. Prune at END of reload flow (after successful write) so a crash mid-reload leaves the snapshot for forensics. Failures silent.
- No retention on `lists_archive[]`; manual purge belongs to a future `/clickup:reload --purge-archive` command (out of scope).

### Edge cases

- `--reload --auto` → parse-time refuse (mirrors `--onboard --auto`).
- Concurrent writer detected on re-read → abort + tell user to re-run.
- User Ctrl-C between confirm and apply → no flock taken yet; no mutation. Safe.
- User Ctrl-C between snapshot write and config write → snapshot exists; config unchanged. Re-running reload re-snapshots and proceeds.
- Empty workspace (S=M=∅) → no-op banner.

### Status banner integration

`## status` mode (this file, above) gains a one-line surfacing of config staleness. In the `clickup/config.json` block of `/clickup:status` output, add:

```
  Lists last validated: <duration> ago  (oldest: "<name>" <D>d ago, freshest: "<name>" <d>d ago)
```

Computed as `max(lists[].last_validated_at)` for the headline duration, with min/max teammate names for context. If max > 30 days, append the recommendation `→ run /clickup:reload`.
