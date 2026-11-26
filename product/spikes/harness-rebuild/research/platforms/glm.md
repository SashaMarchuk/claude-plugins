# Z.ai GLM (GLM Coding Plan) — platform profile

**Date of research:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0).
**Companion documents:** `00-field-scan.md` (resolves the field), `claude-code.md` (the profile this
one leans on most heavily). Read `claude-code.md` first — most of GLM's axis answers *are* Claude
Code's answers, and this document deliberately does not restate them.

**Evidence tags:** **VERIFIED** — read in official source on disk, read in official docs, or run on
this machine today. **CLAIMED** — asserted by a vendor page, README or third party, not
independently confirmed. **UNKNOWN** — could not be established in this pass.

**Not installed here.** `which glm zai` → nothing. No `~/.zai`, `~/.glm`, `~/.config/zai`,
`~/.chelper`, `~/.zcode`. No `z.ai` / `bigmodel` / `GLM` string anywhere in `~/.zshrc`, `~/.zshenv`,
`~/.zprofile`, `~/.bashrc`, `~/.bash_profile`. (VERIFIED, read-only probe.) The owner has the
**Xiaomi MiMo** equivalent wired up (`~/.config/claude-mimo/env`) but **no Z.ai credential on this
machine**. Everything below that required a live GLM key is therefore tagged accordingly; everything
that could be established from official source code, official docs, or unauthenticated endpoint
probes was.

---

## 0. The one sentence that reframes this platform

**GLM is not a CLI and it is not a session. It is a credential triple** — `base URL` + `API key` +
`model id` — **plus one genuinely excellent quota endpoint.** Every orchestrator axis except **E
(quota)** and parts of **D (context)** and **F (accounts)** is answered by *whichever CLI you point
at it*, not by Z.ai.

This is the same shape the field scan found for Xiaomi MiMo, and it is the most important structural
fact in this profile: **the orchestrator does not need a GLM adapter. It needs a
`{base_url, token, model, context_window}` object and the ability to launch an existing adapter with
that environment.**

### The drivers Z.ai officially supports

From `https://docs.z.ai/devpack/tool/others`, the official supported-tool list (VERIFIED, read
today): **ZCode, Claude Code, Claude for IDE, Codex, OpenCode, Pi, Cursor, Cline, TRAE, Qoder,
Droid, Kilo Code, Roo Code, Crush, Goose, Eigent**, plus AutoClaw, OpenClaw, Hermes Agent,
SillyTavern.

Two entries on that list matter disproportionately to this rebuild:

- **Pi is officially supported.** The field scan named pi as the reference implementation for axis G
  (`--mode rpc`, id-correlated request/response) and axis B (`--session-id` names a session before it
  exists). Z.ai supports it directly — `ZAI_API_KEY`, `/login zai`, credentials land in
  `~/.pi/agent/auth.json` (VERIFIED, `docs.z.ai/devpack/tool/pi`). **pi + GLM is the only combination
  in the field that gives the orchestrator bidirectional in-session control *and* a real quota
  endpoint at the same time.** See §G.
- **Codex is officially supported**, via the OpenAI **Responses** wire protocol, not chat-completions
  (VERIFIED from the official helper's source — see §A.3).

### The three protocol surfaces

All VERIFIED from `docs.z.ai/devpack/quick-start` and confirmed by unauthenticated probe from this
machine today:

| Protocol | Base URL (global) | Base URL (China) |
|---|---|---|
| Anthropic Messages | `https://api.z.ai/api/anthropic` | `https://open.bigmodel.cn/api/anthropic` |
| OpenAI Chat Completions | `https://api.z.ai/api/coding/paas/v4` | `https://open.bigmodel.cn/api/coding/paas/v4` |
| OpenAI Responses | `https://api.z.ai/api/v1` | `https://open.bigmodel.cn/api/v1` |

A third host, `https://dev.bigmodel.cn`, is recognised by the community quota plugin but is not in
the docs (VERIFIED in that plugin's source; purpose UNKNOWN).

**Live probe from this machine, 2026-09-19:**

```
$ curl -s -o /dev/null -w "%{http_code}" -X POST https://api.z.ai/api/anthropic/v1/messages \
    -H "content-type: application/json" -d '{"model":"glm-5.3",...}'
401
{"error":{"message":"Authentication parameter not received in Header, unable to authenticate","type":"1001"}}
```

The Anthropic surface returns a **real HTTP 401 with an Anthropic-shaped error body** — i.e. an
Anthropic SDK client will handle its errors natively. Note for §E that the *monitor* endpoints do
**not** behave this way.

### Models currently served on the plan

VERIFIED from `docs.z.ai/devpack/latest-model`, `docs.z.ai/guides/llm/glm-5.3`, and the official
helper's `model-registry.js` read on disk:

| Model id | Context window | Notes |
|---|---|---|
| `glm-5.3` | **1,048,576** (1M) | text-only; 128K max output; "always operates with reasoning enabled", effort `low` / `high` / `max`. Released **2026-08-18**. |
| `glm-5.3-flash` | **1,048,576** (1M) | multimodal; 320B total / 18B active params (CLAIMED). Released **2026-08-26**. **This is the helper's hard-coded default for *both* the main and the small model.** |

Older ids the registry still maps (VERIFIED, from `model-registry.js`): `glm-5.2` 1M, `glm-5.1`
200,000, `glm-5` 200,000, `glm-5-turbo` 204,800, `glm-4.7` 200,000, `glm-4.5-air` 128,000; fallback
for an unknown custom id is **200,000**.

> **The task brief said "GLM-4.6/4.7 class". That is a generation and a half stale.** The plan serves
> GLM-5.3 / GLM-5.3-Flash as of today, and the 200K → 1M context jump between those generations
> changes the axis-D arithmetic completely.

**Open weights exist** (VERIFIED, HuggingFace `zai-org`, queried today): `GLM-5.3-Flash` and
`GLM-5.3-Flash-BF16` are **MIT**; `GLM-5.3` and `GLM-5.3-BF16` are **"Other"** — a non-MIT licence
whose terms this pass did not open. `GLM-5.2`/`-FP8`, `GLM-5.1`, `GLM-5`, `GLM-4.7` are MIT. The
self-host escape hatch is therefore real for Flash and licence-encumbered for the flagship.

---

## A. LAUNCH

**Z.ai contributes nothing to this axis and takes nothing away. The driver owns it entirely.**

### A.1 Claude Code (the recommended driver)

Everything in `claude-code.md` §A holds unchanged: `-p/--print`, `--output-format text|json|stream-json`,
`--input-format stream-json`, `--bg/--background`, `--include-partial-messages`, `--include-hook-events`
(all VERIFIED by running `claude --help` on the local 2.1.278 build today). None of it involves the
provider.

The GLM-specific part is purely environment. **Set these in the child process's environment — never
in a settings file** (see §F for why):

```
ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
ANTHROPIC_AUTH_TOKEN=<z.ai coding-plan key>
API_TIMEOUT_MS=3000000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3[1m]
ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3[1m]
ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5.3-flash[1m]
CLAUDE_CODE_AUTO_COMPACT_WINDOW=1048576
```

Every name and value above is **VERIFIED**: read from Z.ai's own `@z_ai/coding-helper@0.1.1`
(`dist/lib/claude-code-manager.js`, unpacked into the scratchpad and read today) and corroborated by
`docs.z.ai/devpack/tool/claude`. `API_TIMEOUT_MS: '3000000'` (50 minutes) and
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: 1` are literal constants in that source.

The `[1m]` suffix is not decoration. The helper's own rule (VERIFIED, `model-registry.js`):

```js
export function formatModelForClaudeCode(model, contextWindow) {
    if (contextWindow >= 1_000_000 && !/\[1m\]$/i.test(model)) return `${model}[1m]`;
    return model;
}
```

**Claude Code's third-party model-mapping semantics.** Z.ai's own docs say manual model mapping is
"generally not recommended… as they prevent automatic updates" — meaning if you set only
`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`, Z.ai's gateway maps Claude's `opus`/`sonnet`/`haiku`
tiers to current GLM models server-side. Separately, the local Claude Code binary contains the
strings `CLAUDE_CODE_3P_PROBE_WROTE_OPUS_DEFAULT` and `CLAUDE_CODE_3P_PROBE_WROTE_SONNET_DEFAULT`
(VERIFIED — present in the 2.1.278 binary), implying a third-party-provider probe that writes model
defaults after inspecting the endpoint. **The exact semantics of that probe are UNKNOWN** and it
should not be relied on: pin the model ids explicitly.

### A.2 pi

`ZAI_API_KEY=<key>`, then `/login zai` and `/model` inside pi; credentials persist to
`~/.pi/agent/auth.json` in the shape `{"zai":{"type":"api_key","key":"..."}}` (VERIFIED —
`docs.z.ai/devpack/tool/pi`, and the same path/shape independently documented by the `pi-glm-usage`
extension). pi's own launch surface (`--print/-p`, `--mode text|json|rpc`, `--session-id`) is in the
field scan, all VERIFIED there.

### A.3 Codex

VERIFIED from `@z_ai/coding-helper` `dist/lib/codex-manager.js` — this is what the official helper
writes into `~/.codex/config.toml`:

```toml
model_provider     = "ZAI"
model              = "glm-5.3-flash"
model_reasoning_effort = "max"
model_catalog_json = "~/.codex/models.json"

[model_providers.ZAI]
name  = "ZAI"
base_url = "https://api.z.ai/api/v1"          # global; CN: https://open.bigmodel.cn/api/v1
experimental_bearer_token = "<key>"
wire_api = "responses"
```

It also writes a model entry into `~/.codex/models.json` carrying
`context_window` / `max_context_window` = the model's window, `effective_context_window_percent: 95`,
`supports_parallel_tool_calls: true`, `apply_patch_tool_type: 'freeform'`,
`truncation_policy: {mode:'bytes', limit:10000}` (VERIFIED, same file). Note the key is written to
`config.toml` under `experimental_bearer_token` — an experimental field name, and a plaintext secret
in a config file.

### A.4 opencode

VERIFIED from `dist/lib/opencode-manager.js`. Provider id is **`zai-coding-plan`** (global) or
**`zhipuai-coding-plan`** (China); it writes into `opencode.json`:

```json
{ "$schema": "https://opencode.ai/config.json",
  "provider": { "zai-coding-plan": { "options": { "apiKey": "<key>" } } },
  "model": "zai-coding-plan/glm-5.3-flash",
  "small_model": "zai-coding-plan/glm-5.3-flash" }
```

Interactively, opencode's `/connect` offers "Z.AI Coding Plan", "Z.AI" or "Zhipu" (VERIFIED — quoted
from the `opencode-glm-quota` plugin's own error text).

### A.5 Crush / Factory Droid

Crush: `~/.config/crush/crush.json`, base URL `https://api.z.ai/api/coding/paas/v4` (OpenAI
chat-completions). Droid: `~/.factory/settings.json`, supports both an `anthropic`-type provider at
`https://api.z.ai/api/anthropic` and an `openai` / `generic-chat-completion-api` provider at
`.../coding/paas/v4`. Both VERIFIED from the helper's source.

### A.6 ZCode — Z.ai's own harness, and why it is not a candidate

ZCode is Z.ai's official "Agentic Development Environment": an **Electron desktop app**, downloaded
as a binary, not a CLI (VERIFIED, `zcode.z.ai/en/docs/welcome` — "Download the desktop app"; no
binary name, no headless mode, no SDK, no automation interface documented anywhere in its docs
navigation). Its feature list (Agent, Goal Mode, Subagents, Skills, Hooks, MCP, Automations,
Idle-time Tasks, Remote Control, Bot Channel, Usage Stats) reads like a competitor to this
orchestrator, not a target for it.

**Verdict: ZCode is out of scope as an orchestrated platform.** An unattended supervisor cannot
launch it headlessly, cannot read its transcripts, and cannot resume it by id. Its "Remote Control"
and "Bot Channel (Feishu/WeChat)" features are the only remote-drive surface and both are
human-facing (UNKNOWN whether either exposes a documented API).

One near-miss worth recording: **`zagent`** (npm `zagent`, bins `zagent` / `za`) claims to be a
terminal agent "driving your installed ZCode runtime from the shell", with `-p`, `--json`,
`--session id`, `zagent quota [status|usage|balance|preview|reset] [--json]`, `zagent sessions --json`,
`zagent rewind`, and a `zagent mcp` stdio server exposing `zagent_turn` / `zagent_quota` /
`zagent_models` / `zagent_doctor` (CLAIMED — from its README only). **It has 1 GitHub star and is
explicitly unofficial.** Do not build on it. Its config path `~/.zcode/cli/config.json` is however a
hint that a ZCode-runtime CLI surface exists; establishing whether Z.ai has an *official* one is an
open question.

---

## B. IDENTITY & RESUME

**Entirely client-side. GLM neither helps nor hinders.**

Claude Code's answers hold verbatim — `--session-id <uuid>` names a session before it exists,
`-r/--resume [id]`, `-c/--continue`, `--fork-session`, `--no-session-persistence`, `--bg` + `claude
attach|logs|stop|rm|agents` (all VERIFIED by `claude --help` today). Session records are JSONL under
the config dir's `projects/`; nothing in them depends on the provider. See `claude-code.md` §B.

**Z.ai has no server-side session concept at all.** There is no conversation id, no server-side
thread, no "list my sessions" endpoint anywhere in `docs.z.ai`'s sitemap (VERIFIED — the sitemap has
69 URLs and contains no session/conversation management API outside the unrelated `agents/` product).
The Anthropic Messages surface is stateless request/response, as the real Anthropic API is.

**What survives a crash:** whatever the driver persists. What does *not* survive is free: **resume
replays the whole conversation to the provider on the next turn, and those input tokens are charged
against your GLM credits again.** Z.ai publishes cached-input pricing ($0.26/Mtok for GLM-5.3 vs
$1.40 uncached) and the credit model explicitly tracks "input, cached, and output tokens separately",
so a cache probably absorbs most of a resume — but **whether Z.ai's gateway honours Anthropic-style
`cache_control` breakpoints as sent by Claude Code is UNKNOWN**, and it is the single most expensive
unknown in this profile. A crash-loop that resumes ten times on a 600K-token context is either
trivial or catastrophic depending on that one answer.

**A provider outage is invisible to resume** and shows up as request errors; see §E for the in-band
error codes and §J for what an unattended run does with them.

---

## C. TRANSCRIPT

**Entirely client-side. Inherits the driver's answer; see `claude-code.md` §C.**

There is **no Z.ai-side transcript** — no endpoint returns past requests or responses, and none
appears in the API reference sitemap (VERIFIED). The `monitor/usage/model-usage` and
`monitor/usage/tool-usage` endpoints return *aggregates* over a 24-hour rolling window, not content.

One consequence worth stating plainly: **a supervisor reading a GLM session's progress is reading the
driver's JSONL, which means GLM inherits every transcript strength and every transcript weakness the
driver has.** It adds no independent way to tell whether a stalled session is stuck on the model or
stuck on itself.

---

## D. CONTEXT — read fullness, trigger compaction, prove it happened

This axis is **half inherited, half GLM-specific**, and the GLM-specific half is a real trap.

### D.1 Reading fullness — inherited, unaffected

Claude Code's three ways of reading context fullness (see `claude-code.md` §D) all work against a
third-party provider, because all three are computed client-side from the transcript. Z.ai adds no
fourth way and blocks none of them.

### D.2 Triggering compaction — inherited, with a required GLM parameter

`/compact` and auto-compaction are Claude Code features. They fire a summarisation request at
whatever provider is configured, so with GLM they cost **GLM credits, not Anthropic quota**.

The GLM-specific part: **Claude Code cannot discover a third-party model's context window, so if the
orchestrator does not tell it, auto-compaction fires at the wrong point.** Two levers, both VERIFIED:

- **CLI flag** — `--autocompact <auto|tokens>`: *"Auto-compact window size (auto, or 100k–1M tokens)"*
  (VERIFIED, quoted from `claude --help` on the local 2.1.278 build today).
- **Environment** — `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. Z.ai's own helper writes it as
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW: String(sel.modelContextWindow)` (VERIFIED, literal line in
  `claude-code-manager.js`), i.e. `"1048576"` for a 1M model. `docs.z.ai/devpack/latest-model` shows
  the same knob as `"CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"`.

Related env names present in the 2.1.278 binary and relevant here (VERIFIED as *present*; their exact
semantics are UNKNOWN and undocumented): `CLAUDE_CODE_MAX_CONTEXT_TOKENS`,
`CLAUDE_CODE_DISABLE_1M_CONTEXT`, `CLAUDE_CODE_COLD_COMPACT`, `CLAUDE_CODE_DISABLE_PRECOMPACT_SKIP`.

> **The trap, stated as a rule:** the `[1m]` model suffix, the `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
> value and the actual model id must agree. Get it wrong in one direction and a 1M-context model
> compacts at 200K, throwing away 80% of the window the owner is paying for. Get it wrong in the
> other and the session runs past the model's real limit and the provider errors mid-run. The
> orchestrator's provider object must therefore carry `context_window` as a **first-class field**,
> not derive it.

### D.3 Proof it happened — inherited

The proof is the compaction entry in the driver's transcript (VERIFIED for Claude Code in
`claude-code.md` §D; VERIFIED for pi in the field scan, which records a typed `CompactionEntry`
written into the session file). **Z.ai offers no independent proof** — no server-side event, no
compaction hook, nothing. If the driver's transcript does not record it, it is unprovable.

**Z.ai-side compaction/handoff hook: none exists.** (VERIFIED by absence — no such endpoint or
feature in the API reference or devpack docs.) There is a `docs.z.ai/devpack/resources/memory-mechanism`
page (not read in this pass) that may describe a plan-level memory feature; whether it is
orchestrator-controllable is **UNKNOWN**.

---

## E. QUOTA — *the axis where GLM is genuinely strong*

**This is the best answer to axis E of any platform in the scan so far, including Claude Code's, on
one measure: it needs no OAuth token, no keychain, and no beta header — just the same API key the
session already uses.**

### E.1 The endpoint

VERIFIED three ways: read in **Z.ai's own official code** shipped inside `@z_ai/coding-helper@0.1.1`
(`zai-coding-plugins/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs`, read on
disk today), read in the community `opencode-glm-quota` plugin's source, and **probed live from this
machine today**.

```
GET  https://api.z.ai/api/monitor/usage/quota/limit           # current quota percentages
GET  https://api.z.ai/api/monitor/usage/model-usage?startTime=…&endTime=…   # 24h rolling
GET  https://api.z.ai/api/monitor/usage/tool-usage?startTime=…&endTime=…    # 24h rolling (MCP)
```

China host: swap `api.z.ai` for `open.bigmodel.cn`. The official script derives the monitor host from
`ANTHROPIC_BASE_URL`'s origin, so the orchestrator's provider object needs only one URL.

**Headers — exact, and one of them is a trap:**

```
Authorization: <raw api key>        # NO "Bearer " prefix — this is load-bearing
Accept-Language: en-US,en           # without it, the CN host returns Chinese error text
Content-Type: application/json
```

The no-Bearer rule is stated as a comment in Z.ai's own script (`'Authorization': authToken`) and
called out explicitly in the community plugin (`// NO "Bearer" prefix`). Both VERIFIED.

The `Accept-Language` point is VERIFIED by live probe: `open.bigmodel.cn` without it returned
`{"code":401,"msg":"令牌已过期或验证不正确","success":false}`.

### E.2 The response — and the HTTP-200 trap

**Live probe, this machine, 2026-09-19:**

```
$ curl -s -w " HTTP %{http_code}" https://api.z.ai/api/monitor/usage/quota/limit
{"code":1001,"msg":"Authentication parameter not received in Header, unable to authenticate","success":false} HTTP 200

$ curl -s -w " HTTP %{http_code}" https://api.z.ai/api/monitor/usage/quota/limit -H "Authorization: not-a-real-key"
{"code":401,"msg":"token expired or incorrect","success":false} HTTP 200
```

> **The monitor endpoints return HTTP 200 on authentication failure.** The error lives in the body's
> `code` / `success` fields. Both the official Z.ai script and the community plugin gate on
> `res.statusCode !== 200`, so **both treat an auth failure as a successful response.** Traced through
> the code: the official script falls back to `json.data || json` and prints the raw error envelope
> under the heading `Quota limit data:`; the community plugin reads `quotaResponse.data`, gets
> `undefined`, and renders an **empty quota table with no error at all**. An orchestrator that copies
> either implementation inherits a monitor that reports "no quota data" when the real answer is "your
> key is wrong" — the worst possible failure for an unattended pause loop. The correct check is
> `json.success === true`, not the HTTP status.
>
> Note the contrast with the *inference* endpoints, which return honest HTTP codes (401 probed above,
> 429 documented in §E.4). The two surfaces do not behave the same way.

**Success envelope** (VERIFIED from the official script's `json.data` unwrapping and the community
plugin's typed interface):

```jsonc
{ "code": 200, "success": true, "msg": "…",
  "data": {
    "level": "lite" | "pro" | "max",          // plan tier
    "limits": [
      { "type": "TOKENS_LIMIT", "unit": 3, "number": 5,
        "percentage": 41.7, "nextResetTime": 1789830000000 },   // 5-hour window
      { "type": "TOKENS_LIMIT", "unit": 6, "number": 1,
        "percentage": 12.4, "nextResetTime": 1790300000000 },   // weekly window
      { "type": "TIME_LIMIT",   "percentage": 3.1,
        "currentValue": 31, "usage": 1000,
        "usageDetails": [ { "modelCode": "web_search", "usage": 12 }, … ] }  // MCP, 1 month
    ] } }
```

**Window identification is by `unit` + `number`, not by a name** (VERIFIED, from
`opencode-glm-quota/src/utils/token-limits.ts`):

| `type` | `unit` | `number` | Means |
|---|---|---|---|
| `TOKENS_LIMIT` | 3 | 5 | **5-hour rolling window** |
| `TOKENS_LIMIT` | 6 | 1 | **weekly (7-day) window** |
| `TIME_LIMIT` | — | — | **MCP tool usage, 1-month window** (`currentValue` / `usage` are absolute counts) |

`unit: 5` is reported by one third party as web-search/reader quota (CLAIMED, `pi-glm-usage` docs; not
seen in either source I read).

**`nextResetTime` is a Unix timestamp in milliseconds.** That is the reset time the orchestrator's
pause/resume loop needs, and it is present per window. (VERIFIED — `reset-timer.ts` consumes it as
`resetTime - Date.now()`.)

> **A defect in Z.ai's own official script, worth knowing before copying it:** `query-usage.mjs`
> labels **every** `TOKENS_LIMIT` entry as `'Token usage(5 Hour)'` and drops `unit`, `number` and
> `nextResetTime` entirely. Run the official plugin and you get two identically-labelled rows and no
> reset time. **The community `opencode-glm-quota` plugin handles this correctly.** Read the raw
> endpoint; do not shell out to Z.ai's script. (VERIFIED — both sources read side by side today.)

**Absolute remaining capacity is not returned — only `percentage`.** For token windows there is no
`currentValue`/`total` pair (those appear only on the `TIME_LIMIT`/MCP entry). So the orchestrator can
answer "how full am I, and when does it reset" precisely, and "how many more tokens do I have" only by
multiplying the percentage against the published plan allowance. (VERIFIED by the absence of those
fields in both typed implementations.)

### E.3 What the windows actually measure — credits, not tokens, and not evenly

The plan moved from prompts to **credits** on **2026-07-30** (VERIFIED,
`docs.z.ai/devpack/notice/usage-revision`). Credits derive from tokens via a **time-of-day multiplier**:

| Model | Off-peak | Peak |
|---|---|---|
| GLM-5.3 | **1×** | **3×** |
| GLM-5.3-Flash | **0.4×** | **1.2×** |

**Peak = Monday–Friday, 14:00–18:00 Singapore time (UTC+8)** — i.e. **06:00–10:00 UTC**, which is
**09:00–13:00 Kyiv time (UTC+3)**. (VERIFIED, same page.)

> **This is a scheduling lever, not a footnote.** The same work costs **7.5× more credits** on
> GLM-5.3 at peak than on GLM-5.3-Flash off-peak (3× vs 0.4×). An overnight European queue runs
> almost entirely off-peak. An orchestrator that knows this can deliberately hold heavy work until
> after 13:00 Kyiv and cut its credit burn by two-thirds — and one that doesn't will burn a weekly
> window in a morning.

Individual plan allowances (VERIFIED, `docs.z.ai/devpack/overview`):

| Tier | 5-hour credits | Weekly credits | Price |
|---|---|---|---|
| Lite | 2,000 | 10,000 | **$18/mo** (VERIFIED — "Starting at just 18 USD per month") |
| Pro | 12,000 | 60,000 | ~$72/mo (CLAIMED, secondary source only) |
| Max | 28,000 | 140,000 | ~$160/mo (CLAIMED, secondary source only) |

Team plan, **per seat** (VERIFIED, `docs.z.ai/devpack/teamplan` and `…/notice/usage-revision`):

| Seat | 5-hour credits | Weekly credits | GLM-5.3 tokens/5h | GLM-5.3 tokens/week |
|---|---|---|---|---|
| Standard | 15,000 | 66,000 | 60M | 300M |
| Premium | 35,000 | 155,000 | 160M | 800M |

(Flash allowances are 2.5× the GLM-5.3 token figures, consistent with the 0.4× multiplier.)

The 5-hour window is **rolling, not fixed**: *"credit quota resets 5 hours after consumption"*. The
weekly window *"starts counting from the time you place your order"* — so **it is anchored to the
subscription date, not to a calendar week.** An orchestrator that assumes Monday resets will be wrong;
read `nextResetTime`.

### E.4 In-band limit signalling — precise and well-documented

VERIFIED, `docs.z.ai/api-reference/api-code`. All return **HTTP 429** on the *inference* surface:

| Code | Meaning |
|---|---|
| **1316** | **"Usage limit reached for the past 5 hours. Insufficient balance…"** — the 5-hour window is exhausted |
| **1317** | **"Usage limit reached for the past 7 days. Insufficient balance…"** — the weekly window is exhausted |
| 1310 | "Weekly/Monthly Limit Exhausted…" |
| 1308 | "Usage limit reached for `{number}` `{unit}`…" — parameterised by the same unit/number scheme as §E.2 |
| 1302 | "Rate limit reached for requests" — request-rate, not quota |
| 1305 | "The service may be temporarily overloaded, please try again later" |
| 1313 | **"Account's current usage pattern does not comply with Fair Usage Policy…"** — see §J |
| 1309 | "GLM Coding Plan package has expired…" |
| 1311 | "Current subscription plan does not yet include access to `${model_name}`" |
| 1318–1321 | Usage exhausted / monthly spend limit prevents extra usage |
| 1113 | "Insufficient balance or no resource package. Please recharge." |
| 1000/1001/1003 | 401 auth failures (no key, missing header, expired token) |

**1316 and 1317 are the two signals an unattended run must special-case**, and they distinguish the
5-hour pause (wait ~hours) from the weekly pause (wait ~days) *in band, without a second API call*.
That is better than having to poll. **Whether the 429 response body or headers also carry a reset
timestamp is UNKNOWN** — it could not be provoked without a live key, and no `anthropic-ratelimit-*`
or `retry-after` header appeared on the 401 probe. Assume not, and fall back to
`monitor/usage/quota/limit` → `nextResetTime`.

### E.5 A ready-made reader inside the session

Z.ai ships an **official Claude Code plugin marketplace** inside the `@z_ai/coding-helper` npm package
(VERIFIED, read on disk): `zai-coding-plugins` with `marketplace.json` pointing at two plugins —
**`glm-plan-usage`** ("Query quota and usage statistics for GLM Coding Plan service", author
`chao.gong@z.ai`) and `glm-plan-bug`. `glm-plan-usage` carries a command, an agent and a skill, all
wrapping the `query-usage.mjs` script described above.

**For the orchestrator this is the wrong shape** — it makes the *session* ask about its own quota,
which costs tokens and returns prose. The supervisor should call the endpoint directly with `curl`.
The plugin's value is as a signed, official statement of the contract, and as a fallback if the
endpoint ever changes.

---

## F. ACCOUNTS

### F.1 The good news: switching a new session's account is trivial and fully non-interactive

**A GLM "account" is three environment variables.** No OAuth, no browser, no keychain, no macOS
permission dialog, no config-directory juggling. To pin a new session to a chosen account, the
orchestrator sets `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` (+ model ids + window) **in the child
process's environment** and launches the driver. That is it.

Compare with `claude-code.md` §F: Claude Code's own multi-account story needs `CLAUDE_CONFIG_DIR`,
per-account keychain entries under a derived service name, and carries a documented failure mode where
macOS blocks an unattended run on a GUI Keychain dialog. **The GLM path has none of that.** For an
overnight fleet, *this is a genuine advantage of GLM over the owner's current platform*, and it is
worth saying out loud because it is counter-intuitive.

N accounts on one machine is therefore just N key strings in the orchestrator's own store. There is
no per-account directory to create and nothing to install twice.

### F.2 The bad news: the usage policy, not the tech, is the constraint

VERIFIED, `docs.z.ai/devpack/usage-policy`:

- **"Account sharing or multi-user access is prohibited. Violations may result in restrictions on
  subscription benefits and, in serious cases, may affect normal account usage."**
- **"GLM Coding Plan may only be used within officially supported tools and products. Use in
  unsupported tools may result in restricted benefits."**
- Concurrency is tier-scoped: **Lite = single project; Pro = 1–2 simultaneous projects; Max = 2+
  simultaneous projects.** *"Plan users will enjoy higher concurrency limits during off-peak hours
  (dynamically increased)."*
- **"Violations of the Usage Rules may trigger risk control measures, including rate limiting, account
  freezing, or other restrictions. Accounts with more than three violations may be banned."**
  Error code **1313** is the in-band signal that this has fired.

Read together with §E.3's peak/off-peak multiplier, the picture is consistent: **Z.ai prices and
polices concurrency, and an orchestrator running a fleet is exactly the pattern its risk control is
watching for.**

Three consequences the orchestrator must encode:

1. **Do not fan one key across many parallel sessions beyond the tier's stated concurrency.** On Lite
   that means *one* session. This is the hard ceiling on "run the queue across several sessions" with
   a single GLM subscription.
2. **Buying N individual subscriptions to get N keys is the thing the policy prohibits** if they are
   one person's. **The Team Plan is the sanctioned multi-key path**: minimum 2 seats, no upper limit,
   *"Members and seats follow a 1:1 relationship; multiple members cannot share the same seat"*, each
   member gets their own key, and **"Plan usage is limited separately by seat"** — per-seat quota
   isolation, which is precisely the per-role account model the owner asked for. The Team Plan key is
   *"independent from other platform API Keys"* and must be used explicitly. (All VERIFIED,
   `docs.z.ai/devpack/teamplan`.) The catch: seats map to *people*, so a one-person fleet across
   several seats is arguably the same violation in a different shape. **Whether Z.ai treats an
   individual running an agent fleet across their own team seats as compliant is UNKNOWN and should be
   asked before money is spent.**
3. **Driving GLM from a home-grown harness that hits the endpoint directly may count as an
   "unsupported tool".** Driving it through Claude Code / Codex / opencode / pi — all on the official
   list — does not. This is an argument for the orchestrator remaining a *launcher of supported CLIs*
   rather than an API client in its own right.

### F.3 Changing a *running* session's account

**No.** Same answer as every other platform: the env is read at process start. The workaround is the
same too — checkpoint, kill, relaunch with `--resume <id>` under the new env. The GLM-specific cost of
that workaround is §B's: the replayed context is re-billed to the *new* account's credits.

### F.4 Where keys live, and the one tool that must never be run

Key management pages (VERIFIED): individual plan → `https://z.ai/manage-apikey/apikey-list` and
`https://z.ai/manage-apikey/subscription`; team → `https://z.ai/manage-apikey/coding-plan/team/my-plan`,
usage at `…/team/usage-stats`, billing at `https://z.ai/manage-apikey/billing`.

Z.ai's official CLI, `@z_ai/coding-helper` **0.1.1** (published **2026-08-27**; bins `coding-helper`
and `chelper`), stores **exactly one key**: `~/.chelper/config.yaml` with a flat `{lang, plan,
api_key}` shape — `getApiKey()` / `setApiKey()` / `revokeApiKey()` on a single field (VERIFIED,
`dist/lib/config.js`). **It has no concept of multiple accounts.** Plaintext YAML, no keychain.

> **`coding-helper auth reload claude` must never be run on the owner's machine by the orchestrator.**
> VERIFIED from `dist/lib/claude-code-manager.js`, `loadGLMConfig()` does three destructive things:
> 1. `ensureOnboardingCompleted()` — writes `hasCompletedOnboarding: true` into `~/.claude.json`;
> 2. `cleanupShellEnvVars()` — **edits the user's shell rc files** to strip `ANTHROPIC_API_KEY` and
>    `ANTHROPIC_BASE_URL`;
> 3. rewrites **`~/.claude/settings.json`**, deleting `ANTHROPIC_API_KEY` and the three
>    `ANTHROPIC_DEFAULT_*_MODEL` keys and replacing the `env` block.
>
> On this machine that would collide head-on with the profile-switcher setup (profiles, each
> with its own config dir, all symlinking into the shared `~/.claude` content store) and with the
> `~/.zshrc` MiMo alias. **The orchestrator sets environment per child process and touches no config
> file.** The helper is useful only as documentation of the correct values — which is how this
> profile used it.

---

## G. INTERVENTION

**Z.ai contributes nothing. This axis is 100% the driver's, and the driver choice is therefore the
whole answer.**

- **Claude Code**: the control protocol over `--input-format stream-json` / `--output-format
  stream-json`, `--replay-user-messages` for acknowledgment, `--permission-prompts host|none`, and the
  permission-prompt tool. All VERIFIED in `claude-code.md` §G and by `claude --help` today. All
  provider-independent.
- **pi**: `--mode rpc` — line-delimited JSON on stdin/stdout with `id`-correlated
  `{type:"response"}` replies (VERIFIED in the field scan). Since **Z.ai officially supports pi**,
  this is available *today* against GLM with no adapter work.
- **ZCode**: "Remote Control" and "Bot Channel" exist but are human-facing; **UNKNOWN** whether either
  is programmatically addressable.

**Answering a session's own question programmatically:** unchanged from the driver. GLM neither
provides a protocol event nor prevents one.

One GLM-shaped caveat: **a third-party model's fidelity at following a mid-run injected instruction is
not the same question as whether the injection arrived.** The protocol acknowledgment proves delivery;
it does not prove GLM-5.3 obeys a course correction as reliably as the model the workflow was tuned
on. That is an empirical question this pass could not answer (**UNKNOWN**) and it is the right thing
to measure in a first paid trial.

---

## H. GUARDRAILS

**Entirely the driver's.** Claude Code's `--permission-mode acceptEdits|auto|bypassPermissions|manual|dontAsk|plan`,
`--allowedTools` / `--disallowedTools`, `--restricted`, `--safe-mode`, `--bare`, hooks and sandboxing
all work identically against a third-party endpoint (VERIFIED by `claude --help`; none of these
touch the provider). See `claude-code.md` §H.

**Z.ai-side guardrails for unattended use: none.** There is no server-side permission model, no
tool-allowlist, no sandbox, and no "this request looks destructive" gate. The only server-side control
that exists is **risk control** (§F.2) — and it is aimed at protecting Z.ai's capacity, not the
owner's repository. It can freeze an account mid-run, which is a *hazard* to an unattended queue, not
a safeguard for it.

**What it will do unattended without asking:** exactly what the driver's permission mode allows.
Nothing about routing through GLM makes an unattended session more cautious. If anything, a cheaper
provider invites `--dangerously-skip-permissions` on work that would not have earned it at Anthropic
prices; that temptation is a real operational risk and should be named in the orchestrator's defaults.

---

## I. EXTENSIBILITY

**MCP works.** Z.ai publishes MCP servers of its own — `search-mcp-server`, `reader-mcp-server`,
`vision-mcp-server`, `zread-mcp-server` (VERIFIED, in the docs sitemap), and the official helper has a
dedicated `mcp-manager.js` that writes MCP config for Claude Code (`~/.claude/mcp.json`), Crush and
Droid, supporting `stdio`, `sse` and `streamable-http` transports (VERIFIED, read on disk). **MCP tool
usage is metered** — it is the `TIME_LIMIT` / 1-month bucket in the quota response, with a per-tool
`usageDetails` breakdown (`web_search`, `web_reader`, …). An orchestrator that leans on Z.ai's MCP
servers is spending a *third* budget with its own window.

**Custom commands, skills, subagents, config precedence:** all the driver's, all unchanged. A
GSD-style, subagent-heavy workflow runs inside Claude Code against GLM with no structural change.

Three GLM-specific costs of that, though:

1. **Every subagent is a full model call on GLM credits.** The `ANTHROPIC_DEFAULT_HAIKU_MODEL` mapping
   is the lever — Z.ai's own default points *both* tiers at `glm-5.3-flash[1m]`, and Flash is **0.4×**
   credits off-peak against GLM-5.3's 1× (§E.3). A swarm workflow should pin cheap roles to Flash
   explicitly rather than inherit whatever the gateway maps.
2. **Claude Code's `--max-budget-usd`** exists (VERIFIED, `claude --help`) but it computes spend from
   the usage numbers the provider returns and Anthropic's price table. **Whether it produces a
   meaningful number against Z.ai is UNKNOWN** — treat it as unusable for GLM and budget in credits
   via §E instead.
3. **Prompt-cache behaviour is the load-bearing unknown** (§B). Every subagent spawn re-sends a system
   prompt and context; whether Z.ai's gateway honours Anthropic `cache_control` breakpoints decides
   whether a subagent-heavy workflow is cheap or ruinous on this provider.

Z.ai also ships an official Claude Code **plugin marketplace** (`zai-coding-plugins`, §E.5) — evidence
that Z.ai treats Claude Code as a first-class host, not a tolerated one.

---

## J. OPERATIONAL REALITY

**Cost model.** Subscription credits, not metered tokens, for plan users; pay-as-you-go API pricing
exists separately (VERIFIED, `docs.z.ai/guides/overview/pricing`, all USD):

| Model | Input | Cached input | Output |
|---|---|---|---|
| GLM-5.3 | **$1.40** /Mtok | **$0.26** /Mtok | **$4.40** /Mtok |
| GLM-5.3-Flash | **$0.15** /Mtok | **$0.03** /Mtok | **$0.50** /Mtok |

Cached-input storage is *"Limited-time Free"*. For comparison with the field scan's other cheap
provider: Xiaomi MiMo-V2.5-Pro is $0.435 in / $0.87 out — **GLM-5.3-Flash undercuts it roughly 3× on
input and 1.7× on output**, and GLM-5.3 flagship is ~3× more expensive than MiMo on input. On a
subscription, the marginal cost of an overnight run is **zero until a window is exhausted** — which is
exactly the property an unattended queue wants, and the opposite of a metered API's failure mode.

**Maturity.** Endpoints, docs and error codes are mature and precise. The *tooling* around them is
young: the official CLI is **0.1.1**, the official usage script has a real labelling defect (§E.2),
and the best quota implementation in the field is a **30-star community plugin**. Two parallel doc
trees disagree with each other: `docs.z.ai/devpack/tool/claude` gives `glm-5.3` while
`docs.z.ai/scenario-example/develop-tools/claude` still gives `GLM-4.7` / `GLM-4.5-Air` and tells
readers to update configs written before 2025-09-30. **Prefer `/devpack/`; treat `/scenario-example/`
as stale.** (Both VERIFIED by reading them today.)

**Install footprint.** With Claude Code as driver: **zero.** No new binary, no new daemon, no new
config directory — only environment variables on a process the machine already runs. This is the
smallest footprint of any platform in the scan.

**Platform support (macOS).** Nothing platform-specific is involved on the driver side. ZCode ships a
macOS Apple-Silicon desktop build (VERIFIED). The rest is HTTPS.

**Known unattended-run failure modes:**

| Failure | Signal | Tag |
|---|---|---|
| 5-hour window exhausted | HTTP 429, code **1316** | VERIFIED (docs) |
| Weekly window exhausted | HTTP 429, code **1317** | VERIFIED (docs) |
| Request-rate limit / overload | 429 code **1302** / **1305** | VERIFIED (docs) |
| Risk control fires on a fleet | 429 code **1313**, and possibly account freeze | VERIFIED (docs) |
| Plan expired mid-run | 429 code **1309** | VERIFIED (docs) |
| Quota poll silently "succeeds" on a bad key | HTTP **200** + `success:false` | **VERIFIED live today** |
| Auto-compaction at the wrong threshold | none — silent context loss | VERIFIED (mechanism); see §D.2 |
| Resume re-bills the whole context | none — silent credit burn | VERIFIED (mechanism); magnitude UNKNOWN |
| Peak-hour 3× multiplier drains a window in a morning | none — silent | VERIFIED (docs) |
| Model/`[1m]`/window triple disagrees | none — silent truncation or provider error | VERIFIED (mechanism) |

Note how many of these are **silent**. GLM's in-band error codes are excellent; its *silent* failure
modes are where an overnight run actually dies.

**Is it plausible to run unattended overnight today? Yes — with one caveat that is not technical.**

Technically: launch is solved, resume is solved, transcripts are solved, compaction is solved with one
required parameter, quota is the best-instrumented of any platform here, and account switching is
easier than on Claude Code. A single-session overnight queue on a Pro or Max plan is straightforwardly
viable right now.

The caveat is **§F.2**. The owner's stated design — a fleet of sessions across several accounts — runs
directly at the tier concurrency limits and at a usage policy that prohibits account sharing and bans
after three violations. **GLM is an excellent platform for one or two concurrent unattended sessions
and a policy risk for six.** The Team Plan is the sanctioned route and needs a direct question to Z.ai
before it is relied on.

---

## What this costs the orchestrator

**What GLM gives for free** (no adapter work at all):

1. A **new provider with zero new adapter** — a `{base_url, token, model, context_window}` object and
   an existing Claude Code / pi / Codex / opencode launcher.
2. **The cleanest per-role account switching in the scan** — three env vars per child process. No
   config dir, no keychain, no GUI dialog, no profile-switcher machinery.
3. **A quota endpoint that needs only the session's own key** — percentage + `nextResetTime` per
   window, one unauthenticated-shaped `curl`, no OAuth token and no beta header.
4. **Two distinct in-band exhaustion codes** (1316 five-hour, 1317 weekly) that tell a pause loop *how
   long* to sleep without a second call.
5. **Near-zero marginal cost per overnight run** while a window holds, at roughly an order of magnitude
   under frontier pricing.

**What it costs to build:**

1. **A provider object with `context_window` as a first-class field**, plus the `[1m]`-suffix rule and
   `--autocompact` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` wiring. Not optional: get it wrong and 80% of a
   1M window is silently discarded. *(~half a day)*
2. **A quota reader that checks `json.success`, not the HTTP status**, and identifies windows by
   `unit`+`number`. Both shipped implementations get one of these wrong. *(~2 hours)*
3. **A credit model, not a token model** — percentages against published plan allowances, plus the
   peak-hour multiplier table and the fact that the weekly window is anchored to the **subscription
   date**, not the calendar. *(~half a day)*
4. **A concurrency governor keyed to the plan tier** (Lite 1 / Pro 1–2 / Max 2+), because exceeding it
   is a policy violation with a three-strikes ban attached, not merely a 429. **This is the piece that
   constrains the whole fleet design.** *(design decision, not code)*
5. **A hard rule that no orchestrator code ever invokes `coding-helper auth reload`**, and that all
   GLM configuration is per-process environment. *(a lint rule and a comment)*
6. **A paid trial to answer the prompt-cache question**, which decides whether resume and subagent
   fan-out are cheap or ruinous on this provider. *(one Lite month, $18)*

**What GLM does *not* solve, and never will:** axes A, B, C, G, H and most of I. Those are the
driver's. **Choosing GLM is choosing a price and a quota API. It is not choosing an orchestration
surface.** The orchestration surface question is answered by picking Claude Code or pi as the driver —
and since Z.ai supports both, that choice stays open.

---

## Open questions for a later pass

| # | Question | Axis | Why it matters |
|---|---|---|---|
| 1 | Does Z.ai's Anthropic gateway honour `cache_control` breakpoints as Claude Code sends them? | B, I, J | Decides whether resume and subagent fan-out are cheap or ruinous. **The single most expensive unknown here.** |
| 2 | Does the 429 body or headers carry a reset timestamp, or must the pause loop poll `quota/limit`? | E | One call vs two on every limit hit. |
| 3 | Does Z.ai consider one person running an agent fleet across their own Team seats compliant? | F, J | Decides whether the fleet design is legal at all. Ask before buying. |
| 4 | Does `unit: 5` really mean web-search/reader quota? Are there other `unit` values? | E | The window map is currently built from two implementations, not a spec. |
| 5 | Are the `usage` numbers on Anthropic-surface responses accurate enough for `--max-budget-usd`? | I, J | Would give a second, independent spend brake. |
| 6 | Does Z.ai publish an **official** ZCode-runtime CLI (`~/.zcode/cli/config.json` hints at one)? | A, G | Would change ZCode from "out of scope" to a candidate. |
| 7 | What licence is `zai-org/GLM-5.3` ("Other") — and does it permit self-hosting? | J | The escape hatch if the plan's policy blocks the fleet. Flash is already MIT. |
| 8 | What is `docs.z.ai/devpack/resources/memory-mechanism`, and is it orchestrator-controllable? | D | A possible plan-level handoff mechanism, not read in this pass. |
| 9 | What do `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and `CLAUDE_CODE_COLD_COMPACT` actually do? | D | Present in the 2.1.278 binary, undocumented; could sharpen axis D. |
| 10 | Does GLM-5.3 follow a mid-run injected instruction as reliably as the workflow's tuned model? | G | Delivery is provable; obedience is not. Measure in the trial. |

**A note on a referenced input.** The task pointed at prior orchestrator research at
`…/scratchpad/context/orchestrator-landscape.md`. That path is still empty as of this writing
(VERIFIED — the `context/` directory exists and contains nothing), so this document could not be
checked against it for overlap. It covers the *platform*, not orchestrators, so overlap should be
minimal.

---

## Sources

All retrieved or run on **2026-09-19** unless noted.

**Run on this machine (VERIFIED):**
- `claude --help`, `claude --version` — Claude Code **2.1.278**, `~/.local/bin/claude` →
  `~/.local/share/claude/versions/2.1.278`
- `strings` over that binary — `ANTHROPIC_*` / `CLAUDE_CODE_*` env surface
- `which` / `ls` probe for GLM footprint: none found
- Live unauthenticated probes of `https://api.z.ai/api/monitor/usage/quota/limit`,
  `https://open.bigmodel.cn/api/monitor/usage/quota/limit`,
  `https://api.z.ai/api/anthropic/v1/messages`, `https://api.z.ai/api/coding/paas/v4/chat/completions`
- `npm view @z_ai/coding-helper` → **0.1.1**, published **2026-08-27**, bins `coding-helper` / `chelper`

**Read as source code (VERIFIED — primary):**
- `@z_ai/coding-helper@0.1.1`, unpacked to the scratchpad: `dist/lib/claude-code-manager.js`,
  `codex-manager.js`, `opencode-manager.js`, `crush-manager.js`, `factory-droid-manager.js`,
  `model-registry.js`, `config.js`, `commands/auth.js`
- `zai-coding-plugins/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs` —
  **Z.ai's own official quota-query implementation**
- `zai-coding-plugins/.claude-plugin/marketplace.json`
- `github.com/guyinwonder168/opencode-glm-quota` (MIT, 30 stars, pushed **2026-09-13**):
  `src/api/endpoints.ts`, `src/api/client.ts`, `src/api/platforms.ts`, `src/utils/token-limits.ts`,
  `src/utils/reset-timer.ts`, `src/utils/time-window.ts`, `src/index.ts`

**Official documentation (VERIFIED):**
- `https://docs.z.ai/devpack/overview` — plan tiers, 5-hour and weekly credits
- `https://docs.z.ai/devpack/faq` — 5-hour cycle, weekly reset anchored to order date, base URLs, 1113
- `https://docs.z.ai/devpack/quick-start` — three protocol base URLs, key management pages
- `https://docs.z.ai/devpack/tool/claude` — Claude Code env block, install script, model mapping
- `https://docs.z.ai/devpack/tool/pi` — `ZAI_API_KEY`, `/login zai`, `~/.pi/agent/auth.json`
- `https://docs.z.ai/devpack/tool/others` — the full officially-supported tool list
- `https://docs.z.ai/devpack/extension/coding-tool-helper` — `coding-helper` command surface
- `https://docs.z.ai/devpack/teamplan` — seats, per-seat keys, per-seat quota isolation
- `https://docs.z.ai/devpack/notice/usage-revision` — credits migration (**2026-07-30**), peak
  multipliers, peak window, team token allowances
- `https://docs.z.ai/devpack/usage-policy` — account sharing ban, tier concurrency, risk control
- `https://docs.z.ai/devpack/latest-model` — current models, `[1m]`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
- `https://docs.z.ai/api-reference/api-code` — full error-code table (1113, 1302–1321)
- `https://docs.z.ai/guides/llm/glm-5.3` — 1M context, 128K output, reasoning effort levels
- `https://docs.z.ai/guides/overview/pricing` — pay-as-you-go pricing
- `https://docs.z.ai/release-notes/new-released` — GLM-5.3 **2026-08-18**, GLM-5.3-Flash **2026-08-26**
- `https://docs.z.ai/scenario-example/develop-tools/claude` — **stale** (GLM-4.7 era); recorded as a
  contradiction, not as a source of fact
- `https://zcode.z.ai/en/docs/welcome`, `…/usage-stats` — ZCode is a desktop ADE, GUI-only statistics
- `https://huggingface.co/api/models?author=zai-org` — open-weight licences and dates

**Secondary / unconfirmed (CLAIMED):**
- `https://github.com/agent-next/zagent` — unofficial GLM terminal agent; **1 star**; flags from its
  README only
- `https://pi.dev/packages/pi-glm-usage` — `unit` value semantics, `~/.pi/agent/auth.json` shape
- Pro ($72) and Max ($160) monthly prices — third-party pricing aggregator only; only Lite's $18 is
  corroborated by Z.ai's own text
