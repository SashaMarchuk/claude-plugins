# "deepseek harness" — identity resolution

**Stage:** identify only. No adoption verdict here.
**Date of research:** 2026-09-19. Every star count, version and date below is as of that day.
**Method:** GitHub REST/GraphQL via `gh`, the npm registry, the repository's own source and docs, the
official product page. Web write-ups used only where a primary source could not answer, and tagged.

---

## Bottom line

The owner's "deepseek harness" resolves to exactly one thing, and the name is not ambiguous in
practice: **`deepseek-ai/deepseek-harness`** — command name `dsh`, "DeepSeek Harness: Everything is a
Plugin." It is a **first-party DeepSeek AI** open-source agent harness, MIT, TypeScript, published
**2026-08-13**, at **229,696 stars** five weeks later. All four hypotheses in the brief collapse onto
this one artifact (see [Disambiguation](#disambiguation)).

**Candidate for the next stage: `deepseek-ai/deepseek-harness` (DSH core).** Nothing else is close.

**The caveat the next stage must carry in from here.** DSH is a *harness*, and it sits at the same
layer as Claude Code — one agent runtime driving one session's model calls, tools, sandbox and UI. It
is **not** an orchestrator above engines, which is the layer the owner is rebuilding. DSH's
orchestration surface (`jobs`, `schedule`, `goal`, `workflow`, `subagent`, `agent-team`) is
**in-session and session-local by its own documentation**. The cross-session, queue-of-work,
runs-for-hours-unattended layer exists only in community plugins, and those are days old and in the
**2–96 star** range. So the real question for stage two is not "is DSH better than my orchestrator" —
they are not the same product — but "**is DSH the right substrate to build my orchestrator on, and
which of its mechanisms should I borrow?**"

---

## Blocker to flag

The brief points at a prior survey:

```
/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/context/orchestrator-landscape.md
```

**That file does not exist.** The `context/` directory exists and is empty (created 2026-09-18), and a
filesystem-wide search for `orchestrator-landscape.md` returns nothing. I could therefore **not** make
this verdict comparative against Agent Orchestrator, Gas Town, Sortie, Symphony, Claudexor, ralphex or
Bernstein, as instructed. Everything below is absolute, not relative. The comparison must be redone
once the survey is restored or regenerated.

---

## Candidates found

### Tier 1 — the actual referent

| Repo | Stars | Owner | License | Created | Status |
|---|---:|---|---|---|---|
| **`deepseek-ai/deepseek-harness`** | **229,696** | DeepSeek AI (first-party) | MIT | 2026-08-13 | `v0.1.6-alpha.2`, developer preview |

### Tier 2 — ecosystem that shares the name but is not the thing

These matched the search because the name is in their description. None is a harness; all are
downstream of Tier 1. Listed so a future search does not re-litigate them.

| Repo | Stars | What it is |
|---|---:|---|
| `nexu-io/open-design` | 97,020 | Design plugin; supports DSH among 20+ CLIs. Predates DSH (created 2026-04-28). |
| `awesome-dsh-plugin/awesome-dsh-plugin` | 16,251 | Curated plugin list |
| `dataelement/dsh-desktop` | 7,606 | Desktop wrapper |
| `zhu1090093659/dsh-web` | 7,777 | Plugin aggregation web ecosystem |
| `dsh-tauri/deepseek-harness-desktop` | 2,310 | Tauri desktop wrapper |
| `Small-tailqwq/dsh-deep-whale` | 2,143 | UI skins |
| `alchaincyf/deepseek-harness-orange-book` | 1,296 | Third-party book |
| `0xsline/awesome-deepseek-harness` | 1,080 | Ecosystem list |
| + ~20 more | — | Awesome-lists, desktop/mobile clients, tutorials, books, a quant trading system |

**Ecosystem scale (VERIFIED):** 15,435 public repositories carry the `dsh-plugin` topic.

### Tier 3 — the orchestration plugins, i.e. the layer the owner actually wants

This is the important finding in this tier: **the orchestration layer over DSH is real but embryonic.**

| Repo | Stars | License | What it claims |
|---|---:|---|---|
| `NanmiCoder/dsh-agent-teams` | 1,728 | MIT | AgentTeams plugin |
| `Astro-Han/pawwork` | 192 | Apache-2.0 | Desktop agent built on DSH |
| `xuanyuanzhifeng/dsh-plugin-agent-workflow` | 163 | MIT | Agent workflow |
| `titanwings/dsh-automation` | 96 | MIT | Coding tasks on a schedule **in fresh Agent Sessions** |
| `MichengAI/dsh-automation` | 19 | Apache-2.0 | Scheduled tasks in isolated DSH sessions |
| `LouisHaoL/dsh-timer-agent` | 13 | MIT | Host-resident scheduled jobs × agent engine |
| `zibo2025/dsh-orchestrator` | 6 | — | Multi-agent orchestration, per-worker model + thinking effort |
| `Saktawdi/dsh-ha-orchestrator` | 6 | — | Model HA fallback + 5 subagent modes (fanout/pipeline/supervisor/map-reduce/router) |
| `jiruidai/dsh-meta-orchestrator` | 5 | MIT | Model-native meta-agent synthesising workflows at runtime |
| `squirrel20/dsh-cron`, `cofy-x/dsh-cron` | 4, 4 | MIT | Unattended cron jobs, agent or command kind |
| `zhangz-2018/dsh-project-orchestrator` | 4 | — | Approval-gated planning, git worktrees, Issues, audit evidence |
| `linkbag/dsh-swarm-orchestrator` | 3 | — | Per-role model pinning w/ fallbacks, task DAG, review loops |
| `softspark/dsh-orchestrator` | 3 | — | **One-shot Claude Code and Copilot/Gemini delegation via native subscription logins** |
| `rocker2018-droid/dsh-longtask-orchestrator` | 2 | — | Long-task orchestration |

Note `Saktawdi/dsh-ha-orchestrator` (provider fallback), `linkbag/dsh-swarm-orchestrator` (per-role
model pinning), `zhangz-2018/dsh-project-orchestrator` (approval gates + worktrees + Issues) and
`softspark/dsh-orchestrator` (delegating out to Claude Code on a subscription login) — between them
these four sketch roughly half the owner's job list. Each is a single-author repo with single-digit
stars and days of history. **They are a signal that the need is widely felt, not a product to adopt.**

---

## Disambiguation

The brief listed four hypotheses. Resolution:

1. **An agent/orchestration harness published by DeepSeek itself** — **YES, this is it.** VERIFIED:
   `deepseek-ai/deepseek-harness`, README states "an open-source agent harness developed by DeepSeek
   AI", citation block `@misc{deepseek-harness2026, author={DeepSeek-AI}}`.
2. **A community harness for running DeepSeek models as coding agents** — **no such thing under this
   name.** VERIFIED: every repo matching "deepseek harness" created before 2026-08-13 is either a
   pre-existing tool that later added DSH support (`nexu-io/open-design` 2026-04-28,
   `Nagi-ovo/voyager` 2025-10-04, `zhukunpenglinyutong/desktop-cc-gui` 2026-02-03) or an ecosystem
   repo created 2–3 days ahead of launch (2026-08-11/12). No prior unrelated claimant to the name.
3. **DeepSeek's own agent/terminal tooling shipped with a model release** — **same artifact.**
   CLAIMED (secondary sources, consistent across several): DSH went MIT-public on 2026-08-13, the same
   day DeepSeek made **DeepSeek-V4-Pro-0813** generally available. Model and harness shipped together.
   VERIFIED in-repo: the DeepSeek-specific route is `dsh-llm-deepseek` serving `deepseek-official`.
4. **An evaluation harness of that name** — **same artifact, in a mode.** VERIFIED: the repo's
   `BENCHMARK.md` documents running benchmarks *through* DSH — the Python SDK's `jsonrpc-agent`
   **minimal** variant, separate workspaces and session IDs per task. CLAIMED (secondary): DeepSeek's
   own published Terminal-Bench 2.1 number for V4-Pro (87.9) was measured on this harness. So "the
   DeepSeek harness" in an eval context means DSH minimal mode, not a separate project.

**Conclusion: one name, one artifact, no collision.** Unusual for an agent tool, and it means the
owner's note carries no hidden ambiguity.

---

## The chosen candidate — evidence

### Identity · VERIFIED

- **Repo:** `github.com/deepseek-ai/deepseek-harness`, default branch `master`, id 1333065091
- **Homepage:** `https://deepseek.com/harness` · **Docs:** `deepseek-harness.github.io/deepseek-harness/`
- **npm:** `@deepseek-ai/dsh` — "dsh CLI: profile boot, plugin management, and the browser UI alias"
- **Entry point:** `npx @deepseek-ai/dsh web` → Web UI on `127.0.0.1:3080`, opens a browser. Also runs
  from source via pnpm. **Note: the advertised front door is a local web server, not a TTY.**
- **License:** MIT (repo and npm package), third-party notices disclosed separately
- **Language:** TypeScript, 206 MB checkout, pnpm workspace, ~55 package groups
- **Topics:** `ai-agents`, `cordis`, `dsh`, `dsh-plugin`

### What it claims to be · VERIFIED (own README and product page)

> "DeepSeek Harness (`dsh`) is an open-source agent harness developed by DeepSeek AI. It is built on an
> **everything-is-a-plugin** architecture and powered by [Cordis]…"

Cordis is a third-party micro-kernel/plugin meta-framework (`cordiverse/cordis`), whose design the
README attributes to *A Programming Paradigm for Spatiotemporal Composability* (arXiv 2608.25512).
The product page states every capability is a plugin — "models, tools, skills, sessions, sandboxes,
storage, loops, scheduling, and the UI" — selectable, swappable or extensible **in configuration,
without changing DSH source**. Runtime modes named: Standard, Code, Minimal, Creator.

### Maturity and status · VERIFIED

- **Version:** npm `latest` = **0.1.5-rc.2**; `alpha` = **0.1.6-alpha.2** (2026-09-17). Never reached 1.0.
- **Self-declared:** "DeepSeek Harness is in *developer preview* and iterating rapidly. **THERE WILL BE
  COMPATIBILITY-BREAKING CHANGES.**"
- **`SAFETY.md`:** "experimental developer-preview software. It has not undergone a security audit and
  must not be treated as secure or production-ready." Recommends a disposable VM or container, and
  states plainly that "Sandboxing, approval prompts, and permission controls can reduce risk, but they
  do not guarantee isolation."
- **22 npm versions in 5 weeks**, every one a pre-release.

### Activity · VERIFIED

| Signal | Value |
|---|---|
| Stars | 229,696 (from 0 on 2026-08-13; ~155k by day 5 per secondary report) |
| Forks | 27,488 |
| Watchers | 986 |
| Contributors | 36 |
| Commits/week, last 6 weeks | 3762, 1725, 2000, 982, 1218, 783, 1640, 829 |
| PRs merged | ≥ 4,471 (highest observed PR number, 2026-09-17) |
| Discussions | 7,040 |
| npm downloads, week of 2026-09-12 | 344,017 |
| Last push | 2026-09-17 |

Top contributors: `tianyicui` (6,218), `LegGasai` (2,257), `imccyu` (1,836), `Chinesezjc` (1,032),
`kermanx` (948), `CreatixChu` (912). Several are recognisable names from the TypeScript/Vue OSS world
(`kermanx`, `07akioni`, `Kingwl`), i.e. a funded, full-time team, not a side project.

### Governance — the material risk · VERIFIED

This is the finding most likely to change an adoption decision, and it is easy to miss:

- **GitHub Issues are disabled** (`has_issues: false`). Bug reports go to Discussions only.
- **The REST `pulls` endpoint 404s and `gh pr list` returns empty** — the public repo exposes no PR
  history via API, though merge commits reference PR numbers up to #4471.
- Merge commits name head branches under a **separate `deepseek-harness` GitHub org** (created
  2026-05-26, **0 public repos**), and the tree contains a **`.gitlab-ci.yml`**. Git history begins
  2026-08-13, the public launch date.
- `CONTRIBUTING.md` states it outright: *"We are sorry that we cannot accept external pull requests at
  the moment."* And: *"You may consider this repository an idea, an official showcase, and a source of
  inspiration, but not a mandate from us."*

**Read: this is a one-way mirror of a private internal repository.** You cannot file an issue, you
cannot upstream a fix, you cannot see the PR that broke you, and the history you can read is five weeks
old. Your only supported lever is writing a plugin. For software the owner intends to leave running
unattended overnight, that is the single most important fact on this page.

---

## Why this candidate, and what stage two is walking into

A surface capability map only — **not** an evaluation. Taken from package names, subsystem docs and
package READMEs in the repo. Mapped against the owner's 11 jobs so stage two knows where to dig.

| # | Owner's job | DSH surface | Tag |
|---|---|---|---|
| 1 | Unattended queue for hours, clean stop, kills only its own | `packages/jobs` — "Background Job Runtime", `JobStatus: running/stopping/completed/killed/failed`, job kinds `bash` and `subagent`, owner-authorized access. `packages/deliverables`. **But job kinds are in-session producers.** | VERIFIED surface, fit UNKNOWN |
| 2 | Does not own the process; runs GSD/superpowers/custom; must not forbid subagents | `packages/subagent`, `packages/skill`, `packages/preset`, `packages/plan`. Subagents are first-class, so the *anti*-requirement is met. **But DSH brings its own agent loop and its own process** — it is a peer of Claude Code, not a driver of it. Running GSD inside DSH means re-expressing GSD as DSH plugins. | Tension — stage two's central question |
| 3 | Work from local registry or GitHub Issues/ClickUp; statuses, comments, mid-run pickup | Nothing in core. `packages/todo` is session-local. Only `zhangz-2018/dsh-project-orchestrator` (4★) claims Issues integration. | **Gap** |
| 4 | Per-provider subscription quota watch, thresholds, hard/soft/save-resume, wait for reset | `packages/llm/token-meter` measures *context/request pressure from the durable session log* — **that is context accounting, not subscription quota**. `llm-retry` retries at durable step boundaries. A "budget doc" commit landed 2026-09-17. | Partial; **quota ≠ tokens**, verify |
| 5 | Several platforms and accounts, per role, switchable mid-run, verified before a run | **Strongest fit.** `llm-pi-ai` routes to "multiple pi-ai providers, OpenAI-compatible gateways, or self-hosted servers from one configuration"; per-route profiles and credentials; OAuth or interactive key with cross-process refresh locking; and — directly matching "switchable mid-run" — *"settings changes take effect on the next request without a restart."* `agent-team` snapshots carry a per-teammate `provider`. `packages/credentials`, `packages/identity`. | VERIFIED surface, **borrow candidate** |
| 6 | Watch context window, compact or hand off at a threshold, guaranteed to happen | `packages/compaction` + `token-meter` (`totalTokens`, `surfaceDeltaTokens`, `logRevision` — measured off the durable event log, i.e. replayable and auditable). **This is precisely what FIELD-NOTES records the current harness cannot do.** | VERIFIED surface, **strongest borrow candidate** |
| 7 | Survives its own death: health check, provider fallback, launch journal, never two orchestrators | Event-sourced durable session log throughout; `session-query`, `spill`, `storage`, `runtime-diagnostics`. Provider fallback only in a 6★ community plugin. Single-orchestrator mutual exclusion: nothing found. | Partial |
| 8 | Interactive terminals or headless per platform; orchestrator answers a session's question | `packages/terminal`, `shell`, `subprocess`, `ssh`, `sandbox`, `acp`, `apps/cli`, `apps/web`, `apps/desktop`. Subsystem doc `user-questions.md` exists — a modelled question channel. | VERIFIED surface, **borrow candidate** |
| 9 | Config at global/project/run scope, changed DURING a run, next-tick pickup; manual stops | `packages/settings`, `docs/config-catalog.md`, `scope.md`; hot settings confirmed for provider routes (see #5). | Partial |
| 10 | Silent unless asked; status via separate command; verified notification channel | `packages/webhook`, `packages/feedback`, `session-telemetry.md`. **But the default front door opens a browser UI** — the opposite of "prints nothing". | Tension |
| 11 | Never touches other projects; one text file of prohibitions every agent reads | `packages/workspace`, `docs/subsystems/scope.md`, `approval.md`, `permission-presets.md`, `sandbox`. **`packages/guard` is a red herring** — it contains only `repeat-tool-reminder` and `timeout-policy`. No prohibitions-file concept found. | Partial |

**Two mechanisms are worth stage-two attention regardless of any adopt/reject verdict:**

1. **`token-meter` + `compaction`** — context pressure computed from a durable event log at a known
   `logRevision`, so the measurement is replayable rather than guessed. FIELD-NOTES records that
   nothing in the current harness measures a session's context window at all. This is the closest
   thing found to a solved version of job #6.
2. **`llm-pi-ai`'s route model** — named provider routes, per-route credentials and profiles, resolved
   per request, changes live without restart. That is job #5's "switchable mid-run through one watched
   file" already built, and it is ~1 package, not an architecture.

Also worth a look for its own sake: `packages/workflow` ships **`dsh-tool-ralph`** as an opt-in
consumer — DeepSeek shipped a first-party Ralph-loop tool. The workflow seam runs a *model-written*
orchestration script that spawns subagents, with `meta`/`args` as validated plain JSON that is never
`eval`'d, and a `maxTotalAgents` ceiling the script cannot observe or raise. That containment design is
a clean answer to a problem the owner's harness has too.

---

## What stage two must resolve

1. **Layer.** Is DSH a *replacement* for the orchestrator, a *substrate* to build it on, or a *donor of
   mechanisms*? The evidence here points hard at the third, possibly the second, not the first.
2. **Cross-session.** `schedule` is documented as *"Session-local Schedule"* and `goal` as
   *"Same-session goals"*; `agent-team` is in `packages/experimental`. Find out whether a queue of work
   can outlive one session **without** a community plugin, and whether it survives a host restart.
3. **Quota vs tokens.** Confirm whether anything in DSH reads a *subscription* quota (job #4) or only
   token pressure (job #6). These are different problems and the names invite conflation.
4. **Foreign engines.** Can DSH drive an external agent CLI — Claude Code, Codex — as an executor, or
   must every step run on DSH's own loop? `softspark/dsh-orchestrator` (3★) claims the former via
   native subscription logins; if that works, it changes the verdict.
5. **Governance.** Decide explicitly whether a no-issues, no-external-PRs, alpha, unaudited mirror of a
   private repo is acceptable under something that runs unattended overnight. This is a judgement call
   for the owner, not a research finding.
6. **Restore the landscape survey** and redo the comparison. Without it, "better than the best of
   those" has not been tested.

---

## Sources

Primary (all read directly, 2026-09-19):

- `github.com/deepseek-ai/deepseek-harness` — REST metadata, README.md, CONTRIBUTING.md, SAFETY.md,
  BENCHMARK.md, root tree, `packages/` and `apps/` and `docs/` listings, `docs/subsystems/{jobs,
  schedule, workflow, token-meter, agent-team, goal}.md`, `packages/llm/README.md`,
  `packages/llm/llm-pi-ai/README.md`, `packages/guard/` listing
- GitHub REST/GraphQL: releases, tags, contributors, commit stats, discussions count, `dsh-plugin`
  topic count, `orgs/deepseek-harness`
- npm registry: `@deepseek-ai/dsh` manifest + download counts
- `https://deepseek.com/harness/en/` — official product page

Secondary (used only for the model/launch relationship, tagged CLAIMED above):

- [InfoQ — The Open-Sourcing of DeepSeek Harness](https://www.infoq.com/news/2026/08/deep-seek-harness/) (fetch returned HTTP 405; only the search-result summary was available)
- [VentureBeat — DeepSeek Harness launches as open source rival to Claude Code, alongside V4-Pro](https://venturebeat.com/technology/deepseek-harness-launches-as-open-source-rival-to-claude-code-alongside-v4-pro-on-api-with-higher-prices)
- [Pandaily — DeepSeek Open-Sources Harness Agent Runtime](https://pandaily.com/deepseek-harness-open-source-agent-framework)
- [DataNorth — DeepSeek releases V4-Pro-0813 and Harness v0.1](https://datanorth.ai/news/deepseek-releases-v4-pro-0813-and-harness-v0-1)
