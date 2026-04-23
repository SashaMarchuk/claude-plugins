---
argument-hint: "--task=name"
description: "Resume a paused /ultra run from its last checkpoint. Requires --task=name so state can be located."
---

Invoke the `ultra:ultra` skill via the Skill tool, passing `--resume $ARGUMENTS`. The skill's SKILL.md loads the named task's coordination state (see `${CLAUDE_SKILL_DIR}/coordination.md`) and continues from the recorded phase + agent index.
