---
created: 2026-08-22
title: Cover interview-handoff with tests
area: test
priority: P2
complexity: small
estimate: half a day
files:
  - tests/run-all.sh
  - plugins/interview-handoff/
---

## Problem

`interview-handoff` shipped with zero test coverage. The repository runs a 170-test regression harness at
`tests/run-all.sh`, and none of those tests touch this plugin. Every other plugin in the marketplace is
covered; this one is not, so a structural mistake in it reaches users silently.

The plugin is structure-heavy rather than logic-heavy: three thin commands, one hidden skill, three
reference documents and a recommendations file. That makes it cheap to test and easy to break, because
almost every failure mode is a file that does not parse, a pointer that does not resolve, or a rule the
architecture requires that quietly stopped being true.

## What to cover

At minimum, and all of it static:

- `.claude-plugin/plugin.json` and `config/recommended.json` parse as valid JSON.
- `config/recommended.json` declares both sources, `session-logs` and `interview-method`, each with a
  `strength` of `weak` and a non-empty `note`.
- The skill's frontmatter sets `user-invocable: false` and keeps `disable-model-invocation: false`.
- Each of `commands/run.md`, `commands/collect.md`, `commands/config.md` delegates to the skill and passes
  `$ARGUMENTS` through, and carries no workflow steps of its own.
- Agnosticism: no connector or product name appears anywhere under `commands/` or `skills/`. Concrete names
  are legal only in `config/recommended.json`.
- Every `references/*.md` the skill points at exists, and every reference file present is pointed at.
- The `marketplace.json` entry name matches `plugin.json`, and its `source` path resolves to a real folder.

## Why P2

The plugin is new and unreleased to users, so nothing is broken in the field today. It becomes P1 the moment
someone else edits it, because these are exactly the invariants a well-meaning edit breaks without noticing.

## Notes

The owner deferred this deliberately while the plugin was being built. Two open questions from
`plugins/interview-handoff/REQUIREMENTS.md` are still unanswered and do not block this work: whether the
plugin ships tests of its own, and whether `REQUIREMENTS.md` stays in the plugin folder.
