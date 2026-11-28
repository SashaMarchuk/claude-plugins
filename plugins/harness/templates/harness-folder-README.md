# Harness configuration

This folder holds configuration for the Harness Orchestrator, a Claude Code plugin that works through tickets unattended. It is configuration only.

**You do not need the harness to work on this project.** Nothing here runs by itself, adds a git hook or changes your build, tests or commits. To bypass the harness, just ignore this folder and work as usual.

**To use the harness here:** install the plugin (see its install guide, `docs/INSTALL.md` in the plugin), open Claude Code in this project and run `/harness:config`. It offers the configs in this folder (`config.json`, or `config.<name>.json` named for their owner) and records your choice in `local.json`, which stays on your machine and is never committed.
