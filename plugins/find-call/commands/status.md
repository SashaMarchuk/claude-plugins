---
argument-hint: ""
description: "Read-only health check for /find-call — which provider each source resolves to (calendar / docs / transcripts), what's connected, and where identity comes from. Writes nothing."
---

Invoke the `find-call:find-call` skill via the Skill tool, passing `--status $ARGUMENTS`. The skill runs its `## Mode: --status` flow: it reads the current preferences via `scripts/config_io.py --show`, detects connected MCP providers and the workspace CLI from the session, checks identity/calendar inheritance, and prints a resolution table. Read-only — it writes nothing.
