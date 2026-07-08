---
argument-hint: "[project-name]"
description: "Set up this project for the harness — detect repos, choose the ticket source (GitHub issues or local files), workflow (GSD/generic), and guardrails. Writes <project>/.harness/config.json and bootstraps the ticket queue."
---

Invoke the `harness:harness` skill via the Skill tool, passing `--init $ARGUMENTS` through verbatim. The skill's flag router handles the `--init` mode.
