# Installing the harness

Short guide for a new user. It takes about five minutes.

## 1. Requirements

- Claude Code, logged in.
- `bash`, `git` and `jq` on your PATH.
- A terminal the harness can drive: iTerm2 on macOS, or `tmux`.
- The GitHub CLI `gh`, logged in, if your tickets are GitHub issues.
- The flow system you want to run, if any. The `gsd` flow needs GSD installed; the `basic` flow needs nothing more.

## 2. Install the plugin

In Claude Code:

```
/plugin marketplace add SashaMarchuk/claude-plugins
/plugin install harness@sashamarchuk-plugins
```

Restart Claude Code, then check the engine:

```
bin/harness version
bin/harness selftest
```

Run these from the plugin folder, or call `${CLAUDE_PLUGIN_ROOT}/bin/harness` from a command.

## 3. Configure a project

Open Claude Code in the project and run `/harness:config`. It recommends a flow you already use, or offers the default (the `gsd` flow with OpenSpec requirements), and asks for your autonomy profile. The default profile is `safe`: nothing leaves your machine. It writes `.harness/local.json`, which git ignores, so your choice stays on this machine.

Optional: run `/harness:ai-ready` to prepare the repository for AI development (CLAUDE.md review, AGENTS.md link, SECURITY.md, hooks). It sets up no flow system.

## 4. Add a ticket and start a run

```
/harness:add <what you want built>
bin/harness run new
```

`/harness:add` asks until the ticket is clear, then files it. `bin/harness run new` checks your confirmed config and creates a run. The command that starts the whole unattended run in terminals is not part of this pre-release yet. To stop a run, create the file `.harness/STOP` in the project. To report a problem with the harness, use `/harness:feedback`.

## Several workers at once

The worker cap is 1 by default. To run more lanes in parallel:

1. Give the run a cap: `bin/harness run new --workers 3`, or set `limits.workers` in the project config with `/harness:config`.
2. Keep heavy work (builds, test suites, browsers) to one at a time: `limits.heavy` and `limits.stages.browser` stay 1 unless your machine has room.
3. Each worker runs on its own branch in its own git worktree, and the run merges lanes one at a time through its integration branch. There is no container isolation; if two lanes collide on a shared resource (a port, a database), lower the cap and report it with `/harness:feedback`.

## Joining a project that already uses the harness

See "Joining a project that already uses the harness" in the [plugin README](../README.md#joining-a-project-that-already-uses-the-harness).
