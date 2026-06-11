---
name: log-time
description: Generate a paste-ready time-log for Redmine (or any tracker the user's config describes) by cross-checking the evidence sources the user configured — calendar events, task-tracker activity, Claude Code session history, meeting transcripts, spreadsheets, or any custom source. Behavior (sources, target tickets, day rules, output format) comes from the free-form config at ~/.claude/log-time/config.md; the skill itself makes no assumptions about working hours or which sources exist. Use ANY time the user wants to log time, prep daily/weekly tracker entries, reconstruct what they did on past dates, batch-fill timesheets, or asks "what was I working on between X and Y" with the intent of logging hours. Trigger on phrases like "/log-time", "log my time", "log time", "time log", "redmine entries", "timesheet", "fill in my hours". Evidence-only output with confidence ratings; read-only against every source.
user-invocable: false
---

# /log-time — Universal time-log builder

You are helping the user reconstruct what they actually worked on across past days and turn it into paste-ready time-tracker entries (Redmine by default — any tracker their config describes). The skill supplies the *mechanics* — preflight, parallel evidence gathering, synthesis, allocation, emit. The user's config supplies every *rule* — which sources to check, which tickets to log against, how a day should add up, and what an entry looks like.

This is an accuracy-over-speed workflow. Cross-reference everything, flag uncertainty, never pad.

## Operating principles

1. **Evidence first.** Every emitted entry traces back to something a source actually shows. Never invent work, never fabricate hours, never silently fill gaps.
2. **The config is the contract.** `~/.claude/log-time/config.md` is free-form markdown written by the user (or the onboarding wizard). Read it top to bottom and treat it as instructions: its sources, ticket targets, day rules, skip rules, and output style override every default in this file.
3. **No assumed daily target.** The skill has no built-in notion of how many hours a day "should" contain. Without a target in config, output is evidenced-only — a day may total 3.25h and that is correct output. A target exists only if the user's config declares one or the user states one for this run.
4. **Use whatever tools the user has.** Each source is satisfied by any working method — MCP tool, CLI, local files, a spreadsheet read. Preference comes from config, but it is preference + fallback, never a wall: if the preferred method fails, try the next available one and note the substitution.
5. **Read-only against every source.** Never write to the calendar, tracker, transcripts, spreadsheets, session history, or `~/.claude/shared/identity.json`. Never write time logs into any tracker — output is paste-ready text the user applies themselves. The only files this skill writes are its own config (via `--onboard` / `--config`, with confirmation) and per-run artifacts.
6. **Degrade gracefully — but never run unconfigured.** A broken source is a question for the user ("fix it or proceed without?"), not a dead end. A missing config routes straight into onboarding: the wizard runs first, then the original request continues.

## Step 0 — Load config + identity

Run this before anything else, in every mode:

1. Read `~/.claude/log-time/config.md`. If present, internalize every section — sources, targets, day rules, output style, plus any free-form rules that don't fit those headings (they are equally binding).
2. **If absent, onboarding is mandatory.** In every mode except `--status`: tell the user there is no config yet, switch directly into the `## Mode: --onboard` flow, and only after the config file is written resume what they originally asked for. **Never build a time-log without a config on disk**; never silently substitute defaults. (`--status` just reports the missing config.) The wizard's steps remain individually skippable — skipped sections become commented placeholders — so even a minimal pass produces a config and this forced detour happens exactly once.
3. Read `~/.claude/shared/identity.json` if it exists (read-only — this skill never writes it) to learn the user's name/email for matching calendar attendance and tracker activity. Do not HALT if it is missing — proceed and resolve "me" per-source at runtime. Users of the `clickup` or `gevent` plugins can run their `onboard identity` step to create it.

## Invocation modes

Parse `$ARGUMENTS` first:

| Arguments | Mode |
|---|---|
| `--onboard [sources \| targets \| day-rules \| output]` | Onboarding wizard (writes config) |
| `--config <plain-text change>` | Quick config edit (writes config after confirm) |
| `--status` | Read-only health check |
| anything else (date range, empty) | Default: build the time-log |

## Default mode — build the time-log

A linear flow with one parallel fan-out. Per-run artifacts go to the run directory: `~/.claude/log-time/runs/<range-label>/` unless the config names a different location.

### S1 — PREFLIGHT

Probe every source the config lists **in parallel**, each with the smallest possible read (list one event, fetch one task, stat one file). Produce a table: `[OK | BROKEN | OFF] <source> — <note>`.

For each BROKEN source: show the fix hint (the config may carry one per source — e.g. a re-auth command), then ask the user whether to fix it or proceed without it. Never silently proceed with a degraded source set — the user decides.

### S2 — SCOPE

Parse the date range from the invocation ("this week", "jun 2-6", "yesterday"). If absent, ask via AskUserQuestion (today / yesterday→today / past N working days / custom).

Show a compact summary of the rules that will apply this run — pulled from config, not invented: working days, daily target (or "evidenced-only"), skip rules, output style. One yes/no to confirm or adjust. Per-run adjustments apply to this run only unless the user asks to persist them (then route through the `--config` write path).

Write `scope.md` to the run directory.

### S3 — GATHER (parallel fan-out)

For each OK source, launch one sub-agent (sonnet — never opus or haiku) in the same message so they run in parallel. Each sub-agent reads its single source for the full date range and writes one artifact (`<source>.md`) to the run directory: what the source shows, per day, with timestamps/durations/identifiers verbatim. Keep the main context clean — only artifacts come back.

Source playbooks (apply when the config names the source; these are also what `--onboard` auto-detects):

- **Calendar** — events with title, start/end, attendance/RSVP. If the `find-call` plugin is installed, prefer it for meeting depth — it pulls notes, transcripts, and resources per call. Recommend a calendar connection + `find-call` to any user who logs meeting time; it is the single highest-value source for time-certainty.
- **Task tracker** — the user's tracker activity (ClickUp / Jira / Linear / etc. via whatever MCP or CLI is connected): tasks created, comments, status changes, with timestamps. These confirm ownership of work.
- **Claude Code sessions** — inventory `~/.claude/projects/*/*.jsonl` files modified in range. **Read FIRST LINE + LAST LINE ONLY — never the full file** (session files can exceed 100MB). Compute the session span per project directory per day. Flag raw spans the config would consider implausible.
- **Meeting transcripts** — any connected notetaker MCP, if the user has one. Used to enrich call entries with what the user actually did/committed to.
- **Custom sources** — anything the config describes in plain text: a standup-bot CLI or export, a Google Sheet tab, a git log, an exported CSV. Follow the config's own instructions for how to read it. If a custom source needs credentials (an env file, an API key), load them silently and **never print, echo, or log the secret value**.

### S4 — SYNTHESIZE

Read all gather artifacts and build one evidence map per day in `evidence.md`: what each source shows, cross-checks between them, explicit conflicts (sources disagree) and gaps (time no source accounts for). Apply the config's mapping rules (e.g. "repo X → ticket Y", "meetings titled Z → project W") if it has any; flag anything unmapped instead of guessing.

### S5 — ALLOCATE

Apply the user's day rules from config, per day:

1. Time-certain evidence first (calendar/transcript durations), then tracker- and session-backed work, then anything the user told you directly this run.
2. **If the config declares a daily target**: reconcile to it using the config's own gap rules (what may absorb slack, any caps, what to trim first). If the config declares a target but no gap rules, ask the user once rather than inventing a policy.
3. **If no target**: evidenced-only. Emit exactly what the evidence supports and report the per-day totals as-is. Additionally, ask once: "Is there a steady number of hours you always log per day? If yes I can add it to your config." — and route a yes through the `--config` write path.
4. Apply skip rules from config (sources, projects, event types to exclude). Skipped work is dropped, not re-labeled.
5. Rate every entry: 🟢 HIGH (multiple sources agree), 🟡 MED (single source), 🔴 LOW (inferred — only permitted where the config's own rules created the entry, e.g. target gap-fill; never from nothing).

**Adaptive target suggestion:** if the user corrects day totals to the same number repeatedly — within this run or visibly across runs — suggest adding that number as a steady daily target to config. Suggest once; never silently apply it.

Write `allocation.md` with every decision documented.

### S6 — EMIT

Two outputs, produced together and verified to agree:

- **Chat output** — the entries, grouped by day, no preamble. One activity per row — never weld two activities with "+" or "and"; split and divide the hours instead. End with a one-line totals + confidence summary.
- **Audit file** — `daily-log.md` in the run directory: rules applied, per-day breakdown, confidence legend and per-entry ratings, "rock-solid vs inferred" sections. Confidence markers live here, not in the tracker-bound text. Tell the user the path.

Entry format comes from the config's output style section. Defaults when the config doesn't say otherwise:

- A date prefix on each entry (e.g. `[dd.mm] <text>`) is **suggested, not mandatory** — it helps when entries are bulk-imported later, and the config can turn it off or reshape it.
- Hours belong in the tracker's hours field, never inside the entry text.
- If the config asks for ASCII-only output (some tracker CSV imports garble unicode), honor it strictly in tracker-bound text.

## Mode: --onboard

Four steps, **each individually skippable** — a skipped step writes a commented placeholder section the user can fill later. Sub-arg re-runs a single step. Use AskUserQuestion throughout; never assume answers. See `references/config-guide.md` for what each section may contain (illustrative mock examples only).

1. **Sources** — auto-detect what is already available (calendar MCP/CLI, `find-call` plugin, tracker MCPs, `~/.claude/projects` session files, notetaker MCPs) and present the findings; the user toggles each on/off and may add any number of custom sources in plain text (what it is, how to read it, what evidence it gives). If no calendar source is found, recommend connecting one and installing `find-call` — call evidence is the strongest time signal.
2. **Targets** — where time gets logged: tracker projects/issues/tickets and any mapping rules ("work on repo X → ticket Y"). Free-form; paste a table or describe it.
3. **Day rules** — all optional: a steady daily target ("is there a fixed number of hours you always log? Leave unset to log evidenced time only"), working days, weekend handling, skip rules, gap-fill rules and caps if a target is set.
4. **Output style** — entry templates, date-prefix preference (suggest it, let them decline), ASCII-only toggle, run-artifacts location.

Compose the full `~/.claude/log-time/config.md`, show it to the user, and write only after explicit confirmation. If a config already exists, show a diff against it instead of overwriting blind.

This mode is also entered automatically by Step 0 whenever no config exists — finish the wizard, then return to whatever the user originally asked for.

## Mode: --config

The quick-edit path — settings must stay easy to change. Read the current config, apply the user's plain-text change to the relevant section (or a new free-form section if it fits nowhere), show a before/after diff, and write only after explicit confirmation. This and `--onboard` are the **only write paths** to the config file.

## Mode: --status

Read-only — writes nothing. Report: config file present or not, which sections it contains, identity file present or not, then the same parallel minimal-read probes as S1 with the `[OK | BROKEN | OFF]` table and per-source fix hints.

## Things to never do

- **Never fabricate hours or invent work.** Cite every entry's evidence in the audit file. Thin days stay thin unless the user's own config rules say otherwise.
- **Never assume a daily target.** No number is built in; it comes from the user's config or their explicit instruction.
- **Never write to any evidence source** — calendar, tracker, transcripts, spreadsheets, session history, identity file. Output is paste-ready text only.
- **Never read full session JSONL files** — first line + last line only.
- **Never print credential values** that a custom source loads (env vars, API keys) — reference them by name only.
- **Never use WebFetch on Google URLs** — they require auth and return junk; use the user's connected calendar/docs tooling instead.
- **Never build a time-log when no config exists** — route into onboarding first, every time, until a config is on disk.
- **Never bypass the confirmation step on config writes** — every write shows the content (or diff) first.
- **Never put confidence markers or emoji in tracker-bound entry text** — they live in the audit file.
