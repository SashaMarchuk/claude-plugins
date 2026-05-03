# /ultra-analyzer changelog

## 0.2.0 — 2026-05-03

### Changed
- **Updated to call `ultra:launcher` instead of bare `ultra`** at Gate 1 (pre-discover) and Gate 2 (pre-synthesize). The companion `ultra` plugin renamed its backing skill in 1.4.0 to eliminate the `ultra:ultra` doubled-name registry entry; this release tracks that rename.
- Bumped minimum `ultra` plugin version to **1.4.0**. Older `ultra` versions are no longer compatible with the Gate 1 / Gate 2 invocations because they registered the launcher as `ultra:ultra`.
- Updated preflight detection in `references/ultra-dep-preflight.md` to probe for the `ultra:launcher` skill (was: `ultra`).

### Migration

**No reinstall required.** Update both plugins together:

```
/plugin update sashamarchuk-plugins/ultra@sashamarchuk-plugins
/plugin update sashamarchuk-plugins/ultra-analyzer@sashamarchuk-plugins
```

On Claude Code v2.1.110+, the `dependencies: ["ultra"]` field auto-resolves the dependency, so updating ultra-analyzer alone should pull both. On older Claude Code versions, run both updates explicitly.

What does NOT change:
- Slash commands `/ultra-analyzer:run`, `/ultra-analyzer:resume`, `/ultra-analyzer:init`, etc. — same names, same args.
- State files in `.planning/ultra-analyzer/<run-name>/` — kept verbatim across the upgrade.
- Connector specs, seed templates, validator behavior — unchanged.

If you update ultra-analyzer 0.2.0 without updating ultra to 1.4.0, Gate 1 will halt with the standard "ultra plugin not found" message because the preflight probes for `ultra:launcher` which only exists in ultra 1.4.0+.
