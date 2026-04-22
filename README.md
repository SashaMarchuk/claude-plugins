# claude-plugins

Opinionated Claude Code plugins by [Sasha Marchuk](https://github.com/SashaMarchuk) — tooling for ticket management, automation, and everyday engineering workflows.

## Quick install — get all three plugins

In Claude Code:

```
/plugin marketplace add SashaMarchuk/claude-plugins
/plugin install clickup@SashaMarchuk/claude-plugins
/plugin install ultra@SashaMarchuk/claude-plugins
/plugin install ultra-analyzer@SashaMarchuk/claude-plugins
```

That's it — three paste-and-enters. `ultra-analyzer` declares `ultra` as a dependency, so it will pull `ultra` in automatically on Claude Code `v2.1.110+`; on older versions the third line fetches it explicitly.

## Plugins

| Plugin | What it does |
|---|---|
| [clickup](plugins/clickup) | `/clickup` skill — create and manage ClickUp tickets with enforced Connextra user stories, fuzzy list aliases, teammate auto-resolution, duplicate detection, and a two-step onboarding wizard. |
| [ultra](plugins/ultra) | `/ultra` skill — multi-agent swarm with adversarial validation, structured debates, devil's advocate, and anti-AI-slop checks. Tiers `--small` / `--medium` / `--large` / `--xl`; wraps other skills for maximum-rigor runs. |
| [ultra-analyzer](plugins/ultra-analyzer) *(beta)* | `/ultra-analyzer` skill set — rigorous data/corpus pipeline (discover → analyze → validate → synthesize) with resume-able state and `/ultra` gates at critical boundaries. Source-agnostic: MongoDB, filesystem, PDF, web scrapes, JSON/CSV, SQLite. **Requires the `ultra` plugin.** |

### Install a single plugin

```
/plugin install clickup@SashaMarchuk/claude-plugins
/plugin install ultra@SashaMarchuk/claude-plugins
/plugin install ultra-analyzer@SashaMarchuk/claude-plugins   # requires ultra
```

## Your data is preserved across updates

All user state lives **outside** the plugin directory by design, so `/plugin update` never wipes what you've collected:

| Plugin | User-data location |
|---|---|
| `clickup` | `~/.claude/clickup/{config.json, memory.md, drafts/}` — onboarding + learned patterns |
| `ultra` | `~/.claude/skills/ultra/global-lessons.md` — per-run lessons log |
| `ultra-analyzer` | `<your-project>/.planning/ultra-analyzer/<run-name>/` — config, seeds, findings, state per run |

This was verified empirically — a sandboxed `rm -rf + recopy` of the plugin dir (simulating a worst-case update) left every pre-seeded user file intact.

## Contributing / feedback

Open an [issue](https://github.com/SashaMarchuk/claude-plugins/issues) with a concrete example of what broke or what's missing. PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
