---
argument-hint: "[sources | targets | day-rules | output]"
description: "Run the log-time onboarding wizard. With no sub-arg: all four steps (sources, targets, day rules, output style), each skippable. With a step name: re-run just that slice."
---

Invoke the `log-time:log-time` skill via the Skill tool, passing `--onboard $ARGUMENTS`. The skill's SKILL.md defines the `--onboard` flow: four skippable steps (evidence sources, tracker targets, day rules, output style) that write the free-form config at `~/.claude/log-time/config.md`. Skipped steps get commented placeholders the user can fill in later by hand or via `/log-time:config`.
