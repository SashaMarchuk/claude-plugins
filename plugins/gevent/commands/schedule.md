---
argument-hint: "[--auto] [<seed text>]"
description: "Schedule (create / update / cancel) a Google Calendar event. Pass --auto for a silent default-only create; otherwise interactive preview + edit + confirm. Update + cancel are triggered via natural language (move / reschedule / cancel the X call)."
---

Invoke the `gevent:gevent` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. This is the skill's default create / update / cancel dispatch — the skill's own flag parser handles `--auto` if present; otherwise it routes through intent detection (create / update / cancel) per its SKILL.md.
