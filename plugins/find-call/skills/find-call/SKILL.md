---
name: find-call
description: Pulls deep, cited context from the user's past Google Calendar meetings when they want to investigate, summarize, recall, or extract decisions/action-items from a past call. Reads the canonical "Meeting Resources" block (Transcription, Meeting Notes, Video, Parent Folder) that notes/transcription bots auto-append to event descriptions, plus optional transcripts (Sembly or any connected notetaker) in parallel; spawns sonnet sub-agents per matched call when transcript-depth is warranted. Uses whatever calendar/doc/transcript tools are available by default, configurable per source via ~/.claude/find-call/config.json. Resolves teammate names against the shared ~/.claude/shared/identity.json roster (same file /clickup and /g-event use). Read-only — never modifies Calendar/Drive/transcripts. Use when the user says things like "find the call about X", "summarize my call with <name>", "what did I commit to in the Y meeting", "recap the Z call", "what did <name> say about <topic>", "did we decide anything in the <project> meeting", "pull context from the <project> call", or otherwise references a past meeting with investigative intent. DO NOT trigger on: casual narration ("btw, in our call yesterday I told Tom..."), scheduling phrases ("set up a call with X" — that's /g-event), or generic summaries unrelated to a specific past call.
user-invocable: false
---

# /find-call — Call Investigation Skill

You are helping the user pull deep, cited context from their past calls. Many calendars — especially those using a notes/transcription bot (e.g. notes.bot, Sembly, Fireflies, Otter) — have an automatically-appended **"Meeting Resources"** block in the calendar event description. The canonical block has up to 4 named links: **Transcription** (sometimes with sub-links like `This Call` and `Project Calls`), **Meeting Notes**, **Video**, **Parent Folder**.

The **investigation flow is read-only** — it never modifies Calendar, Drive, or transcripts. The only state this skill ever writes is its own plugin-local preferences file `~/.claude/find-call/config.json`, and only through the `--config` wizard. Accuracy and source attribution dominate speed.

> Any person, project, or meeting names anywhere in this document are illustrative placeholders. Real ones resolve against the user's `~/.claude/shared/identity.json` teammate roster — this skill ships with no real names baked in.

## Invocation modes (parse `$ARGUMENTS` first)

| Flag | Mode | Where |
|---|---|---|
| (none) / seed text | Investigate a past call | Workflow below (Steps 1–8) |
| `--status` | Read-only health check — providers + preferences + identity inheritance | `## Mode: --status` |
| `--config` | Interactive source-provider wizard (writes config.json) | `## Mode: --config` |

Precedence on conflict: `--status` > `--config` > default. Positional text with no flag is the call query.

## Operating principles

1. **Calendar is the index.** Every call you care about has a calendar event on the user's calendar. Start there.
2. **Meeting Notes give structured signal cheap.** They're typically rotating Markdown/Doc files. Sections usually include `Topic:`, `Date:`, `Short Summary`, `Key Discussion Points`, `Action Points` (per attendee), `Meeting Resources`. For action-item / decision questions, notes alone usually answer.
3. **Transcripts add tone, verbatim, hesitation, push-back.** Read them via parallel sonnet sub-agents only when the query is interpretive or notes are too thin.
4. **Transcripts are a parallel augment (when available).** Not every call is transcript-indexed (1-on-1s often miss). If a notetaker provider is available (Sembly today, via `mcp__sembly-ai__*`), query it IN PARALLEL with the calendar query; if none is connected — or the user pinned `transcripts: off` — skip it silently and rely on Meeting Notes. See `references/sources.md`.
5. **Cite everything.** Every claim in your output anchors to a Doc URL, a transcript line, or a Sembly meeting ID. No floating "based on the meeting" claims.

## Step 0 — Load identity (every invocation, before searching)

Read `~/.claude/shared/identity.json` — the same file `/clickup` and `/g-event` write. This skill is a **read-only consumer**; it never writes this file. Extract:

- `user.name` — used in sub-agent prompts and output ("the user's commitments"). Substitute it wherever this doc says **{user.name}**.
- `user.email` — the organizer; auto-excluded from attendee lists; its domain is the implicit "internal" domain.
- `teammates[]` (`first_name`, `latin_alias`, `full_name`, `email`, `active`) — the attendee-name resolver input. When the user names someone by first name, match against these.
- `trusted_domains[]` — internal-org domains; used only to label attendees as internal vs external in output. Has no security gate here (read-only skill).

**Optional, soft dependency on `/g-event`:** if `~/.claude/g-event/config.json` exists — or, for users who have not yet migrated from the old plugin name, the legacy `~/.claude/gevent/config.json` (read the new path first; fall back to the legacy one only when the new path is absent) — read `defaults.calendar` (use it as the calendar ID instead of `primary`) and `always_include[]` (the `notes_bot` entry's email tells you which bot appends the Meeting Resources block). If neither file is present, default the calendar to `primary` and treat the notes bot as unknown — neither is required.

### Resolve source providers (preference + fallback)

Read `~/.claude/find-call/config.json` if it exists, section `sources`. This is the only file the skill ever writes, and only via the `--config` wizard — the investigation flow only reads it. It sets, per source, the user's **preferred provider order** — NOT a hard restriction. No file (or no `sources` block) → every source is `auto`. Full model + schema + examples: `references/sources.md`. Summary:

- `sources.calendar` — `auto` (default) | `cli` | `mcp`. `auto` = default order (prefer `npx @googleworkspace/cli`, then a connected Google Calendar MCP). `cli` = try CLI first, then fall back to MCP. `mcp` = try MCP first, then fall back to CLI. All values fall back; the difference is only which is tried first.
- `sources.docs` — `auto` (default) | `cli` | `mcp` | `off`. Same preference+fallback as calendar; `off` = never fetch Meeting Notes (summarize from calendar + transcripts only).
- `sources.transcripts` — `auto` (default) | `off` | `["sembly", …]`. `auto` = use every connected notetaker MCP (Sembly today; future ones picked up automatically). `off` = notes-only, never read a transcript even on interpretive queries. A list sets a *preference order* — try those first, then fall back to any other connected notetaker.

**Guiding principle — get the data.** The config is a *preference*, never a wall. Try the preferred provider first; if it's unavailable, unauthenticated, errors, or returns nothing, fall through to the next available provider for that source. Only report a source as unavailable when *every* provider for it failed. Detect provider availability from the session tool list — don't assume. The two genuine hard limits: `off` disables a source on purpose, and `WebFetch` is NEVER a provider for Google URLs (it can't supply the auth they need).

**If `~/.claude/shared/identity.json` is missing or has no `user`:** degrade gracefully. Calendar search still works against `primary`; attendee-name resolution falls back to matching the literal name against event attendee `displayName`/`email`. Surface a one-line banner once:

```
ℹ No ~/.claude/shared/identity.json found — teammate-name resolution is limited. Run `/clickup:onboard identity` or `/g-event:onboard identity` once to set up your profile + roster (shared across all three plugins).
```

Do not HALT — this skill is useful even with zero config.

## Tooling rules (HARD CONSTRAINTS)

Which tool you use for each source is resolved from `sources.*` (Step 0) as a *preference order* — try the preferred provider first, fall back to the next available one until the data is retrieved.

- **Google Calendar:**
  - CLI path: `npx @googleworkspace/cli calendar events list --params '<JSON>'`.
  - MCP path: a connected Google Calendar MCP's list-events tool (`mcp__*Google_Calendar*__list_events`).
  - Order by `sources.calendar` (`auto`/`cli` → CLI first; `mcp` → MCP first). If the first choice is unavailable/unauthenticated/errors, fall back to the other. Only fail if both fail — then tell the user how to enable one.
  - NEVER `WebFetch` for any Google URL under any provider (Google URLs need auth WebFetch can't supply).
- **Google Doc / Drive text** (`sources.docs`, ordered the same way; falls back between paths):
  - CLI path: `npx @googleworkspace/cli drive files export --params '{"fileId":"<id>","mimeType":"text/plain"}' --output ./.tmp/find-call/<id>.txt`. The `--output` path MUST be inside the current working directory — `/tmp/...` is rejected by the CLI. Then `Read` the local file.
  - MCP path: a connected Drive MCP read tool.
  - `off`: skip notes entirely (the one value that does NOT fall back — it's a deliberate disable).
- **Transcripts** (`sources.transcripts`): try the preferred notetaker(s) first, then fall back to any other connected one. Sembly — `mcp__sembly-ai__list_meetings` for index, `mcp__sembly-ai__get_meeting` for content. Read-only methods only. If no notetaker is connected (or `transcripts: off`), skip transcripts and say so.
- **WebFetch:** ONLY for non-Google URLs and only as last resort.
- **Sub-agents:** `subagent_type: general-purpose, model: sonnet`. Never opus for transcript reading; never haiku.
- **NEVER:** modify any calendar event, doc, drive folder, or transcript/meeting. NEVER write time logs.

## Workflow

### Step 1 — Parse query, build search predicate

Extract from the user's message:
- **Topic keywords:** content nouns/phrases ("retention", "onboarding flow", "the API migration").
- **Person references:** first names → match against teammate `first_name`/`latin_alias`/`full_name` from identity.json, then against attendee `displayName` and `email` username.
- **Time anchor:** "yesterday", "last week", "Tuesday", "April 28". If absent, default range = past 7 days.
- **Intent verbs:** "summarize", "recap", "what did I commit", "what did X say", "tone", "react", "push back", "verbatim". Interpretive verbs flag transcript-depth need (Step 4).

### Step 2 — Parallel search: Calendar + transcripts

Run BOTH in parallel via parallel tool calls in the same message, each through its resolved provider (Step 0). Skip the transcript query if `transcripts: off` or no notetaker MCP is connected.

**Calendar** (provider `cli`/`auto` shown; under `mcp`, call the Calendar MCP's list-events with the same range):
```bash
npx @googleworkspace/cli calendar events list --params '{
  "calendarId":"<defaults.calendar or primary>",
  "timeMin":"<range_start_minus_1day>T00:00:00Z",
  "timeMax":"<range_end_plus_1day>T23:59:59Z",
  "singleEvents":true,
  "maxResults":50,
  "orderBy":"startTime"
}'
```
Pad ±1 day for local-time/UTC boundary. Filter out `eventType in ('workingLocation','focusTime','outOfOffice')`.

**Transcripts** (e.g. Sembly, when connected and not `off`):
```
mcp__sembly-ai__list_meetings(start_at=range_start, finish_at=range_end)
```

### Step 3 — Score & rank candidates

For each event, compute a relevance score:

```
score = (3 if exact phrase substring in title else 0)
      + (2 per attendee-name match if user named someone)
      + (1 per significant keyword match in title or description preamble)
      + (recency: this-week=2, this-month=1, older=0)
      - (1 if the user's responseStatus == "declined")
```
> `# TUNE-ME` — these constants are v1 starting points; revisit after a few weeks of real use.

### Step 4 — Disambiguation (tiered)

**Decision tree:**
- 0 matches → expand range to 30 days, retry. If still 0, ask "Searched 30 days, no match for '<query>'. Want me to widen to 90 days or check all-time?"
- 1 match → proceed silently to Step 5.
- 2-3 matches AND `top_score / second_score > 1.5` AND top is within last 7 days → silent auto-pick top, but show inline "Picked '<title>' (also considered: <Y>, <Z>); say 'no, <Y>' to switch."
- 2-3 matches with close scores → `AskUserQuestion` with dated options.
- ≥4 matches → `AskUserQuestion` with options grouped by week, plus an "All <N> (parallel investigation)" option capped at 10 events. If N>10, ask user to narrow first.

**AskUserQuestion format:**
```
question: "Found <N> matches for '<query>' — which did you mean?"
options:
  - "<Apr 28> — <Title> (<duration>)"
  - "<Apr 25> — <Title> (<duration>)"
  - "All <N> (parallel)"
  - Other (user types narrower phrase)
```

### Step 5 — Per-match data fetch (parallel)

For each selected event:

1. **Parse the description HTML.** Use this regex set to extract the Meeting Resources links:
   - Doc IDs: `https://docs\.google\.com/document/d/([A-Za-z0-9_-]+)` — capture all and label by adjacent link text (`This Call`, `Project Calls`, `Open`).
   - Drive file: `https://drive\.google\.com/file/d/([A-Za-z0-9_-]+)`
   - Drive folder: `https://drive\.google\.com/drive/folders/([A-Za-z0-9_-]+)`
   - Strip query strings (`?usp=drivesdk`, `?tab=t.0`) before passing to the CLI.

2. **If Meeting Resources block present:**
   - Always pull **Meeting Notes** (`drive files export` → `./.tmp/find-call/<docId>.txt`).
   - Skip Video unless the user explicitly asks ("did anyone show their screen"). The video is binary; this skill doesn't transcribe video.

3. **If Meeting Resources block ABSENT (common for 1-on-1s and bot-less calls):**
   - Try Sembly (if connected): search `list_meetings` results for date+title fuzzy match → `get_meeting` if hit.
   - If both miss → return: "Found '<title>' on <date> but no Meeting Notes / Sembly transcript exists. Calendar description: '<truncated>'. Want me to look at adjacent events?"

4. **Sembly augment (when available):**
   - For each matched event, also pull `get_meeting` if its date+title fuzzy-matches any item in the parallel `list_meetings` result.
   - Sembly's structured fields (decisions, tasks, risks, requirements, issues) are higher-signal than raw transcript and are independent of the notes-bot output.

### Step 6 — Depth decision (notes-only vs transcript-subagent)

For each matched event, decide whether to spawn a transcript sub-agent:

**Spawn transcript sub-agent when ANY of:**
- Number of matched events ≤ 5 (uniform-parallel default).
- Query contains an interpretive trigger word: `tone, react, push back, hesitate, lash, rant, verbatim, exact words, mood, defensive, confident, convince, justify, explain, defend, body language` (liberal — when in doubt, include).
- The Meeting Notes section for this event is < 2K tokens (notes likely truncated/missing).
- The user's message contains "deep dive", "transcript", "full context", "everything they said".

**Cap:** maximum 5 transcript sub-agents per query. If matches > 5 and the cap is hit, deep-read the top-5-ranked and notes-only the rest. Tell the user explicitly which is which.

**Sub-agent prompt template (sonnet, general-purpose):**
```
You are a transcript reader for one call. Read this transcript and answer:
1. What did {user.name} personally say or commit to? (quote verbatim with line refs if available)
2. What decisions were made and by whom? (cite the speaker)
3. What action items exist for {user.name}? (cite the moment)
4. <the user's specific question if any>
Source files (read these and ONLY these):
- Notes: <local path>
- Transcript: <local path or Sembly meeting id>
Sembly meeting id (optional): <id>
RULES:
- Cite every claim with a quote or line reference. Never paraphrase a commitment without a quote.
- If the transcript doesn't contain an answer, say "transcript does not contain this" — do not invent.
- Output ≤ 1500 tokens.
```

### Step 7 — Compose output

**Answer the user's actual question first, directly.** The output exists to answer what was asked — not to fill a template. Lead with the answer; cite it; stop.

- Targeted question ("what did I commit to?", "did the client push back?", "what was decided?") → answer *that*, with citations, and **omit every section that doesn't bear on it**. Don't append a "Key decisions" block to a commitment question, or a generic "Summary" nobody asked for. One matched call + a pointed question can be two sentences.
- Open-ended question ("summarize the X call", "recap my week with Dana") → use the fuller structure below as a *starting* shape, dropping any section with no grounded content.

**Hard rules regardless of shape:** every claim carries a citation (Doc URL / transcript line / meeting ID); state your sources read; if a transcript was NOT read for a call, say so explicitly; never pad with boilerplate, hedging, or generic framing.

**Fallback structure for open-ended summaries** (drop empty sections — do not emit a header with "none"):

```
## <Date> — <Event Title> (<duration>)
Sources read: [Meeting Notes](<doc url>) [• [Transcript](<doc url>)] [• <provider>: <meeting_id>]

**Summary:** <2-3 sentences — only what's grounded in sources>

**Key decisions:** <cite each>  · **{user.name}'s commitments:** <cite verbatim where possible>  · **Open questions / blockers:** <only if present>

<If transcript was NOT read for this match:>
> _Notes-only for this call — say "deep dive on this one" if you want me to read the full transcript._
```

For multiple matched calls, add a 1-paragraph cross-cutting synthesis at the end ONLY if it surfaces a real pattern supported by ≥2 sources — otherwise skip it:
```
**Across these <N> calls:** <synthesis — only patterns supported by ≥2 sources>
```

### Step 8 — Optional: offer to remember the alias (v1: disabled)

> v1 SHIPS STATELESS. Skip this step. The infrastructure below is documented for v1.1.

After successful disambiguation, IF v1.1 has memory enabled, propose:
```
AskUserQuestion: "Want me to remember '<phrase>' = <project>/<event-pattern> for next time?"
options: ["Yes, remember", "No, ask me each time"]
```

On Yes → append to `references/aliases.md` (plugin-local) with `learned: <ISO date>` stamp.

## Anti-slop rules (HARD)

- **Answer the question asked, then stop.** No generic framing, no unrequested sections, no hedging filler. A pointed question gets a pointed, cited answer — not a full templated report.
- **Cite every claim.** Every decision, commitment, quote, or fact in output must link to a Doc URL or transcript/meeting ID. If you can't cite it, don't say it.
- **Don't summarize what you didn't read.** If a transcript subagent was skipped for an event, output explicitly says "Notes-only for this call". Never claim "the team also discussed X" without a source — that's invention.
- **Don't infer attendee positions.** "Dana probably agreed" is forbidden. "Dana said 'I'm fine with that' [transcript line 142]" is fine.
- **No emoji confidence indicators.** This skill returns hard sourced claims; emoji confidence (🟢/🟡/🔴) belongs to other workflows, not this one.
- **Never invent action items.** Only quote action items that appear in the Notes' `Action Points` section or are spoken verbatim in the transcript.
- **Never modify any asset.** This skill makes zero write calls to Calendar / Drive / Sembly / Slack / Gmail. If a follow-up action is needed, tell the user what to do, don't do it for them.

## Failure modes (handlers)

| Code | Symptom | Handler |
|---|---|---|
| F1 | No Meeting Resources block in event description | Try Sembly (if connected) → if miss, return calendar description + offer adjacent-event search |
| F2 | Doc rotated; current `Open` link is the new active file, doesn't contain this meeting | Search exported text for `Topic: <title>` or event date — if not found, fall back to Parent Folder, search archived files by name |
| F3 | Sembly has it, Calendar doesn't | Sembly query runs in parallel; merge by datetime+title fuzzy |
| F4 | Phrase matches >1 events | Tiered disambiguation (Step 4) |
| F5 | Description is HTML, not plain | Use the regex set in Step 5; do not parse as HTML |
| F6 | Timezone boundary misses a borderline event | Pad timeMin/timeMax by ±1 day, filter post-hoc |
| F7 | Title `[PFX] Roadmap Review (External)` doesn't match "Roadmap Review call" | Match against title substring AND attendee names AND description content |
| F8 | Drive export 403 | Catch error, fall back to Sembly for that meeting, surface "permission needed" warning |
| F9 | Notes section <500 tokens | Auto-escalate to transcript sub-agent for that single event |

## Things to never do

- **Never `WebFetch` a Google URL** under any provider — Google URLs need auth WebFetch can't supply. This is the ONLY hard limit on Google access: a Calendar/Drive MCP is fully in play per the resolved order — tried first when `sources.*` is `mcp`, or as the fallback when `cli`/`auto` prefers the CLI but the CLI can't deliver. Never refuse a working MCP fallback.
- **Never write to Calendar/Drive/Sembly/Slack/Gmail.** Read-only.
- **Never write time logs** — that's a different tool's job. If the query is about logging hours, say so and hand off.
- **Never spawn an opus sub-agent for transcript reading.** Sonnet only.
- **Never read full Drive Doc JSON** when the goal is text — `drive files export mimeType=text/plain` is the path.
- **Never load a transcript directly into main context.** Always go through a sub-agent that returns ≤1500 tokens of cited summary.
- **Never invent action items, decisions, or quotes.** If the source doesn't say it, you don't say it.
- **Never auto-pick a match when scores are close** (top/second ratio ≤ 1.5×) — disambiguate via AskUserQuestion.
- **Never write to `~/.claude/shared/identity.json`** (or `g-event/config.json` — including the legacy `gevent/config.json` — or `clickup/config.json`). This skill is a read-only consumer of shared/other-plugin state; `/clickup` and `/g-event` own those writes. The ONLY file this skill ever writes is its own `~/.claude/find-call/config.json`, and ONLY via the `--config` wizard through `scripts/config_io.py`.

## Examples

> Names below are illustrative placeholders. In practice the person references resolve against the user's `~/.claude/shared/identity.json` teammate roster.

**Example 1 — single match, action-item query (notes sufficient):**

> User: "what did I commit to in the AI Assessment Bot meeting yesterday?"

Skill:
1. Calendar list yesterday±1 → matches `AI Assessment Bot` (yesterday).
2. Single match, has Meeting Resources block → pull Meeting Notes only; per Step 6 default for ≤5 matches, also spawn a transcript sub-agent.
3. Output cites `Action Points → {user.name}` section verbatim, with the Doc URL.

**Example 2 — multi-match, "all of them":**

> User: "summarize my calls with Dana this week"

Skill:
1. Calendar list this-week with attendee match `dana.*` (resolved via identity.json) → 3 matches.
2. AskUserQuestion: "Found 3 — which?" with "All 3 (parallel)" option.
3. User picks "All 3" → spawn 3 parallel sonnet transcript sub-agents (under cap of 5).
4. Output: 3 sections + 1 cross-cutting synthesis paragraph.

**Example 3 — no Meeting Resources block:**

> User: "what did Sam and I talk about in our 1-on-1 last week?"

Skill:
1. Match `1on1 - {user.name} / Sam` (last week) — no Meeting Resources block (1-on-1, no notes bot).
2. Sembly parallel search (if connected): hit on the same date+title.
3. Use Sembly's structured `summary`, `decisions`, `tasks` fields.
4. Output cites `Sembly meeting <id>`. If Sembly is not connected, return the calendar description and offer adjacent-event search.

**Example 4 — interpretive query forces transcript:**

> User: "did the client push back when I proposed the limited rollout?"

Skill:
1. Match the relevant client call.
2. "push back" is an interpretive trigger → spawn transcript sub-agent regardless.
3. Sub-agent searches transcript for the client's responses around the rollout-proposal timestamps.
4. Output: verbatim quote with line ref OR explicit "transcript shows the client said '<quote>' immediately after — not pushback per se."

## Sub-skill boundaries

- **`/g-event`** owns event creation/modification. If the query is "schedule" / "move" / "cancel", hand off.
- **`/clickup`** owns task creation. If the query asks to create a follow-up ticket from a call, return the call context but DO NOT call `/clickup` directly — let the user initiate.
- **Time-logging** is a separate concern. If the query is "what did I do" with hour-counting intent, this skill is the wrong tool — say so.

## Mode: --status

**Read-only. Writes nothing.** Shows which provider each source will resolve to, what's connected, and where identity/calendar defaults come from.

1. Run `python <plugin-root>/scripts/config_io.py --show` (e.g. `python plugins/find-call/scripts/config_io.py --show`). It returns JSON: current `sources` preferences, whether the config file exists, any corruption error, and whether the `npx` CLI binary is present (`cli_binary_available`). Auth is NOT probed here — note that the CLI may be present but unauthenticated.
2. Detect connected providers from THIS session's tool list: a Google Calendar MCP (`mcp__*Google_Calendar*`), a Drive MCP, and notetakers (`mcp__sembly-ai__*`). The script can't see session MCPs — this step is yours.
3. Check `~/.claude/shared/identity.json` exists (identity inherited from `/clickup` or `/g-event`) and `~/.claude/g-event/config.json` — falling back to the legacy `~/.claude/gevent/config.json` when the new path is absent — (calendar default).
4. Print a resolution table — for each source: preference → which provider it resolves to first + what's available as fallback (✓/✗). If the config is unset, show `auto` and say "not set — all auto".

```
/find-call:status
  calendar   : auto → cli (googleworkspace CLI present ✓; auth not probed)
  docs       : auto → cli ✓
  transcripts: auto → sembly connected ✓
  identity   : inherited from g-event ✓ (~/.claude/shared/identity.json)
  calendar id: primary (no g-event defaults.calendar)
  config     : ~/.claude/find-call/config.json — not set (all auto)
```

## Mode: --config

Interactive wizard. **This is the ONLY write this skill performs** — and it writes ONLY `~/.claude/find-call/config.json`, via the guarded helper. Never touches `identity.json`, `g-event/config.json` (or the legacy `gevent/config.json`), or `clickup/config.json`.

1. Read current preferences: `python <plugin-root>/scripts/config_io.py --show`. Pre-select the current value for each source.
2. Ask via `AskUserQuestion` — one question per source, marking the current value. Make clear these are *preferences*, not restrictions — the skill always falls back to whatever works (except `off`):
   - **Calendar source** → `auto` (default order) / `cli` (prefer the googleworkspace CLI, fall back to MCP) / `mcp` (prefer a Calendar MCP, fall back to CLI).
   - **Docs source** → `auto` / `cli` (prefer CLI) / `mcp` (prefer MCP) / `off` (never fetch Meeting Notes — the only non-fallback value).
   - **Transcripts** → `auto` (every connected notetaker) / `off` (notes-only, never read a transcript) / `sembly` (prefer Sembly, fall back to other connected notetakers).
3. Persist via the helper (it validates values and writes atomically — `flock` + tmp + `os.replace`):
   ```
   python <plugin-root>/scripts/config_io.py --set calendar=<v> docs=<v> transcripts=<v>
   ```
   Only pass the keys the user changed. The script rejects invalid values rather than writing them.
4. Confirm: print the resulting JSON and "run `/find-call:status` to verify resolution."

Never write any file other than `config.json`. If the script exits non-zero, surface its stderr and do not retry blindly.

## v1 known TUNE-ME items

- Disambiguation scoring constants (Step 3) — invented; revisit after a few weeks of usage.
- Transcript sub-agent cap (5) — revisit if the user routinely picks "All N" with N>5.
- Interpretive-verb list (Step 6) — extend as missed cases surface.
- Memory persistence (Step 8) — disabled in v1; flip in v1.1 if usage justifies it.
