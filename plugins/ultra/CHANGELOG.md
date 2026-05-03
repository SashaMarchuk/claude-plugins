# /ultra changelog

## 1.4.0 — 2026-05-03

### Fixed
- **Stop LLMs emitting bare `/ultra`.** Every registry-visible description (command frontmatter, skill frontmatter, `plugin.json`, `marketplace.json`) now leads with the canonical `/ultra:run` (or `/ultra:resume`) literal instead of the bare `/ultra` token. Sibling plugins (clickup, gevent) never had this anti-pattern; this brings `/ultra` in line.
- **Eliminate the `ultra:ultra` doubled-name skill from the registry.** The backing skill's `name:` frontmatter is now `launcher`, so it registers as `ultra:launcher` instead of `ultra:ultra`. The skill was already hidden via `user-invocable: false`, but the CC v2.1.23 regression (issue #21649) was surfacing it anyway. Renaming closes the lure entirely.

### Migration

**No reinstall required.** If you have `ultra-analyzer` installed too, **update both plugins together** — ultra-analyzer 0.2.0+ requires ultra 1.4.0+ because the renamed launcher skill is the new Gate 1 / Gate 2 invocation target:

```
/plugin update sashamarchuk-plugins/ultra@sashamarchuk-plugins
/plugin update sashamarchuk-plugins/ultra-analyzer@sashamarchuk-plugins
```

On Claude Code v2.1.110+, `dependencies` resolution should pull both atomically when you update either one. On older Claude Code versions, run both updates explicitly.

What changes for users:
- `/ultra:run` and `/ultra:resume` work exactly as before — invocation, args, behavior unchanged.
- The `ultra:ultra` entry disappears from the skill registry. (It was hidden anyway; if your CC version was leaking it past `user-invocable: false`, the leak stops.)
- `ultra:launcher` appears as the new internal skill name. Not user-invocable; only the slash commands and ultra-analyzer's gates call it.

What does NOT change:
- Slash commands `/ultra:run` and `/ultra:resume` — same names, same flags.
- State files in `.planning/ultra/<task>/` — kept verbatim across the upgrade.
- Lessons file at `~/.claude/skills/ultra/global-lessons.md` — kept verbatim.
- Skill directory layout on disk — `skills/ultra/` is unchanged (only frontmatter `name:` was changed); test harness paths still resolve.

### Internal
- Skill directory `skills/ultra/` is intentionally NOT renamed. Decoupling the directory name from the registry name keeps the 34-test regression harness paths intact while still removing `ultra:ultra` from the registry.
