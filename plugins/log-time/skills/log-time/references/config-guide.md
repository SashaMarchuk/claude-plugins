# What can live in `~/.claude/log-time/config.md`

The config is **free-form markdown**. The skill reads the whole file and treats it as binding instructions — the section names below are a helpful convention (the onboarding wizard uses them), not a schema. Anything that fits nowhere goes in its own section and is applied all the same.

**Every example below is illustrative mock data** for a fictional company. Replace all of it with your own reality during `/log-time:onboard`, or edit the file by hand any time — it's just text.

## Sources

Where the skill looks for evidence of how you spent time. Each line: what it is, how to read it, what it proves. Built-in playbooks exist for calendar, task tracker, Claude Code sessions, and meeting transcripts — custom sources just need a plain-text description.

```markdown
## Sources
- Google Calendar — via the find-call plugin (preferred) or calendar MCP/CLI.
  Proves: meeting time, exact durations.
- Jira — via MCP. Proves: task ownership (comments, status changes).
- Claude Code sessions — ~/.claude/projects. Proves: solo dev time per repo.
- Custom: standup bot — run `acmebot reports --mine --after <date>`
  (needs ACMEBOT_TOKEN from ~/.acme/env — source it, never print it).
  Proves: my own written account of each day. Treat as primary narrative.
- Custom: Google Sheet "Team hours", tab "Q3" — rows where Owner = me.
  Proves: manually pre-logged blocks.
```

A per-source fix hint is worth adding for anything that breaks often (e.g. "if calendar returns invalid_grant, run `<your re-auth command>`").

## Targets

Where time gets logged — tracker projects/issues plus any mapping rules. The skill flags unmapped work instead of guessing.

```markdown
## Targets
| Tracker project | Issue | Covers |
|---|---|---|
| [ACME] Platform | Task #10101: Platform maintenance | infra, CI, on-call |
| [ACME] Mobile   | Task #10204: App v2 development  | mobile app work   |

Mapping rules:
- Repo acme-api or acme-infra -> #10101
- Meetings titled "Mobile sync" or with the mobile team -> #10204
- Anything labelled "interview" -> #10309 (recruiting)
```

## Day rules

All optional. **With no daily target the skill logs evidenced time only** — a 4.75h day is emitted as 4.75h. Set a target only if you always log a fixed number of hours; if you set one, also say how gaps may be filled and capped.

```markdown
## Day rules
- Steady daily target: 7.5h (Mon-Fri). Gap-fill: assign slack to the day's
  dominant project; cap gap-fill at 1.5h/day; trim solo time before meetings.
- Weekend work rolls forward: Sat -> Fri's log, Sun -> Mon's log.
- Skip: declined calendar events, the "Lunch & learn" series, repo acme-sandbox.
```

## Output style

What an emitted entry looks like. A date prefix like `[dd.mm]` is **suggested** (handy for bulk imports) but entirely optional — decline or reshape it here.

```markdown
## Output style
- Prefix each entry with [dd.mm].
- Task entries: [dd.mm] {<task-id> : <task name>} <one-sentence description>
- Meeting entries: [dd.mm] <meeting title verbatim>
- Plain ASCII only (our Redmine CSV import garbles unicode).
- One activity per row; prep for a call is its own row, never folded into the call.
- Run artifacts: keep the default ~/.claude/log-time/runs/.
```

## Anything else

Free-form rules that fit no section still bind — e.g. "never log more than 0.5h to recruiting without asking", "treat the standup source as ground truth of intent when sources conflict". Write them the way you'd brief a careful assistant.
