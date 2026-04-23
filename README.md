# claude-plugins

Opinionated Claude Code plugins by [Sasha Marchuk](https://github.com/SashaMarchuk) — tooling for ticket management, automation, and everyday engineering workflows.

## Quick install — get all four plugins

In Claude Code:

```
/plugin marketplace add SashaMarchuk/claude-plugins
/plugin install clickup@sashamarchuk-plugins
/plugin install create-call@sashamarchuk-plugins
/plugin install ultra@sashamarchuk-plugins
/plugin install ultra-analyzer@sashamarchuk-plugins
/reload-plugins
```

> **Marketplace name vs. GitHub source**: `SashaMarchuk/claude-plugins` (GitHub `owner/repo`) is what you pass to `marketplace add` to fetch the manifest. `sashamarchuk-plugins` is the marketplace's declared name inside `marketplace.json` — that's the suffix you use on `plugin install`. Anthropic's plugin-manifest validator rejects marketplace names that start with `claude-` or `anthropic-` (reserved for official), hence the rename.

`ultra-analyzer` declares `ultra` as a dependency, so it will pull `ultra` in automatically on Claude Code `v2.1.110+`; on older versions the fourth line fetches it explicitly. `clickup` and `create-call` are independent but share `~/.claude/shared/identity.json` for user + teammate data — onboard either one first and the other inherits the roster.

## Plugins

| Plugin | What it does |
|---|---|
| [clickup](plugins/clickup) | `/clickup` skill — create and manage ClickUp tickets with enforced Connextra user stories, fuzzy list aliases, teammate auto-resolution, duplicate detection, and a two-step onboarding wizard (identity + workspace). |
| [create-call](plugins/create-call) | `/create-call` skill — create/update/cancel Google Calendar events with Google Meet. Always attaches a configurable notes bot, conflict + past-time guards, two-step onboarding (identity + calendar defaults). Shares the teammate roster with `clickup`. |
| [ultra](plugins/ultra) | `/ultra` skill — multi-agent swarm with adversarial validation, structured debates, devil's advocate, and anti-AI-slop checks. Tiers `--small` / `--medium` / `--large` / `--xl`; wraps other skills for maximum-rigor runs. |
| [ultra-analyzer](plugins/ultra-analyzer) *(beta)* | `/ultra-analyzer` skill set — rigorous data/corpus pipeline (discover → analyze → validate → synthesize) with resume-able state and `/ultra` gates at critical boundaries. Source-agnostic: MongoDB, filesystem, PDF, web scrapes, JSON/CSV, SQLite. **Requires the `ultra` plugin.** |

### Install a single plugin

Assuming `/plugin marketplace add SashaMarchuk/claude-plugins` was already run:

```
/plugin install clickup@sashamarchuk-plugins
/plugin install create-call@sashamarchuk-plugins
/plugin install ultra@sashamarchuk-plugins
/plugin install ultra-analyzer@sashamarchuk-plugins   # requires ultra
/reload-plugins
```

## Your data is preserved across updates

All user state lives **outside** the plugin directory by design, so `/plugin update` never wipes what you've collected:

| Location | Contents | Used by |
|---|---|---|
| `~/.claude/shared/identity.json` | User profile + teammate roster (name, email, `external_ids`, `active`, `last_validated_at`) — single source of truth for "who is on the team" | `clickup`, `create-call` |
| `~/.claude/clickup/{config.json, memory.md, drafts/}` | Workspace + lists + aliases + learned memory rules + idempotency drafts | `clickup` |
| `~/.claude/create-call/config.json` | Calendar defaults + always-include attendees (notes bot) + behavior flags | `create-call` |
| `~/.claude/skills/ultra/global-lessons.md` | Per-run lessons log | `ultra` |
| `<your-project>/.planning/ultra-analyzer/<run-name>/` | Config, seeds, findings, state per analyzer run | `ultra-analyzer` |

All JSON writes are atomic (`tmp + fsync + os.replace`) under `fcntl.flock` on a sentinel file, and readers preserve unknown keys — so `clickup` and `create-call` can evolve independently without stepping on each other's fields in `identity.json`.

This preservation guarantee was verified empirically — a sandboxed `rm -rf + recopy` of the plugin dir (simulating a worst-case update) left every pre-seeded user file intact.

### Migrating from the legacy user-level `create-call` skill

**Important**: if you previously installed `create-call` as a user-level skill at `~/.claude/skills/create-call/`, that legacy skill **wins over the plugin** by Claude Code precedence. Install + legacy coexistence does NOT do what you want — Claude will keep loading the legacy skill until you remove it.

Migration steps:

1. Back up your legacy contacts (optional): `cp ~/.claude/skills/create-call/contacts.json /tmp/create-call-contacts.bak.json`
2. Remove the legacy skill: `rm -rf ~/.claude/skills/create-call`
3. Install the plugin: `/plugin install create-call@sashamarchuk-plugins` (after `marketplace add SashaMarchuk/claude-plugins`)
4. Run onboarding: `/create-call --onboard`
5. The identity wizard offers (as a one-time prompt on first run if it detects a leftover legacy contacts file anywhere in common backup locations) to import your `contacts.json` entries as a thin seed into `~/.claude/shared/identity.json`.

The plugin will emit a loud banner on every invocation as long as `~/.claude/skills/create-call/` still exists, so it's hard to miss.

### Platform support

All plugins are tested on **macOS** and **Linux**. Windows is not currently supported — the shared-identity helper uses `fcntl.flock` for cross-process locking, which is POSIX-only. A Windows fallback (`msvcrt.locking`) would be a welcome PR.

### Troubleshooting install

**"Plugin `<name>` not found in any marketplace"** — the marketplace was added but you're using the wrong identifier after `@`. Inside `marketplace.json` the declared name is `sashamarchuk-plugins`. Use that:
```
/plugin install create-call@sashamarchuk-plugins
```
Not `@SashaMarchuk/claude-plugins` (that's the GitHub source, which `marketplace add` takes).

**"Failed to parse marketplace file... impersonates an official Anthropic/Claude marketplace"** — you're on an older clone from before 2026-04-23. Pull latest: the marketplace `name` field has been renamed from `claude-plugins` to `sashamarchuk-plugins`. Re-add: `/plugin marketplace remove SashaMarchuk-claude-plugins` then `/plugin marketplace add SashaMarchuk/claude-plugins`.

**After install, plugins don't show up** — run `/reload-plugins`. Claude Code caches the skill list until reload.

## Contributing / feedback

Open an [issue](https://github.com/SashaMarchuk/claude-plugins/issues) with a concrete example of what broke or what's missing. PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
