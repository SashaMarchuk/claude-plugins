---
argument-hint: "[<run-name>]"
description: "(beta) Edit a Claude migration run's configuration: tier, parallelism, thresholds, naming convention, bucket display labels, and re-author or swap a source/sink connector via interview. Use when the user types /claude-migrate:config, or says \"change the migration settings\", \"set the tier\", \"edit the bucket labels\", \"swap the connector\"."
---

Invoke the `claude-migrate:config` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the optional `<run-name>`; the skill edits `config.yaml` (tier, parallelism, cost thresholds, naming, bucket role-to-display-label map) and can re-author a connector through a guided interview.
