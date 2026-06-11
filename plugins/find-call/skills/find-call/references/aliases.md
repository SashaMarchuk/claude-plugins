# /find-call alias memory (v1: DISABLED)

> **Status**: v1 of the skill ships stateless. This file is the schema target for v1.1's opt-in alias learning.
> The skill reads this file during disambiguation but does NOT write to it in v1. It is plugin-local — NOT shared state.

## Schema (for v1.1)

Each entry maps a phrase the user types to a recurring meeting pattern (project name, attendee, or title fragment), plus a learned-on date.

```yaml
- phrase: "<the phrase the user types>"
  matches: "<title-substring | attendee-name | project-tag>"
  scope: "title" | "attendee" | "project"
  learned: "<YYYY-MM-DD ISO>"
  notes: "<optional context>"
```

## Examples (when v1.1 enabled)

```yaml
- phrase: "Dana calls"
  matches: "Quarterly Review"
  scope: "title"
  learned: "2026-01-15"
  notes: "Dana's Q2 review series — appears as Quarterly Review or Q2 Sync in title"

- phrase: "client bot call"
  matches: "AI Assessment Bot"
  scope: "title"
  learned: "2026-01-15"
```

## Entries

(none — v1 stateless)
