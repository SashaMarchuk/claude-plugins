# Contributing to claude-plugins

Thanks for being here. This is an open, MIT-licensed marketplace of Claude Code plugins, and contributions of every size are welcome: bug reports, docs fixes, new plugins, or a Windows port.

## Ways to help

- **Report a bug** — open an [issue](https://github.com/SashaMarchuk/claude-plugins/issues) with a concrete repro: what you ran, what you expected, what happened (paste the command + output).
- **Suggest an improvement** — an issue describing the use case is enough to start a conversation.
- **Fix something** — small, focused PRs are the easiest to review and merge.
- **Add a plugin** — see "Adding a new plugin" below.

## Project layout

```
.claude-plugin/marketplace.json   # the registry: one entry per plugin
plugins/<name>/                   # one self-contained plugin per directory
  .claude-plugin/plugin.json      # name, version, description, author, license, dependencies
  skills/<skill>/SKILL.md         # one skill per dir; dir name == /<plugin>:<skill>
  commands/<cmd>.md               # thin command wrappers (argument-hint + description)
  bin/ | templates/ | references/ | docs/ | hooks/   # as needed
  tests/run.sh                    # per-plugin regression harness
  README.md  CHANGELOG.md  LICENSE
tests/run-all.sh                  # runs every plugin's tests/run.sh
```

## Conventions (kept consistent across plugins)

- **Naming**: the plugin directory name, `plugin.json.name`, and the `marketplace.json` entry name must all match. Skills are invoked as `/<plugin>:<skill>`.
- **User state lives OUTSIDE the plugin** (e.g. `~/.claude/<plugin>/` or `<project>/.planning/<plugin>/`) so `/plugin update` never wipes a user's data. Reference internal plugin paths via `${CLAUDE_PLUGIN_ROOT}`.
- **SKILL.md frontmatter**: `name` + `description` are required; add `allowed-tools`, `model`, or `user-invocable: false` only when needed. Write the `description` to trigger well: lead with WHAT it does, then scope, then an explicit "Use when the user types /x ... or says '...'" list.
- **Commands** are 2-key wrappers (`argument-hint`, `description`) whose body delegates to the backing skill via the Skill tool, passing `$ARGUMENTS` verbatim.
- **Shell**: `bash`, POSIX-friendly, `set -uo pipefail`; prefer atomic writes (`mktemp` in the same dir, then `mv`) and `mkdir`-based locking.
- **Secrets / PII**: never write credentials, tokens, emails, or other PII into committed files or logs.
- **Style**: no em-dash in shipped files; keep skills domain-neutral and reusable.

## Adding a new plugin

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json` (semver; start beta at `0.x` and prefix the description with `(beta)`), a `README.md`, `CHANGELOG.md`, and `LICENSE` (MIT).
2. Add one entry to `.claude-plugin/marketplace.json` `plugins[]` (`name`, `description`, `author.name`, `source: "./plugins/<name>"`, `category`, `homepage`).
3. If it depends on another plugin here, declare it in `plugin.json.dependencies` and add a runtime preflight (see `ultra-analyzer` / `claude-migrate` for the pattern).
4. Add `plugins/<name>/tests/run.sh` and register `<name>` in the `PLUGINS=(...)` array in `tests/run-all.sh`.
5. Add a row to the root `README.md` Plugins table.

## Running tests

```
bash tests/run-all.sh                 # all plugins
bash plugins/<name>/tests/run.sh      # one plugin
```

Each runner sandboxes in a temp dir and prints a `PASS=<n> FAIL=<n>` summary; it must exit 0 with zero failures.

## Pull requests

- Branch from `main`, keep the change focused, and describe the user-facing effect.
- Bump the plugin's `version` + add a `CHANGELOG.md` entry for any registry-visible change (include a short "Migration" note if behavior changes).
- Make sure `bash tests/run-all.sh` is green.

## Platform

Tested on macOS and Linux. Windows is not yet supported (POSIX `fcntl.flock` + POSIX shell). A Windows fallback is a welcome contribution.

## License

By contributing, you agree your contributions are licensed under the repository's [MIT License](LICENSE).
