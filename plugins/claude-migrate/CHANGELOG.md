# /claude-migrate changelog

## 0.1.0 - 2026-06-02

First beta release. Universal Claude-to-Claude account migrator.

### Added
- **State machine + resume-able pipeline.** `init -> pre-split-gate -> split -> preflight -> filter-gate -> distill -> synthesize -> build-page -> verify-gate -> ready -> [pre-apply-gate -> apply -> finalize] -> done`, driven by a locked, rename(2)-atomic `state.json` and a filesystem work-queue (a unit's directory IS its state). Kill at any point and run `/claude-migrate:resume <run>`.
- **Always-on byte-exact copy page (the reliable floor).** Every run produces and verifies a self-contained `out/index.html` you can use with zero tooling, even if you never enter the browser accelerator.
- **Confirmation-gated browser automation (optional).** When a pre-authenticated browser is reachable, `apply` runs in-session and serially creates projects, seeds each chat, awaits the first turn, renames, then swaps every project to its steady-state instructions. Login is never scripted.
- **Source/sink universality.** Four shipped connectors (`sources/export-file`, `sources/browser`, `sinks/copy-page`, `sinks/browser`) as `connector.md` contracts; the universal `source`/`sink` skills execute a fixed 7-op contract each. The pipeline never branches on mode.
- **Deterministic transform.** Unit IDs follow sorted-uuid order; token estimates and the cost estimate are computed in `bin/parse-export.cjs` (never by a model); two runs over the same export produce identical briefs, payloads, and per-project artifacts.
- **/ultra gates at three boundaries.** Pre-split, verify, and pre-apply machine-gates invoke `/ultra:run`; atomic steps run no swarm.
- **PII safety net.** `users.json` is read for a hash only and never copied; live extraction strips secrets before writing; `run.log` reasons and errors are pre-redacted; a `PostToolUse`/`Write` hook is the last-resort tripwire (warns only, never blocks). Run dirs ship a `.gitignore`.
- **9 slash commands** (`init`, `run`, `resume`, `confirm`, `progress`, `verify`, `health`, `config`, `help`) over 17 skills.
- Requires the [`ultra`](https://github.com/SashaMarchuk/claude-plugins/tree/main/plugins/ultra) plugin and a local Node + Playwright runtime for byte-exact verification.

### Migration

**No reinstall required** for future updates. To update this plugin once newer releases exist:

```
claude plugin update claude-migrate@sashamarchuk-plugins
```

On Claude Code v2.1.110+, the `dependencies: ["ultra"]` field auto-resolves the `ultra` dependency, so updating `claude-migrate` alone pulls both. On older Claude Code versions, also update `ultra` explicitly:

```
claude plugin update ultra@sashamarchuk-plugins
```

**Then restart your Claude Code session** so the plugin registry refreshes.

What does NOT change across updates:
- Slash commands `/claude-migrate:init`, `/claude-migrate:run`, `/claude-migrate:resume`, `/claude-migrate:confirm`, `/claude-migrate:progress`, `/claude-migrate:verify`, `/claude-migrate:health`, `/claude-migrate:config`, `/claude-migrate:help` - same names, same args.
- Per-run state in `.planning/claude-migrate/<run-name>/` - kept verbatim across the upgrade; in-progress runs resume normally.
- Shipped connector contracts, config/selectors templates, and the copy-page DOM contract - unchanged unless a release note says otherwise.
