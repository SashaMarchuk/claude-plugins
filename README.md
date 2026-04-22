# claude-plugins

Opinionated Claude Code plugins by [Sasha Marchuk](https://github.com/SashaMarchuk) — tooling for ticket management, automation, and everyday engineering workflows.

## Install this marketplace

In Claude Code:

```
/plugin marketplace add SashaMarchuk/claude-plugins
```

Then install any plugin from the list below.

## Plugins

| Plugin | What it does |
|---|---|
| [clickup](plugins/clickup) | `/clickup` skill — create and manage ClickUp tickets with enforced Connextra user stories, fuzzy list aliases, teammate auto-resolution, duplicate detection, and a two-step onboarding wizard. |
| [ultra](plugins/ultra) | `/ultra` skill — multi-agent swarm with adversarial validation, structured debates, devil's advocate, and anti-AI-slop checks. Tiers `--small` / `--medium` / `--large` / `--xl`; wraps other skills for maximum-rigor runs. |

### Install a single plugin

```
/plugin install clickup@SashaMarchuk/claude-plugins
/plugin install ultra@SashaMarchuk/claude-plugins
```

## How these plugins treat your data

All user state (config, memory, drafts) lives **outside** the plugin directory, under `~/.claude/<plugin-name>/`. Plugin updates never touch your personal data.

## Contributing / feedback

Open an [issue](https://github.com/SashaMarchuk/claude-plugins/issues) with a concrete example of what broke or what's missing. PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
