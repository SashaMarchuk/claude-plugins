# ultra-analyzer — Rigorous Pipeline Analyzer

Framework for rigorous data/corpus analysis with grounded findings, independent validation, and adversarial synthesis. Source-agnostic; domain-expert oriented (hand-authored seeds are mandatory).

## Requires

**Hard dependency:** the [`ultra`](https://github.com/SashaMarchuk/claude-plugins/tree/main/plugins/ultra) plugin from the same marketplace. `/ultra-analyzer` invokes `/ultra` at two validation gates (Gate 1 pre-discover, Gate 2 pre-synthesize); without it, runs halt at Gate 1.

On **Claude Code v2.1.110+**, installing `ultra-analyzer` from the marketplace auto-installs `ultra` via the plugin [`dependencies`](https://code.claude.com/docs/en/plugin-dependencies) field — no separate step. On **older Claude Code versions**, `dependencies` is ignored and you must install `ultra` manually (`/plugin install ultra@SashaMarchuk/claude-plugins`). Early skills (`init`, `help`) and Gate 1 (`run`) halt with a clear install command if `ultra` is not available, so the worst case is a one-shot redirect — not silent failure later in the pipeline.

Optional, per-connector:

- MongoDB runs: a MongoDB MCP server + `$MONGO_URI`.
- Browser-driven scrapes: `mcp__browsermcp__*` or `mcp__playwright-persistent__*`.
- Filesystem / JSONL / SQLite / PDF runs: no MCP needed.

## What it does

Takes a corpus (Mongo dump, filesystem tree, PDF pile, JSON/CSV, logs, web scrape) and a hand-authored `seeds.md` describing domain questions, then runs:

```
discover → analyze (parallel workers) → validate (per finding) → synthesize (with triangulation)
```

with `/ultra` swarm validation gates at **two** critical boundaries (before discover, before synthesize).

## Design principles

1. **Hand-authored seeds are mandatory.** No magic auto-generation of investigation topics. User supplies domain grounding per run.
2. **Every numeric claim must have an evidence anchor.** `[DATA:...]`, `[DOC:...]`, `[FILE:...]`, or `[HYPOTHESIS: no evidence]` — unanchored claims fail validation.
3. **Validator runs a different model than worker.** Prevents hallucination capture.
4. **Workers are crash-simple.** One unit per subprocess, no conversation history, state in files.
5. **Resume-able.** `state.json` is single source of truth. Kill at any point, run `/ultra-analyzer:resume`.
6. **/ultra only at gates.** Swarm validates config before discover and findings before synthesis. Inside atomic steps: no swarm (overkill, cost explosion).

## Install & run

**From the marketplace** (recommended):
```
/plugin marketplace add SashaMarchuk/claude-plugins
/plugin install ultra@SashaMarchuk/claude-plugins          # dependency
/plugin install ultra-analyzer@SashaMarchuk/claude-plugins
```

**Local dev**:
```bash
claude --plugin-dir ./ultra-analyzer
```

**Run an analysis**:
```
/ultra-analyzer:init my-analysis     # creates .planning/ultra-analyzer/my-analysis/

# Edit <run>/config.yaml and <run>/seeds.md (hand-authored — required), then:
/ultra-analyzer:run           # advances state; pauses at /ultra gates
/ultra-analyzer:progress      # inspect state
/ultra-analyzer:resume        # continue after interruption
```

## Directory layout

```
ultra-analyzer/
├── .claude-plugin/plugin.json
├── skills/
│   ├── init, run, progress, resume,               ← control surface
│   │   next, pause, help
│   ├── scan, explore, connector-init,             ← setup / discovery
│   │   set-profile, list-runs, health
│   ├── discover-topics, analyze-unit,             ← pipeline stages
│   │   validate-finding, synthesize-report
│   └── connector                                  ← universal source executor
├── bin/
│   ├── state.sh       ← state.json CRUD + atomic counters (mkdir lock)
│   ├── claim.sh       ← atomic topic claim
│   ├── release.sh     ← topic outcome routing (done/failed/requeue)
│   ├── requeue.sh     ← Gate-2 done→pending move with counter correction
│   ├── launch-terminal.sh  ← parallel worker launcher (profile-aware)
│   └── adapter.sh     ← dispatches to universal connector per run
├── templates/
│   ├── config.yaml.template
│   ├── seeds.md.template
│   └── connectors/    ← mongo, fs, http-api, browser, sqlite, jsonl
├── hooks/hooks.json
└── docs/              ← ARCHITECTURE, ULTRA-GATES, EXTENDING-SOURCES
```

Source of data for each run is described in that run's own `connector.md` file (generated from a template or via `/ultra-analyzer:connector-init`). Source type is NOT baked into the plugin — the universal `connector` skill interprets your run's `connector.md` at runtime.

## Per-run state (NOT inside the plugin)

The plugin is portable. Runs create state in the USER's working directory:

```
<cwd>/.planning/ultra-analyzer/<run-name>/
├── state.json              ← single source of truth
├── config.yaml             ← user-edited per run
├── seeds.md                ← hand-authored P1/P2/P3 investigation seeds
├── topics/{pending,in-progress,done,failed}/
├── findings/
├── validation/
├── synthesis/
└── checkpoints/
```

Moving the `ultra-analyzer/` folder to a new project? Zero impact on existing runs — runs live in their own project's `.planning/ultra-analyzer/`.

## Further reading

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — pipeline contract + data flow
- [ULTRA-GATES.md](docs/ULTRA-GATES.md) — where and why /ultra is invoked
- [EXTENDING-SOURCES.md](docs/EXTENDING-SOURCES.md) — write a new connector.md for a source not covered by the shipped templates
