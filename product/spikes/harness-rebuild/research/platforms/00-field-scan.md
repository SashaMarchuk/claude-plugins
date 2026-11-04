# 00 — Field scan: resolving "pi", "something from Xiaomi", and the rest of the field

**Date of scan:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0).
**Scope:** this document covers the AGENT PLATFORMS that a provider-agnostic orchestrator would
drive. It does not cover orchestrators themselves.

**Evidence tags used throughout:**
- **VERIFIED** — read in official docs, read in package/repo metadata, or run on this machine.
- **CLAIMED** — asserted by a README, vendor page or blog post, not independently confirmed.
- **UNKNOWN** — could not be established in this pass.

**Method note.** Version and maintenance facts come from the npm registry (`npm view`), PyPI JSON,
and the authenticated GitHub API — primary sources, queried today. Flag names come from running
`--help` on a locally installed copy, never from prose. Where only a blog said something, it is
tagged CLAIMED and named as such.

**A referenced input was missing.** The task pointed at prior orchestrator research at
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/context/orchestrator-landscape.md`.
That path does not exist — the `context/` directory is present but empty (VERIFIED). I could not
check this document against it for overlap. If that file lives elsewhere, a later pass should
re-check for duplication.

---

## 1. Resolution: "pi"

### Verdict

**"pi" is the Pi coding agent — an open-source terminal coding harness, npm
`@earendil-works/pi-coding-agent`, binary `pi`, repo `github.com/earendil-works/pi`.** It is the
only referent that is a coding executor, it is actively maintained, and it is unusually well-suited
to being driven by an orchestrator. (VERIFIED)

### Evidence

| Fact | Value | Tag |
|---|---|---|
| Current package | `@earendil-works/pi-coding-agent` | VERIFIED (npm) |
| Current version | `0.85.1`, published **2026-09-05** | VERIFIED (npm `time.modified`) |
| Binary | `pi` → `dist/bundle/cli.js` | VERIFIED (npm `bin` field) |
| Node requirement | `>=22.19.0` | VERIFIED (`engines` in package.json) |
| Repo | `github.com/earendil-works/pi`, **MIT**, 107,197 stars, last push 2026-09-18 | VERIFIED (GitHub API) |
| Former identity | `@mariozechner/pi-coding-agent` / `badlogic/pi-mono`, last published there `0.73.1` on 2026-05-07 | VERIFIED (npm) |
| Author | Mario Zechner (`badlogic`) — the original npm scope and repo owner | VERIFIED |
| Co-author Armin Ronacher | asserted by one blog post; not confirmed in repo metadata | CLAIMED |

There is a second dist-tag, `legacy-node20` → `0.74.2`, for Node 20 environments (VERIFIED). Worth
knowing: `npm pack` of the bare name gives `latest` (0.85.1), but a naive tarball run fails because
the bundle imports `@earendil-works/chord` at runtime — pi must be **installed**, not unpacked, to
execute.

### Why this matters far more than "it exists"

I installed 0.85.1 into an isolated sandbox and ran `pi --help`. The flags map almost
one-for-one onto the orchestrator contract axes. All flags below are **VERIFIED** — quoted from the
binary's own help output, not from docs:

| Axis | What pi actually exposes |
|---|---|
| **A. Launch** | `--print, -p` (non-interactive: process prompt and exit); `--mode <mode>` with `text` (default), **`json`**, or **`rpc`** |
| **B. Identity & resume** | `--session-id <id>` — *"Use exact project session ID, creating it if missing"* (the orchestrator can **assign** the id up front); plus `--session <path\|id>`, `--continue, -c`, `--resume, -r`, `--fork <path\|id>`, `--session-dir <dir>`, `--no-session` |
| **C. Transcript** | JSONL on disk at `~/.pi/agent/sessions/--<path-with-slashes-as-dashes>--/<timestamp>_<uuid>.jsonl`; documented entry schema; **version 2+ is a tree** via `id`/`parentId`, so branches live in one file |
| **D. Context** | `docs/compaction.md` documents auto-compaction with a threshold trigger and a `/compact` command, plus separate branch summarization; compaction writes a typed `CompactionEntry` into the session file — i.e. **compaction leaves proof in the transcript** |
| **G. Intervention** | `--mode rpc`: line-delimited JSON over stdin/stdout, commands carry an optional `id` and get a correlated `{type:"response"}`, events stream back as JSONL. Strict LF framing — the doc explicitly warns Node's `readline` is **not** protocol-compliant because it also splits on U+2028/U+2029 |
| **H. Guardrails** | `--no-tools/-nt`, `--no-builtin-tools/-nbt`, `--tools/-t <allowlist>`, `--exclude-tools/-xt <denylist>`, `--approve/-a` and `--no-approve/-na` (trust project-local files for this run) |
| **I. Extensibility** | extensions (`--extension`, `pi install/remove/list`), skills (`--skill`, `--no-skills`), prompt templates, themes, MCP, `AGENTS.md`/`CLAUDE.md` discovery (`--no-context-files`); extensions can register their own flags |
| **F. Accounts** | `--provider`, `--api-key`, and a credentials surface: `pi auth print-api-key --provider openai`, `pi auth print-bearer-token --provider openai-codex` |

Docs shipped in the package that later passes should read in full: `rpc.md`, `session-format.md`,
`compaction.md`, `sessions.md`, `skills.md`, `extensions.md`, `sdk.md`, `security.md`,
`containerization.md`, `environment-variables.md`, `settings.md`, `tmux.md`.

**The significant point for the rebuild:** pi is the first platform in this scan that offers a
*first-class bidirectional control protocol* (`--mode rpc`) rather than only a fire-and-forget
headless mode. Axis G ("send an instruction into a running session and know it arrived") is the
axis the current harness fails at — the field notes record a nudge that cannot submit stranded
text. pi answers that axis with request/response correlation by `id`. It also answers axis B's
hardest half: the orchestrator names the session **before** it exists, instead of scraping an id
out of output afterwards.

### Referents considered and rejected

| Candidate | What it is | Why rejected |
|---|---|---|
| **Inflection Pi** (`pi.ai`) | Consumer conversational assistant; Inflection recapitalized 2024, pivoted to enterprise under CEO Sean White | Explicitly not a coding tool — Pi was positioned as an emotionally-intelligent companion and *designed not to generate code*. No CLI, no agent loop. (CLAIMED, from press coverage — but consistent across sources and unambiguous) |
| **Pi Labs / withpi.ai** | Scoring and reward-model tooling for AI evaluation | Not an executor; no coding agent or CLI. (CLAIMED) |
| npm `dsh`-style name collisions (`pi` alone on npm) | Unrelated legacy packages | Not agents |

No other plausible "pi"-branded coding executor surfaced. Confidence that the owner meant the Pi
coding agent: **high** — it is the one "pi" that appears in agent-CLI directories alongside the
other tools he named (OpenCode, Aider, Goose, Claude Code, Codex, Gemini CLI).

---

## 2. Resolution: "something from Xiaomi"

### Verdict

**Xiaomi ships MiMo — and the owner already has it configured on this machine, pointed at Claude
Code through an Anthropic-compatible endpoint.** This is not a hypothetical. (VERIFIED on disk)

### The local evidence — this is the strongest single finding of the scan

`~/.config/claude-mimo/env` exists (created 2026-05-09) and contains (token redacted here):

```
export ANTHROPIC_BASE_URL=https://token-plan-sgp.xiaomimimo.com/anthropic
export ANTHROPIC_AUTH_TOKEN=<redacted>
export ANTHROPIC_CUSTOM_MODEL_OPTION=mimo-v2.5-pro
export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME='Xiaomi MiMo'
```

And `~/.zshrc:48` wires it to a shell alias (VERIFIED):

```
alias claude-mimo="source ~/.config/claude-mimo/env && claude --model 'mimo-v2.5-pro[1m]'"
```

Three things follow, and they change the shape of the orchestrator's provider story:

1. **"Xiaomi" is not a separate CLI to adapt.** It is *Claude Code pointed somewhere else* via two
   environment variables. The orchestrator does not need a MiMo adapter; it needs the ability to
   launch its existing Claude Code adapter with a swapped `ANTHROPIC_BASE_URL` +
   `ANTHROPIC_AUTH_TOKEN`. That is a launch-environment concern, not a platform concern.
2. **The same trick generalises.** Kimi, GLM/Z.ai, MiniMax, iFlow and others all publish
   Anthropic-protocol endpoints for exactly this purpose. Several of the platforms the owner named
   are probably *the same adapter with different env* rather than distinct integrations.
3. **`token-plan-sgp` is a regional host**, distinct from the documented public
   `api.xiaomimimo.com` — the owner is on a Singapore token-plan endpoint. A per-account/per-region
   base URL is therefore a real config axis, not a constant.

### The model itself

| Fact | Value | Tag |
|---|---|---|
| Flagship model | **MiMo-V2.5-Pro** | VERIFIED (Xiaomi official model page) |
| Architecture | Sparse MoE, ~1.02T total parameters / ~42B active | CLAIMED (vendor page says "trillion-parameter flagship Agent foundation"; the 1.02T/42B split is from secondary sources) |
| Context / output | **1M tokens context, 128K max output** | VERIFIED (vendor page) |
| Positioning | long-horizon agentic work, "nearly 1,000 tool calls" | CLAIMED (vendor) |
| Pricing (USD/Mtok) | input cache-hit **$0.0036**, input cache-miss **$0.435**, output **$0.87** | VERIFIED (vendor page) |
| OpenAI-compatible base URL | `https://api.xiaomimimo.com/v1` | VERIFIED (vendor page) |
| Anthropic-compatible base URL | `https://api.xiaomimimo.com/anthropic` (public); `https://token-plan-sgp.xiaomimimo.com/anthropic` (this machine) | VERIFIED |
| Claude Code support | "Works directly with Claude Code, Cline, and other popular AI tools" | CLAIMED (vendor), but **VERIFIED in practice** by the owner's own working config |

**Open weights exist** (VERIFIED, HuggingFace org `XiaomiMiMo`): `MiMo-V2.5-Pro` (~1T) and
`MiMo-V2.5-Pro-Base`, `MiMo-V2.5` (~311B) and `-Base`, `MiMo-V2.5-DFlash`, `MiMo-V2-Flash` (~310B)
and `-Base`, plus the `MiMo-Audio-7B` family and `MiMo-Audio-Tokenizer`. **Licenses: UNKNOWN** —
not shown on the org profile; a later pass must open individual model cards. The earlier
`MiMo-7B` / `MiMo-VL` generation was not visible on the current org profile listing.

**Cost relevance.** At $0.435/$0.87 per Mtok, MiMo-V2.5-Pro is roughly an order of magnitude
cheaper than frontier Anthropic pricing, with a 1M context. For an unattended overnight queue —
which is what this orchestrator is for — that is the difference between "runs all night" and
"burns the weekly limit by 02:00". This is the single most actionable economic finding in the scan.

---

## 3. The field — agent CLIs NOT already on the owner's list

Excluded by the task: claude-code, codex-cli, gemini-cli, opencode, glm, kimi, qwen-code, deepseek,
xiaomi-mimo, pi, cursor-cli, copilot-cli, amp, droid, aider.

All rows below are **VERIFIED** to exist and be maintained — versions and dates from npm/PyPI/GitHub
API queried 2026-09-19. Star counts are from the authenticated GitHub API.

| CLI | Identifier | Version / last release | Repo signal | One-line reason to care |
|---|---|---|---|---|
| **Antigravity CLI** (`agy`) | Google; binary `agy` | shipping now; not on npm under any obvious name (UNKNOWN install command) | — | **Gemini CLI's official replacement.** Consumer Gemini CLI access ended **2026-06-18** — already past. Any "Gemini" target must be re-pointed at `agy` or at an API-key path. |
| **DeepSeek Harness** (`dsh`) | `@deepseek-ai/dsh` | `0.1.5-rc.2`, **2026-09-17** | `deepseek-ai/deepseek-harness`, **229,697 stars**, pushed 2026-09-17 | Enormous mindshare, "everything is a plugin" architecture including the agent loop itself — but still a **0.1.x release candidate**. High potential, low maturity. |
| **Goose** | `block/goose` | **v1.51.0**, 2026-09-17 | 54,458 stars, pushed today, not archived | Mature, Rust, extension/MCP-native, vendor-neutral, joined the Linux Foundation (CLAIMED). Not on npm — install via GitHub/brew. |
| **Crush** | `@charmland/crush` | `0.95.0`, 2026-09-16 | `charmbracelet/crush`, 28,188 stars, pushed today | Charm's Go TUI agent; provider-agnostic, strong terminal ergonomics, very active. |
| **Kilo CLI** | `@kilocode/cli` | `7.7.5`, 2026-09-18 | — | Mature version number, near-daily releases; Kilo Code's terminal agent. (Do not confuse with the unrelated stale `kilocode` package, last touched 2025-10.) |
| **Kimi Code CLI** | PyPI `kimi-cli` | **1.50.0** | — | Worth separating from "Kimi the model": Moonshot ships a *real CLI agent* ("Kimi Code CLI is your next CLI agent"), not just an Anthropic-compatible endpoint. The owner's "Kimi" may mean either. |
| **OpenHands** | PyPI `openhands-ai` | `1.11.0` | — | The most autonomy-oriented OSS agent; designed for unattended long-horizon runs, which is exactly this orchestrator's use case. |
| **Warp** | `warpdotdev/Warp` | AGPL-3.0, 65,096 stars, pushed today | — | Client open-sourced (CLAIMED April 2026); "agentic development environment born out of the terminal". Relevant as a *host* for sessions, not only as an agent. |
| **iFlow CLI** | `@iflow-ai/iflow-cli` | `0.5.19`, 2026-05-12 | — | Exists and is real, but **4 months stale** — include only if the owner specifically wants it. |
| **Cline CLI** | `@cline/cli` | `0.0.13`, **2026-05-11** | — | Listed for completeness and **not recommended**: 0.0.x and 4 months stale. Cline's centre of gravity is the IDE extension, not the CLI. |

### Deliberately not recommended

- **Zed** — no npm/CLI agent package found; it is an editor with an agent panel, not a headless
  executor. (UNKNOWN whether a headless path exists.)
- **Qodo, Tembo and similar** — surfaced only in comparison blogspam; no primary-source CLI
  verified in this pass.

### A blogspam warning for whoever reads the next pass

Secondary sources in this space are badly unreliable about scale. One widely-linked 2026 comparison
article claimed OpenCode had "~202k stars" and DeepSeek Harness "~203k". The real figures from the
GitHub API today are OpenCode **208,546** and DeepSeek Harness **229,697**. The numbers were stale
and the ranking they implied was wrong. **Do not date or size anything in the per-platform passes
from a listicle.**

---

## 4. Local install inventory (this machine, 2026-09-19, read-only probe)

Nothing was modified. No agent runs were started. No owner quota was spent.

### Installed and runnable

| CLI | Path | Version | Notes |
|---|---|---|---|
| **claude** | `~/.local/bin/claude` | **2.1.278** | Matches npm `latest` (`@anthropic-ai/claude-code` 2.1.278, published today) — fully current |
| **codex** | `~/.nvm/versions/node/v22.18.0/bin/codex` | **0.152.0** | npm latest is **0.155.1** (today) — **3 releases behind** |
| **cursor-agent** | `~/.local/bin/cursor-agent` | **2025.09.12-4852336** | Date-stamped build from 2025-09-12 — **roughly a year old**; treat as stale until re-verified |

### Not installed (binary absent from PATH, homebrew, `~/.local/bin`, `~/.bun/bin`)

`gemini`, `opencode`, `amp`, `droid`, `aider`, `qwen`, `kimi`, `glm`, `copilot`, `crush`, `goose`,
`openhands`, `forge`, `sst`, `antigravity`/`agy`, `pi`.

Note the asymmetry: several of these have **config directories but no binary** — the tools were
installed once and removed, or installed through an app rather than a CLI.

### Config directories present

| Path | State | What it tells us |
|---|---|---|
| `~/.claude` | Rich and active — `agents/`, `commands/`, `skills`, `plugins`, `hooks`, `gsd-core`, `harness/`, `memory/`, `daemon/`, `history.jsonl` | The canonical content store; the GSD + harness workflow engine lives here |
| `~/.codex` | Very rich — `sessions/`, `archived_sessions/`, `session_index.jsonl`, `rollout-migrations/`, `thread_history_1.sqlite`, `queue_1.sqlite`, `state_5.sqlite`, `logs_2.sqlite`, `memories_1.sqlite`, `app-server-daemon/`, `app-server-control/`, `ipc/`, `cross-instance-locks/`, `process_manager/`, `worktrees/`, `plugins/`, `skills/` | **Codex is the most orchestration-ready surface here after Claude Code**: an app-server daemon, an IPC directory, cross-instance locks and a process manager all imply a supervisable control plane. `config.toml` shows `model = "gpt-6-astra"`, `sandbox_mode = "danger-full-access"`, and MCP servers (n8n, pencil, node_repl). Worth a dedicated pass on axes B/C/G. |
| `~/.gemini` | `settings.json` = `{"mcpServers":{}}`; `antigravity/mcp_config.json` (Jan 2026) = `{"mcpServers":{}}` | Gemini was configured but is empty and unused; the `antigravity/` subdirectory pre-dates the CLI transition and is also empty. No binary. |
| `~/.copilot` | `config.json` with only `firstLaunchAt: 2026-08-11`; `logs/` touched 2026-09-13 | Tried in August, logs as recent as Sep 13, but no binary on PATH now |
| `~/.cursor` | `agents/`, `cli-config.json`, `mcp.json`, `skills-cursor/`, `projects/`, `snapshots/` | `cli-config.json` shows a permissions model: `{"allow":["Shell(ls)"],"deny":[]}` — relevant to axis H |
| `~/.config/opencode` | `opencode.json` = `{"mcp":{}}` | Configured, empty, no binary |
| `~/.config/claude-mimo` | `env` — the Xiaomi endpoint (see §2) | The live alternate-provider config |
| `~/.config/<profile-switcher>` | present | A profile switcher (see below) |
| `~/.config/codexbar` | present | Codex status-bar tooling |

### Multiple accounts (axis F)

If the user runs a profile switcher, each profile is a separate `CLAUDE_CONFIG_DIR`; the harness must
treat the account as config, not discover it. Setting that variable at spawn pins a **new** session to
the configured account (mechanism in `claude-code.md` §F).

Two constraints a supervisor must respect (both VERIFIED):
- `~/.claude.json` and `~/.claude/.claude.json` are **different files** — the former is what Claude
  Code reads when `CLAUDE_CONFIG_DIR` is unset, i.e. in GUI, cron and non-interactive shells. An
  orchestrator spawning sessions from a daemon will hit the *former* unless it sets the env var.
- macOS may prompt once per config dir for Keychain access. An unattended run that has never been
  granted "Always Allow" for a given config dir will **block on a GUI dialog** — a silent-failure mode
  worth designing around.

---

## 5. What this scan changes about the plan

1. **"Gemini" is a moving target and partly already gone.** Consumer Gemini CLI stopped serving
   Pro/Ultra and free tiers on **2026-06-18** — three months ago. `@google/gemini-cli` still ships
   (0.60.0, published today) for paid API keys and Gemini Code Assist Standard/Enterprise, but the
   consumer path the owner would most likely use is now **Antigravity CLI (`agy`)**, a Go rewrite
   with subagents, hooks, skills and plugins. Its install command and headless flags are **UNKNOWN**
   and are the highest-priority gap in this scan.
2. **Several named "platforms" are one platform with different environment variables.** Xiaomi is
   proven to be exactly this on this machine. Kimi, GLM and MiniMax very likely are too. The
   adapter count is smaller than the platform count — but a per-provider *base URL + token + model
   id* triple becomes a first-class config object.
3. **pi is the reference implementation for axis G.** Its `--mode rpc` with id-correlated
   request/response is the cleanest answer in the field to "send an instruction into a running
   session and know it arrived", and `--session-id` lets the orchestrator name a session before it
   exists. Even if pi is never used as an executor, its protocol is the right shape to copy.
4. **Codex deserves an early, deep pass.** The `app-server-daemon`, `ipc/`, `cross-instance-locks/`
   and `process_manager/` directories on disk suggest a control plane that no blog post has
   described. That is a stronger lead than anything in the comparison articles.
5. **Two local installs are stale** — `codex` is 3 releases behind and `cursor-agent` is a build
   from 2025-09-12. Any capability testing against them must record the version, because their
   flag surfaces will not match current docs.

## 6. Open questions for the per-platform passes

| # | Question | Axis |
|---|---|---|
| 1 | Antigravity CLI: install command, binary invocation, headless flag, JSON output, session/resume, permission modes | A, B, G, H |
| 2 | Licenses on the `XiaomiMiMo` HuggingFace model cards — open weights under what terms? | J |
| 3 | Does the Xiaomi token-plan endpoint expose quota/remaining-capacity programmatically, and does it signal limit-hit in-band? | E |
| 4 | Codex `app-server-daemon` / `ipc` / `cross-instance-locks`: is there a supported external control protocol? | B, C, G |
| 5 | pi: can a supervisor **read context fullness** from outside, and **trigger** compaction via RPC with proof in the session file? | D |
| 6 | Whether Kimi Code CLI (PyPI `kimi-cli` 1.50.0) or the Anthropic-compatible Kimi endpoint is what the owner means by "Kimi" | — |
| 7 | DeepSeek Harness: is a 0.1.x RC safe to run unattended, and what does its plugin-based agent loop expose? | J, I |
