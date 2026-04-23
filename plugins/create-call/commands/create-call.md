---
argument-hint: "[--auto | --onboard [identity|calendar] | --status | --calendar] [<seed text>]"
description: "Create, update, or cancel Google Calendar events with Google Meet. --onboard runs identity+calendar wizard (shared teammate roster with /clickup); --auto creates silently; --status health-checks both config files; --calendar switches default calendar."
---

Invoke the `create-call:create-call` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. The skill's SKILL.md defines the flag precedence (onboard > status > calendar > auto > default), the dual-key attendee resolver (latin_alias → NFC first_name → email with homoglyph-collision gate), and the mandatory tempfile + json.dump contract for every `events insert`/`events patch` CLI call. Pre-flight shadow-check warns loudly if legacy `~/.claude/skills/create-call/` still exists; reads `~/.claude/shared/identity.json` + `~/.claude/create-call/config.json`; HALTs in `--auto` when either is missing.
