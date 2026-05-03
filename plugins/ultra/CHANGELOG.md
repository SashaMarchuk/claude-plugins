# /ultra changelog

## 1.4.1 — 2026-05-03 (hotfix)

### Reverted
- **Skill rename `ultra:ultra` → `ultra:launcher` is reverted.** The combination
  of `name: launcher` (frontmatter) + `user-invocable: false` + directory name
  `skills/ultra/` (mismatch with frontmatter) caused Claude Code v2.1.126 to
  silently fail registration of the backing skill. `Skill: ultra:launcher` was
  returning "Unknown skill", which broke `/ultra:run`, `/ultra:resume`, and
  ultra-analyzer's Gate 1 / Gate 2 invocations end-to-end.
- The backing skill is back to `name: ultra` (registers as `ultra:ultra` per
  the directory). The doubled-name registry entry returns, but its description
  was rewritten in 1.4.0 to lead with `/ultra:run` literal — TIER-1 description
  fixes (the dominant cause of the bare-`/ultra` LLM-emission bug) are KEPT.
- ultra-analyzer 0.2.1 reverts its Gate 1 / Gate 2 invocations and preflight
  detection back to the `ultra` skill name.

### Migration
**No reinstall required.** Run:
```
claude plugin update ultra@sashamarchuk-plugins
claude plugin update ultra-analyzer@sashamarchuk-plugins
```
**Then restart your Claude Code session** (`/exit` and relaunch) so the plugin
registry refreshes from disk.

### Follow-up
A proper TIER-2 cleanup (rename both directory `skills/ultra/` → `skills/launcher/`
AND frontmatter `name:` to match) is tracked as future work. Will be done in
a separate PR with the test harness path updates and CC v2.1.x registration
semantics nailed down.

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
