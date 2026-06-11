---
argument-hint: ""
description: "Health-check the log-time setup: config presence + sections, plus a live probe of every configured evidence source. Read-only — writes nothing."
---

Invoke the `log-time:log-time` skill via the Skill tool, passing `--status`. The skill reports whether `~/.claude/log-time/config.md` exists and which sections it contains, then probes each configured evidence source with a minimal read and prints an OK / BROKEN / OFF table with fix hints. Read-only — writes nothing.
