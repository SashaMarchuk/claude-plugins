---
description: "Start a harness run: preflight, spawn the orchestrator fleet in terminals, and execute every harness:ready ticket unattended (rate-limit-aware pause/resume, graceful STOP)."
---

Invoke the `harness:harness` skill via the Skill tool, passing `--run $ARGUMENTS` through verbatim. The skill's flag router handles the `--run` mode.
