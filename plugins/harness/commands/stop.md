---
description: "Stop the active run gracefully: /exit every session (workers first), stop the watch loop and caffeinate. Busy sessions are left open and reported, never force-closed."
---

Invoke the `harness:harness` skill via the Skill tool, passing `--stop $ARGUMENTS` through verbatim. The skill's flag router handles the `--stop` mode.
