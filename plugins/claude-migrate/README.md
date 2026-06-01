# claude-migrate - Universal Claude-to-Claude Account Migrator (beta)

Move your Claude.ai chats and projects to a new Claude account. Parse a data export (or extract live from the old account), deterministically score what is worth keeping, confirm what migrates, distill every kept chat into one paste-ready first message, then re-create projects and seed chats in the new account. A byte-exact, self-contained copy page is ALWAYS produced as the reliable floor; when a pre-authenticated browser is reachable, confirmation-gated automation also seeds and renames hands-free.

## Requires

**Hard dependency:** the [`ultra`](https://github.com/SashaMarchuk/claude-plugins/tree/main/plugins/ultra) plugin from the same marketplace. `/claude-migrate` invokes `/ultra:run` at three machine-gates (pre-split, verify, pre-apply); without it, runs halt at the first gate.

On **Claude Code v2.1.110+**, installing `claude-migrate` from the marketplace auto-installs `ultra` via the plugin [`dependencies`](https://code.claude.com/docs/en/plugin-dependencies) field - no separate step. On **older Claude Code versions**, `dependencies` is ignored and you must install `ultra` manually (`/plugin install ultra@SashaMarchuk/claude-plugins`). Early skills (`init`, `help`) and the first gate (`run`) halt with a clear install command if `ultra` is not available, so the worst case is a one-shot redirect - not silent failure later in the pipeline.

**Local runtime for byte-exact verification:**

- **Node.js** (v18+). The export parser (`bin/parse-export.cjs`) and the copy-page verifier (`bin/verify-copy-page.cjs`) are `node`-invoked scripts. `init` and `verify` halt with the verbatim message in `references/node-playwright-preflight.md` if `node` is missing.
- **Playwright** with a Chromium build. The verifier launches a headless Chromium to assert the copy page copies every card byte-for-byte. Install once with `npm i -g playwright && npx playwright install chromium` (or a project-local equivalent).

**Optional, for the browser accelerator (`output.mode == auto`):** a pre-authenticated Claude.ai browser session reachable via `mcp__playwright-persistent__*` (default), Playwright over CDP (`http://127.0.0.1:9222`), the `browsermcp` extension, or `browser-use`. The plugin NEVER scripts login - you log in once, it connects. If no browser is reachable, the run degrades to the copy page and says so.

**Install:**
```
/plugin install claude-migrate@SashaMarchuk/claude-plugins
```

## What it does

Takes a Claude.ai source (a Settings -> Privacy -> Export data ZIP, or a live read-only extraction of the old account) and runs a resume-able state machine:

```
split -> preflight (parallel) -> [you confirm] -> distill (parallel)
      -> synthesize -> build copy page -> verify -> [optional browser apply] -> done
```

- **split** - one normalized unit per chat, per-project artifacts keyed by a stable `PNN__slug`.
- **preflight** - deterministically estimates per-chat token cost and scores each chat `KEEP | REFERENCE | DROP` (parallel workers).
- **confirm** - you approve what migrates, how chats are named, the OK-protocol onboarding, optional memory migration, and the cost estimate. Nothing migrates without this gate.
- **distill** - every kept chat becomes one paste-ready first message that carries the standing requirements (parallel workers); over-long chats overflow to a project knowledge document.
- **synthesize** - for each project with at least one kept chat, two Custom-Instructions variants (migration + steady).
- **build copy page** - a self-contained `out/index.html` you can use with zero tooling. This is the dependable deliverable.
- **verify** - `/ultra` adversarial audit (brief == source, no hallucination, no leaked PII) plus a headless byte-exact copy-page check.
- **apply** (optional) - connects a pre-authenticated browser and, serially, creates projects, seeds each chat, awaits the first turn, renames, then swaps every project to its steady-state instructions.

`/ultra` swarm validation runs at **three** critical boundaries (before split, before ready, before apply).

## Design principles

1. **The copy page is the reliable floor.** A byte-exact, self-contained `out/index.html` is ALWAYS produced and verified, even if you never enter the browser accelerator. Declining automation leaves a fully working migration in hand.
2. **Confirmation-gated automation, not blind magic.** You approve what migrates, then it seeds and renames hands-free. The controller never prompts - it blocks and names the next command; the human decisions live in user-invoked gate skills.
3. **Source/sink universality.** The pipeline never branches on mode. The active source and sink are `connector.md` contracts copied into the run dir; the universal `source`/`sink` skills execute a fixed 7-op contract each. A future provider is an additive template, not a core edit.
4. **Deterministic by construction.** Unit IDs follow sorted-uuid order, token estimates are computed in the parser (never by a model), and the cost estimate is a pure function of parsed files. Two runs over the same export produce identical briefs and copy page.
5. **Resume-able.** `state.json` plus the filesystem work-queue are the single source of truth. Kill at any point and run `/claude-migrate:resume <run>`; each unit's directory location IS its state.
6. **PII never escapes.** `users.json` is read for a hash only and never copied. Live extraction strips secrets before writing. Logs and screenshots are redacted or gated. A `PostToolUse` hook is the last-resort tripwire.
7. **/ultra only at gates.** Swarm validation runs at the three machine-gates; inside atomic steps there is no swarm.

## Install & run

**From the marketplace** (recommended):
```
/plugin marketplace add SashaMarchuk/claude-plugins
/plugin install ultra@SashaMarchuk/claude-plugins              # dependency
/plugin install claude-migrate@SashaMarchuk/claude-plugins
```

**Local dev**:
```bash
claude --plugin-dir ./claude-migrate
```

**Run a migration**:
```
/claude-migrate:init my-migration     # creates .planning/claude-migrate/my-migration/
                                       # asks where your source is + how to apply

# run advances through the early steps, then BLOCKS at the filter gate:
/claude-migrate:confirm my-migration   # approve what migrates, naming, cost, etc.

# run continues to a byte-exact-verified copy page (out/index.html).
# In AUTO mode, confirm once more to launch the browser accelerator:
/claude-migrate:confirm my-migration

/claude-migrate:progress my-migration  # inspect state any time
/claude-migrate:resume my-migration    # continue after any interruption
/claude-migrate:verify my-migration    # re-run the copy-page gate on demand
```

## Directory layout

```
claude-migrate/
├── .claude-plugin/plugin.json
├── skills/
│   ├── init, run, resume, confirm,                ← control surface + gates
│   │   progress, health, config, help
│   ├── source, sink,                              ← universal 7-op executors
│   ├── extract, preflight-value, distill-brief,   ← pipeline stages
│   │   synthesize-project, build-copy-page,
│   │   apply-unit
│   └── verify                                     ← copy-page + brief audit gate
├── bin/
│   ├── state.sh             ← state.json CRUD + atomic counters (mkdir lock)
│   ├── claim.sh             ← atomic unit claim (units | seed queue)
│   ├── release.sh           ← outcome routing (done/failed/requeue), redacted log
│   ├── requeue.sh           ← gate-driven done→pending with counter correction
│   ├── launch-worker.sh     ← parallel worker launcher (preflight | distill)
│   ├── launch-seed.sh       ← in-session serial apply advisory helper
│   ├── adapter.sh           ← dispatch to universal source per run
│   ├── sink-adapter.sh      ← dispatch to universal sink per run
│   ├── browser-probe.sh     ← detect transport + auth marker
│   ├── parse-export.cjs     ← deterministic export parser (node-invoked)
│   └── verify-copy-page.cjs ← headless byte-exact copy-page verifier (node-invoked)
├── templates/
│   ├── config.yaml.template, selectors.json.template
│   ├── copy-page.html.template
│   ├── sources/   ← export-file, browser
│   ├── sinks/     ← copy-page, browser
│   └── instructions/ ← project-instructions-migration, -steady
├── references/  ← ultra-dep-preflight, node-playwright-preflight, pii-policy,
│                  login-policy, auto-title-gotcha
├── hooks/hooks.json
└── docs/        ← ARCHITECTURE, EXTENDING
```

The source and sink of each run are described in that run's own `source-connector.md` / `sink-connector.md` files (copied from a template at `init`). Source/sink type is NOT baked into the plugin - the universal `source`/`sink` skills interpret your run's connector contracts at runtime.

## Per-run state (NOT inside the plugin)

The plugin is portable. Runs create state in the USER's working directory:

```
<cwd>/.planning/claude-migrate/<run-name>/
├── state.json              ← single source of truth
├── .gitignore              ← excludes source/, seed/, apply/, *.png, run.log, state.json
├── config.yaml             ← user-edited per run (thresholds, naming, bucket labels)
├── selectors.json          ← all claude.ai UI facts for the browser sink
├── source-connector.md     ← copy of the chosen source contract
├── sink-connector.md       ← copy of the chosen sink contract
├── source/                 ← input landing (users.json is NEVER copied here)
├── units/{pending,in-progress,done,failed,dropped}/
├── value/                  ← per-chat preflight scores
├── briefs/                 ← per-chat paste-ready brief + target name
├── project/<PNN__slug>/    ← per-project instructions x2 + knowledge docs
├── seed/{pending,in-progress,done,failed}/   ← browser-sink apply queue
├── apply/                  ← apply result reports (not the resume authority)
├── out/                    ← index.html + README.md + payloads/ (the copy page)
├── validation/             ← /ultra gate + verify reports
├── checkpoints/
└── run.log                 ← JSONL; every reason/last_error pre-redacted
```

Moving the `claude-migrate/` folder to a new project? Zero impact on existing runs - runs live in their own project's `.planning/claude-migrate/`.

## Further reading

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - state machine, filesystem queues, the 7-op source / 7-op sink contracts, per-project layout, counter invariants
- [EXTENDING.md](docs/EXTENDING.md) - add a future source/sink connector without touching the core stages
- [references/pii-policy.md](references/pii-policy.md) - the canonical redaction rules and `[REDACTED:*]` regex set
- [references/login-policy.md](references/login-policy.md) - why login is never automated, and the dest != source identity guard
