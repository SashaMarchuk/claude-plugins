# ADAPTER-CONTRACT.md — what a platform must do to be orchestrated

**Date:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0).
**Scope:** the contract between the provider-agnostic orchestrator and the agent platforms it drives.
Sources are the fifteen platform profiles and spikes in this directory, plus `00-field-scan.md`.
The orchestrator *landscape* (tools that manage agents) is a different document and is not repeated here.

**Requirements source:** the owner's own voice interview —
`../../round-1/TRANSCRIPT-01.md`, analysed in `../../round-1/ANALYSIS-01.md`. Item codes below
(`R1-06`, `Д7`, …) are that analysis's codes. Instruction **I1** of that analysis is the mandate for
§3 and §7: *"verify these requirements against each platform; where a platform has different limits
or none, raise the divergence as its own question rather than assuming it works"* [182–184].

**Evidence tags:** **VERIFIED** (read in source/docs, or run on this machine) · **CLAIMED**
(vendor/README only) · **UNKNOWN**. Every cell in §1 is traceable to the cited file; where a spike
and its profile disagree, the **spike wins** — it ran the thing.

---

## 0. How to read this

### The ten axes

| | Axis | The owner's requirement behind it |
|---|---|---|
| **A** | Launch — headless and/or visible | R1-11: per-platform config, interactive / headless / hybrid |
| **B** | Identity & resume | R1-06.2, R1-10: state recorded so a run can be resumed, even by hand |
| **C** | Transcript readable live | R1-09: the orchestrator judges progress of the sessions it started |
| **D** | Context — read fullness, trigger compaction, prove it | R1-08: *"повинен бути механізм, який гарантовано робить цю дію"* |
| **E** | Quota — read remaining, know the reset | R1-06.1/2: wait for reset and continue; soft/hard thresholds |
| **F** | Accounts — several per machine, switch per role | R1-07: roles on different accounts, verified before the run starts |
| **G** | Intervention — deliver an instruction, answer a question | R1-11, Д6, Д12: the orchestrator answers AskUserQuestion; stop commands land |
| **H** | Guardrails | R1-02, R1-15: what may run autonomously; the one red-line file |
| **I** | Extensibility | R1-03: run GSD, superpowers, or a fully custom process inside |
| **J** | Operational reality | R1-01, Д3, Д5: a night that finishes without tails |

### The four non-negotiables

The owner named four things the current harness fails at and that a replacement must do
(`plugins/harness/docs/FIELD-NOTES.md` is the evidence he was shown):
**D** (compaction guaranteed from outside), **E** (read capacity before dispatch),
**F** (per-role accounts), **G** (an instruction that provably arrives).
A platform is tier-1 only if all four are **native**.

### The architectural finding that shrinks the work

**The adapter count is smaller than the platform count.** Four of the fifteen names on the owner's
list are *providers*, not platforms — they are another CLI pointed somewhere else by environment:

| Named | What it actually is | Evidence |
|---|---|---|
| GLM / Z.ai | Claude Code (or pi/codex/opencode) + 3 env vars. **No adapter needed** — a provider object plus `env_for(provider)` on the existing driver | `glm-spike.md` §12 |
| DeepSeek (lane A) | Same shape; `/user/balance` replaces the usage endpoint | `deepseek-spike.md` §12.3 |
| "something from Xiaomi" (as a model) | Same shape, `…/anthropic` base URL — **but Xiaomi also ships a real CLI**, see below | `xiaomi-mimo.md` §0, §K |
| Kimi (as an endpoint) | Same shape — **but Moonshot also ships a real CLI** (`kimi-cli` 2.0.2) | `kimi.md`, `00-field-scan.md` §3 |

`00-field-scan.md` §2 concluded Xiaomi was *only* an env-var trick. **That is wrong**
(`xiaomi-mimo.md` §0): Xiaomi ships **MiMoCode** (`@mimo-ai/cli`, binary `mimo`, MIT, an OpenCode
fork) whose HTTP control plane beats Claude Code on axes C, D and G. Both readings are live: MiMo is
*both* a provider lane and a platform, and they score differently.

So the design has **two config objects, not one**:

```
Provider = { base_url, auth_ref, model, small_model, context_window,
             capacity_model: Window|Credit|Unknown, monitor_endpoint?, concurrency_ceiling? }
Platform = { adapter_id, binary, transport, home_env, capabilities{} }
Lane     = Platform × Provider × Account × Role
```

A run is a set of **lanes**. Everything below is about the `Platform` half.

---

## 1. The capability matrix

`native` = one documented call or flag. `emulated` = the adapter must add glue the platform does not
provide. `impossible` = no honest implementation exists. `unknown` = not established in this pass.
Split into two tables for width.

### Table 1 — axes A–E (launch, identity, transcript, context, quota)

| Platform | A launch | B identity | C transcript | D context | E quota |
|---|---|---|---|---|---|
| **Claude Code** | native ×2 | native (`--session-id`) | native JSONL | **native** (piped) | **native** (3 ways) |
| **Codex CLI** | native | emulated (id minted) | native JSONL+sqlite | **native** | **native** (+reset credit) |
| **Droid** | native | native (client names id) | native | **native** | emulated (undocumented route) |
| **Kimi Code** | native | emulated (2-call tag) | native ×3 | **native** | **native** (windows+reset) |
| **Copilot CLI** | native | native | native | **native** (via prompt) | **native** (+resetDate) |
| **GLM** *(provider)* | driver's | driver's | driver's | driver's | **native** (% per window) |
| **DeepSeek** *(API lane)* | driver's | driver's | driver's | driver's | native (credit, **no reset**) |
| **DeepSeek** *(`dsh` ACP)* | native, no TUI | emulated | native | read native · trigger **impossible** | native (normalised) |
| **OpenCode** | native (HTTP) | **native** (client names id) | native (SSE+store) | emulated read · v1 trigger | **impossible** |
| **MiMoCode** | native | emulated | native (SQLite+SQL) | **native, best in scan** | **impossible** |
| **Qwen Code** | native ×3 shapes | native | native | **native ×3 (webhook proof)** | **impossible** |
| **pi** | native (`--mode rpc`) | **native, names id first** | native (JSONL tree) | **native (3 proofs)** | **impossible** |
| **Amp** | native +remote | emulated (read from line 1) | emulated (no file) | read native · trigger **impossible** | **impossible** |
| **Gemini CLI** | native (`-p`/`-i`/ACP) | native, fragile | native | read native · trigger **impossible** | emulated (OAuth path only) |
| **Cursor CLI** | native | native, no listing | native NDJSON | read native *(after upgrade)* · trigger **impossible** | **impossible** (personal plan) |
| **Aider** | native `--message` | emulated (anchors) | emulated (prose) | emulated (`/tokens`+`/clear`) | **impossible** |

### Table 2 — axes F–J (accounts, intervention, guardrails, extensibility, ops)

| Platform | F accounts | G intervention | H guardrails | I extensibility | J overnight today |
|---|---|---|---|---|---|
| **Claude Code** | **native** (`CLAUDE_CONFIG_DIR`) | **native** (piped) | native | native (GSD lives here) | **yes, unqualified** |
| **Codex CLI** | **native** (`CODEX_HOME`, no keychain) | **native** (queue+steer+10 RPCs) | native (sandbox) | native | yes, after 3 fixes |
| **Droid** | **native** (+`DISABLE_KEYRING`) | **native** (ack + typed asks) | native | native (ports from CC) | yes |
| **Kimi Code** | **native** (`KIMI_CODE_HOME`) | **native** (must confirm downstream) | **weak — no sandbox, hooks fail open** | native | yes, pinned |
| **Copilot CLI** | **native, best** (per-session token) | **native** (messageId + choices) | native (fail-closed hazard) | native (reads `.claude/skills`) | **no — account `no_access`** |
| **GLM** *(provider)* | **native** (3 env vars) | driver's | driver's | driver's | yes, ≤ plan concurrency |
| **DeepSeek** *(API lane)* | **native** (1 env var) | driver's | driver's | driver's | **yes, zero engineering** |
| **DeepSeek** *(`dsh` ACP)* | native | permission native · instruction **impossible mid-prompt** · question **impossible** | patch required | plugin-everything | no (RC, unaudited) |
| **OpenCode** | native per provider; **no Anthropic OAuth** | **native** (`admittedSeq`) | native (silently permissive on bad JSON) | strong | yes, over HTTP only |
| **MiMoCode** | native per instance | **native, best in scan** (+question channel) | emulated posture | native | yes, key must be re-minted |
| **Qwen Code** | native (`QWEN_HOME`) | **native ×3, route by kind** | native (Seatbelt) | **richest in field** | yes |
| **pi** | native (`PI_CODING_AGENT_DIR`) | **native, reference impl** | native-ish, no sandbox | skills yes · **MCP no** | yes, with sidecar |
| **Amp** | **native, best** (one env var) | **native ×2** (steer + veto) | capable, defaults unsafe | strong | yes, auto-update off |
| **Gemini CLI** | native (`GEMINI_CLI_HOME`) | **impossible** headless · native ACP | native, silently downgrades | native | conditional on account |
| **Cursor CLI** | native (API key) · browser-login **impossible** | **native** (steer reports delivery) | **best in field** | native | **no — install 372 days old** |
| **Aider** | **native** (dir per role) | emulated (tmux, works) | weak | **none** | yes, as a leaf executor |

### The four non-negotiables, isolated

| Platform | D compact+proof | E read capacity | F accounts | G intervention | Non-negotiables met |
|---|---|---|---|---|---|
| Claude Code | ✅ | ✅ | ✅ | ✅ | **4/4** |
| Codex CLI | ✅ | ✅ | ✅ | ✅ | **4/4** |
| Copilot CLI | ✅ | ✅ | ✅ | ✅ | **4/4** (no entitlement) |
| Kimi Code | ✅ | ✅ | ✅ | ✅ | **4/4** (2-day-old API) |
| Droid | ✅ | ⚠ undocumented | ✅ | ✅ | 3.5/4 |
| GLM lane | driver's | ✅ | ✅ | driver's | 4/4 *through the driver* |
| Qwen Code | ✅ | ❌ | ✅ | ✅ | 3/4 |
| MiMoCode | ✅ | ❌ | ✅ | ✅ | 3/4 |
| pi | ✅ | ❌ | ✅ | ✅ | 3/4 |
| OpenCode | ⚠ v1 only | ❌ | ⚠ no CC OAuth | ✅ | 2.5/4 |
| DeepSeek `dsh` | ❌ | ✅ | ✅ | ⚠ partial | 2.5/4 |
| Cursor CLI | ❌ | ❌ | ⚠ key only | ✅ | 1.5/4 |
| Gemini CLI | ❌ | ⚠ path-dependent | ✅ | ⚠ ACP only | 1.5/4 |
| Amp | ❌ | ❌ | ✅ | ✅ | 2/4 |
| Aider | ⚠ emulated | ❌ | ✅ | ⚠ emulated | 1/4 |

---

## 2. The adapter interface

One transport class per platform, one object per lane. Seventeen operations. **Twelve are REQUIRED
for tier-1**; five are optional and have a defined degradation in §3.

### 2.0 `capabilities() → CapabilityMap` — REQUIRED, and it comes first

```
capabilities(): { [axis in A..J]: "native" | "emulated" | "impossible" | "unknown" }
              & { quotaModel: "Window" | "Credit" | "None",
                  idAssignment: "client" | "server" | "none",
                  attachable: bool, sandbox: bool }
```

- **Inputs:** none. Static per adapter version + platform version.
- **Outputs:** the map above. Must be derivable **without** a network call or a model token.
- **Contract:** the orchestrator plans the run against this map and **asks the owner a question for
  every `impossible` that a configured requirement depends on** (§3, §7). An adapter that reports
  `native` and then degrades at 03:00 is the single worst failure this contract exists to prevent.
- **Never:** report `native` for a capability whose only implementation is a regex over English prose.

This operation is the reason the interface exists. Everything else is mechanics.

### 2.1 Lifecycle

| Op | Signature | Contract | Tier-1 |
|---|---|---|---|
| `preflight` | `(account) → {ready, version, accountId, models[], warnings[]}` | Must prove **which account** this spawn would use, not just that a binary exists. Read-only, zero model tokens, ≤10 s. Must fail loudly on a stale/dead credential. | **REQUIRED** |
| `launchHeadless` | `(ticket, lane, sessionId?) → Handle` | Non-interactive, structured output, **stdin closed or held by the adapter — never inherited**. Idempotent on `sessionId` where the platform assigns ids client-side. External wall-clock timeout mandatory. | **REQUIRED** |
| `launchAttached` | `(ticket, lane) → Handle` | A terminal the owner can type into. May be `impossible`. | optional |
| `resume` | `(sessionRef) → Handle` | Must resume **exactly** or declare itself lossy. Idempotent: resuming a live session returns the live handle, never a fork. | **REQUIRED** |
| `stop` | `(handle, "soft"\|"hard") → TeardownReport` | `soft` = at the next step boundary (the definition of "step" is the user's, R1-08/Д12); `hard` = now. Must assert the process is gone and report orphans. Idempotent. **Must stop only what this adapter started** (R1-16, Д3). | **REQUIRED** |

### 2.2 Observation

| Op | Signature | Contract | Tier-1 |
|---|---|---|---|
| `status` | `(handle) → "working"\|"waitingOnHuman"\|"waitingOnTool"\|"finished"\|"failed"\|"dead"` | **"waiting on a human" is a distinct state from "working"** — conflating them is how an overnight run dies quietly (`qwen-code-spike.md`). Must never block. ≤2 s. | **REQUIRED** |
| `transcript` | `(handle, cursor) → {events[], cursor'}` | Append-only, resumable from `cursor` across a process restart. Cursors may be sparse; treat as opaque. Must work for a session the adapter did **not** spawn, or declare `emulated`. | **REQUIRED** |
| `readContext` | `(handle) → {used, window, pct, isEstimated} \| "unknown"` | Must carry `isEstimated`. `missing ≠ zero`. Zero model tokens. | **REQUIRED** |
| `costMeter` | `(handle) → {spend, unit}` | Local ledger; drifts against off-machine usage and must say so. | optional |

### 2.3 The four non-negotiables

| Op | Signature | Contract | Tier-1 |
|---|---|---|---|
| `compact` | `(handle, instruction?) → Proof \| "unsupported"` | **`Proof` is mandatory** — a typed event, a durable transcript entry, or a measured drop in used tokens. Returning success without proof is forbidden. If the platform mints a **successor session id**, the adapter must remap ticket→session atomically before returning. Idempotent: a second call inside one turn is a no-op, not a second compaction. | **REQUIRED** |
| `readCapacity` | `(account) → Window{used%, resetAt} \| Credit{remaining, unit} \| "unknown"` | Two shapes, never one. **Cache ≥60 min per account**; never poll per session (it earns a 429 exactly when quota matters). Must never be inferred from an exit code. | **REQUIRED** |
| `detectLimitHit` | `(event) → LimitHit{kind: "window"\|"credit"\|"rate", resetAt?} \| null` | The in-band brake. Required even when `readCapacity` is native, because prediction and reaction fail differently. | **REQUIRED** |
| `selectAccount` | `(lane) → SpawnEnv` | Returns environment only — **never mutates the owner's config, keychain or home**. The caller must verify the account **after** launch from the platform's own report, not from the variable it set. Changing a *running* session's account is `impossible` on all fifteen platforms; the adapter must expose that as `handoff`, not hide it. | **REQUIRED** |
| `send` | `(handle, text, "steer"\|"queue") → Ack{status, messageId}` | `Ack` is a **state machine**, not a boolean: `accepted` ≠ `delivered` ≠ `processed`. `accepted` must never be reported as `delivered`. Must expose stranded/queued text so a `stop` can hand it back (only pi's `clear_queue` does this natively). Idempotent on a caller-supplied `messageId` where the platform allows one. | **REQUIRED** |
| `answer` | `(handle, requestId, decision) → void` | Answers the session's *own* question or permission prompt over a correlated channel (R1-11: *"якщо він раптом використовує ask user question, то оркестратор може відповідати"*). Must echo an **offered** option id, never free text. Must log every declined question — silent decline is the documented killer on Droid. | **REQUIRED** |

### 2.4 Invariants every adapter must honour

These are not style notes. Each one is a verified silent-failure mode from a specific spike.

1. **Never branch on the exit code.** Aider `main.py:1133` returns 0 on auth failure, rate limit and
   success alike (`aider-spike.md`). pi `--mode json` exits 0 on provider failure (`pi-spike.md` §15).
   GLM exits 0 on quota exhaustion *with* `subtype:"success"` (`glm-spike.md` §12). MiMoCode's exit
   code is always 0 (`xiaomi-mimo-spike.md` §2).
2. **Never trust HTTP 200 or a `success` string.** Gate GLM's quota poll on `.success == true`;
   gate Claude-family completion on `is_error == false && terminal_reason == "completed"`.
3. **Always close or own stdin.** Codex hangs all night without `< /dev/null`
   (`codex-cli-spike.md`); MiMoCode hangs forever (`xiaomi-mimo-spike.md` §11b); Aider exits
   instantly and silently *with* stdin closed and needs a pty instead (`aider-spike.md`).
4. **Always impose an external wall-clock timeout.** `opencode run --attach --session --dir` hangs
   with zero bytes on stdout, stderr and the server log (`opencode-spike.md`, reproduced twice).
5. **Always pin the version and disable auto-update.** Amp shipped five releases in fifteen hours
   and updates itself by default (`amp.md` §J). Copilot: 835 versions in twelve months. Kimi 2.0.2
   was published the morning of the research.
6. **Always pin the model explicitly.** Inheriting the owner's `~/.codex/config.toml`
   (`model = "gpt-6-astra"`) produced a 100 %-failing run (`codex-cli-spike.md`).
7. **Keep stdout and stderr separate.** GLM always writes `[claude-code:unrecognized_model]` to
   stderr; Cursor writes a 502-byte ANSI splash to *stdout* (`cursor-cli-spike.md`).
8. **Union the roster across accounts.** A roster read under one account shows half the fleet
   (`claude-code-spike.md`).
9. **Re-attach permission and question handlers on every resume**, not just on create.
10. **Assert teardown by process, not by the command's word.** `cursor-agent worker kill` reports
    success and leaves the process at 100 % CPU (`cursor-cli-spike.md`). This is the
    FIELD-NOTES "reports success and does nothing" class, alive in a second platform.

---

## 3. Graceful degradation — and the requirement that silently stops holding

For each axis: the ladder the orchestrator walks down, **the owner requirement that quietly becomes
false**, and the question that must therefore be asked out loud (Ukrainian wording in §7).

### A — Launch

**Ladder:** headless+structured → headless+text (parse) → visible terminal driven by a multiplexer →
executor-only.
**Stops holding:** R1-11's *hybrid* mode. On Gemini CLI, ACP **replaces** the TUI — supervision and
human takeover are mutually exclusive *per process* (`gemini-cli-spike.md` §14). On DeepSeek `dsh`
and Amp there is no attachable local pane at all.
**Orchestrator behaviour:** declare per lane whether takeover is possible; if not, takeover is a
**handoff** (stop → relaunch attached → resume), which costs one restart and must be visible in the
run log, not silent.

### B — Identity & resume

**Ladder:** client names the id before launch (Claude Code, pi, Droid, OpenCode, Qwen) → server mints
and the adapter records it atomically (Codex, Kimi, Amp, MiMoCode) → no id at all, orchestrator
injects anchors into the work product (Aider).
**Stops holding:** R1-06.2, *"в нас в реєстрі має записуватись кожен стан … щоб було відновити процес
і продовжити, навіть руками."* Where the server mints the id there is a **crash window** between
launch and first record. On Gemini CLI a session with **no completed model turn is deleted and is
unresumable** — an early failure leaves no recovery point at all.
**Orchestrator behaviour:** write the ticket→session mapping before the first token where possible;
otherwise treat the first N seconds of a task as "unrecoverable by id" and recover by **re-dispatch**,
not by resume. Aider's resume is lossy by construction (5 turns kept, 48 tool lines dropped) — on
Aider, "resume" means "re-run with a handoff file".

### C — Transcript

**Ladder:** durable file/DB the supervisor tails (Claude Code, Codex, Qwen, MiMoCode, pi) →
server-side API polled (Amp) → the pipe you are holding, and nothing if you drop it (Amp, `dsh`) →
prose scraping (Aider).
**Stops holding:** R1-10's recovery source *"попередні сесії та їх транскрипти"*, and R1-09's
progress judgement. When the transcript exists only on the pipe, **a dead supervisor destroys the
evidence** — which collides directly with R1-10's requirement that the orchestrator's own death be
survivable.
**Orchestrator behaviour:** where the transcript is pipe-only, the adapter must persist it itself
(tee to disk under the run directory) and say so in `capabilities()`.

### D — Context *(non-negotiable)*

**Ladder:** external trigger + typed proof (Codex, Droid, Kimi, Qwen, MiMoCode, pi, Copilot, Claude
Code piped) → trigger by injecting `/compact` as a user message + proof from the transcript →
**pre-commit at launch** (a threshold env var set before the run: Claude Code `--autocompact`, Gemini
`model.compressionThreshold`, `dsh` `thresholdRatio`) → **close-and-reseed**: summarise, open a new
session with the summary, map old→new in the ticket ledger.
**Stops holding:** R1-08 in its strongest form — *"повинен бути механізм, який гарантовано робить цю
дію."* On Amp, Gemini CLI, Cursor and `dsh` there is **no external trigger at all**, so hard mode
("stop now, compact, continue") is not implementable; only soft mode via a pre-set threshold, decided
before the run and unchangeable during it. That breaks the cross-cutting rule that a change made
*during* a run must be picked up (Д7, Д12).
**Orchestrator behaviour:** `close-and-reseed` is the platform-independent fallback and should be
built once, centrally (`deepseek-spike.md` §12.2 makes the same argument). It changes ticket→session
from one-to-one to **one-to-many**, so the ledger must be a lineage, not a field. Where compaction is
proof-less, the orchestrator must treat "compacted" as **unproven** and log it as such.

### E — Quota *(non-negotiable, and the axis that splits the field)*

**Ladder:** window with `resetAt` (Claude Code, Codex, Kimi, Copilot, GLM, Gemini-on-Code-Assist) →
credit balance with no reset (DeepSeek, Amp) → in-band hit with a reset time in the error →
in-band hit with **no** reset time → local ledger + computed clock (Qwen, MiMoCode, Aider) →
nothing (pi).
**Stops holding:** R1-06.1 in full. *"Дочекатись рестарту ліміту і продовжити"* is **not
implementable** on seven of the fifteen platforms, because there is nothing to wait for: the model is
money, not time. The soft/hard threshold ladder of R1-06.2 (*"при скількох відсотках"*) needs a
percentage that does not exist on a credit model.
**Orchestrator behaviour:** `Capacity = Window | Credit | Unknown` must be a first-class type with a
policy per variant. `Window` → pause until `resetAt`, auto-resume. `Credit` → hard spend ceiling,
stop, **notify a human** (Д5's channel), no auto-resume. `Unknown` → local ledger, conservative
ceiling, react to `detectLimitHit` only, and **never give that lane the role whose capacity the
orchestrator must predict** (`xiaomi-mimo-spike.md` states this as its tier-2 contract).
**This is the single biggest divergence in the field and the first thing §7 asks about.**

### F — Accounts *(non-negotiable)*

**Ladder:** per-process env var, no shared state (Amp `AMP_API_KEY`, Aider dir-per-role, GLM/DeepSeek
3 vars, Codex `CODEX_HOME`, Droid `FACTORY_HOME_OVERRIDE`) → per-process home + a daemon each
(Qwen, Kimi, MiMoCode: one server per account) → config dir + OS keychain (Claude Code) →
**one account per machine** (Cursor browser-login: the keychain namespace is the hard-coded literal
`"cursor"` and `CURSOR_CONFIG_DIR` does not scope it).
**Stops holding:** R1-07's *"ролі можуть сидіти на різних акаунтах"* — on Cursor with a browser login
this is impossible and only API keys work; on OpenCode a **Claude subscription cannot
drive a session at all** (no Anthropic OAuth, API key only), which is a bill, not an inconvenience.
And on **every** platform, changing a *running* session's account is impossible — so R1-07's **hard**
account change ("applies now, stops current work") is always a stop-and-relaunch with a context
re-seed, never an in-place switch.
**Orchestrator behaviour:** verify the account **after** launch from the platform's own report
(`initialize.account.email`, `auth_changed`, `apiKeySource=="env"`, `presentVar`) — R1-07 demands the
switch be *proven working before a run starts*. On macOS, Claude Code may raise a **Keychain GUI
dialog** on an account that has never been granted access — an unattended run blocks on a dialog
nobody sees (`00-field-scan.md` §4). Codex, Droid, Kimi and Qwen have no keychain and cannot fail this
way; that is a real reason to prefer them for unattended lanes.

### G — Intervention *(non-negotiable)*

**Ladder:** correlated request/response with a delivery receipt (pi RPC, Codex `queue`, OpenCode
`admittedSeq`, Copilot `messageId`, Droid, MiMoCode, Cursor `steer`) → accepted-only ack that must be
confirmed downstream (Kimi: a 200 means *accepted*, never *ran*) → keystrokes into a multiplexer with
an echoed marker (Aider, pi TUI, Qwen TUI) → **nothing** (Gemini CLI headless: a mid-run prompt
**aborts the turn**; `dsh` ACP: impossible mid-prompt).
**Stops holding:** Д12's stop commands and Д6's live question channel. If an instruction cannot be
delivered mid-turn, `stop-hard` degrades to "kill the process", and Д6's *"враховує відповіді наживо"*
becomes "at the next task boundary".
**Answering the session's own question** degrades separately and worse: native typed channels exist on
Copilot (`choices`), MiMoCode (a *question* channel distinct from *permission*), Qwen, Droid, Kimi,
Cursor ACP, pi, OpenCode. Where it is absent, the only safe unattended posture is **prevent the
question**: allow/deny lists plus a permissive mode. Claude Code's `defer` is print-mode only; a `--bg`
session cannot be answered at all. On `dsh` SDK lane there is no answerer mounted, so it can only run
`danger-full-access` — which collides head-on with R1-02 and R1-15.

### H — Guardrails

**Ladder:** OS sandbox + typed permissions + hooks (Cursor best-in-field, Qwen Seatbelt, Codex,
Claude Code) → allow/deny lists + hooks (most) → **nothing** (Kimi: no container, no seccomp, no
filesystem jail, and hooks **fail open**, so a crashed guard permits; pi: no sandbox).
**Stops holding:** R1-15's red-line file is *"текстово писані правила … без окремої обов'язкової
процедури"* — a prompt-level rule with no enforcement machinery. On a sandbox-less platform that is
the **only** barrier, and a model that ignores it has nothing beneath it. R1-02's "what may be
delegated" also loses its floor.
**Orchestrator behaviour:** where `sandbox: false`, confine the lane to a disposable git worktree
(Д4's default recommendation is already this), use static deny rules for destructive commands, and
raise it as an explicit question rather than assuming the text file suffices.

### I — Extensibility

**Ladder:** MCP + skills + subagents + hooks (Qwen richest; Droid, Codex, Copilot, Claude Code,
OpenCode strong) → skills only, **no MCP** (pi) → **none** (Aider).
**Stops holding:** R1-03 — running GSD or another marketplace process *inside* the lane. A
subagent-heavy engine needs subagents; Aider has none, so it can only ever be a **leaf executor**
inside someone else's process, never the host of one. Copilot reads `.claude/skills/` and `CLAUDE.md`
natively but whether the GSD skills *execute* there is **UNKNOWN** and is the single highest-value
open experiment in that file.

### J — Operational reality

**Ladder:** installed, current, authenticated → installed but stale → not installed → installed and
**entitled to nothing**.
**Today, on this machine:** only `claude` (2.1.278, current), `codex` (0.152.0, three releases
behind) and `cursor-agent` (**372 days old, not logged in**) exist at all. Everything else is a fresh
install — 145 MB (OpenCode, Copilot), 200 MB (Gemini), 748 MB and 227 packages (Aider).
**Stops holding:** R1-01's *"ран зупинився, і це не означає, що це помилка в нас"* cuts both ways —
a platform that was never installed cannot be blamed for a failed night, but it also cannot be
scheduled. Preflight must refuse to dispatch to a lane that has not been proven **today**.

---

## 4. Support tiers

**Tier 1** — all four non-negotiables native; can run the owner's queue overnight with no qualifier.
**Tier 2** — workable with emulation the orchestrator owns; at least one non-negotiable degrades.
**Tier 3** — executor only: it can do a task, it cannot be supervised.
**Unusable today** — a real blocker that is not an engineering problem.

| Platform | Tier | The single reason | What would move it up |
|---|---|---|---|
| **Claude Code** | **1** | The only platform answering all four non-negotiables with documented, id-correlated surfaces, and the owner's multi-account machinery already exists (a profile switcher) | — (fix: pre-grant Keychain access per account so no GUI dialog can block a night) |
| **Codex CLI** | **1**\* | Every axis native and ten of eleven recipes executed here today; better than Claude Code on E (quota resettable from banked credits) and G | The standalone install (`chatgpt.com/codex/install.sh`) — it would restore the daemon and make the supervisor durable. Highest-value single experiment in the whole scan |
| **Droid** | **1**\* | 12 of 13 capabilities native, and it **downgrades to Droid Core instead of halting** — the only platform that degrades rather than stops | A supported quota endpoint; `/api/billing/limits` is undocumented and behind a contract test |
| **Kimi Code** | **1**\* | Every non-negotiable answered by an endpoint called on this machine; quota as floats with reset timestamps | Maturity. 2.0.2 shipped the morning of research; the control plane self-labels *experimental*. Pin + diff `/openapi.json` in CI, and add a sandbox |
| **GLM** *(provider lane)* | **1 technical / 2 practical** | Needs no adapter — a provider object plus `env_for()`. Best quota API in the field | The **contractual** ceiling: Lite 1 / Pro 1–2 / Max 2+ concurrent sessions, three violations → ban. A fleet of six runs straight at it |
| **DeepSeek** *(API lane)* | **1** | Zero engineering: three env vars behind the existing driver, and the quota model gets simpler (credit, no window) | — (it is a cost lane, not an orchestration surface) |
| **Qwen Code** | **2** | Tier-1 on nine axes — and the only platform with a **visible terminal the owner types into that a supervisor can still drive** — but quota is structurally absent (upstream request closed) | A remaining-capacity API. Nothing else is missing |
| **MiMoCode** | **2** | The most supervisable executor in the scan (best D, best G, a *question* channel nothing else has) capped by one axis: no way to read remaining Token Plan credit | A usage endpoint from Xiaomi. Also: **the owner's stored `tp-…` key is dead (401 today)** and must be re-minted before anything runs |
| **pi** | **2** | Names the session before it exists and is the reference implementation for axis G — but quota is a *design position*, not a gap: pi owns no account | Nothing pi can do. Run it on token-plan providers with a spend ceiling instead of a quota budget |
| **OpenCode** | **2** | Client-assigned ids, exactly-once replay from one integer, acknowledged delivery — but quota is VERIFIED-absent across 1,019 OpenAPI key names, and `compact`/`wait` are **503** in the shipped build | v2 `compact` implemented, and Anthropic OAuth support (today the owner's Max subscription cannot drive it) |
| **Amp** | **2** | Best account isolation in the scan and two intervention channels — but **no external compaction trigger and no quota window at all** | Structural. Amp's model is money and remote orbs; it would need a different product |
| **Gemini CLI** | **2, conditional** | Over ACP it answers intervention and permission-answering well, but quota is unreadable on the API-key path the owner would most likely hold, and compaction cannot be triggered in any mode | Settle the account question first: consumer access ended **2026-06-18**; the successor is **Antigravity CLI (`agy`)**, whose flags are **UNKNOWN** — the highest-priority gap in `00-field-scan.md` |
| **DeepSeek `dsh`** | **2 (ACP) / 3 (SDK)** | ACP clears eight of eleven; the SDK lane mounts **no permission answerer**, so it can only run `danger-full-access` | A stable minor. Today: a 0.1.x RC from a five-week-old repo whose README promises breaking changes and whose `SAFETY.md` says it is not production-ready |
| **Aider** | **2 with tmux / 3 without** | Excellent per-role accounts and a working keystroke-plus-marker intervention — but no MCP, no subagents, lossy resume, no quota, and **zero commits since 2026-05-22** | Nothing. Use it as a frozen, disposable leaf executor judged by git |
| **Cursor CLI** | **Unusable today** *(tier-2 after upgrade)* | The installed build is **372 days old and not logged in**: no statusline, no hooks, no `approvalMode`, no sandbox, no ACP — leaving only `--force` (unrestricted) or a run that applies nothing | Install `2026.09.18`, authenticate with an API key, re-run the spike. Even then quota is unreadable on a personal plan, so it can never be a *scheduled* citizen |
| **Copilot CLI** | **Unusable today** *(tier-1 on capability)* | `access_type_sku: "no_access"` on this account. On capability it is the only platform answering **all eleven** recipes with a documented mechanism | One checkout — `can_signup_for_limited: true` |

---

## 5. The first three adapters to build

### 1. Claude Code — because it is the only lane that can run *tonight*

It is installed, current (2.1.278), authenticated through the profile switcher, and it is where GSD
and the owner's skills already live (R1-03, Д1). All four non-negotiables are native in the piped
shape, and the two "real gaps" in its profile are design choices, not blockers: run **everything
piped** and treat owner takeover as a handoff (`claude-code-spike.md`).

**Unlocks:** the whole orchestrator, end to end, on one platform — which is the only way the
adapter interface gets tested before it is generalised.
**Build order inside it:** the stdin control client (§2, §8, §9 of the spike — the only genuinely
hard part), then the statusLine tee (closes D and E for attached sessions, but it edits the owner's
`settings.json` and needs his explicit yes), then the account-union roster (twenty lines, and without
it the supervisor is blind to most of its own fleet).
**Do not forget:** `--verbose` is mandatory with `-p --output-format stream-json` or the process never
starts; `CLAUDE_CONFIG_DIR` must be pinned in every spawn or a daemon silently uses the wrong account.

### 2. Codex CLI — because it proves the interface is not Claude-shaped

Installed (0.152.0), a different vendor, a different protocol, a different account model — and
tier-1 on every axis. It is the honest test of whether `PlatformAdapter` is an abstraction or a
Claude Code wrapper with extra steps. It also removes the Keychain-dialog class of overnight failure
entirely (no keychain), and it is the only platform where a **hit limit can be reset** from banked
credits (`account/rateLimitResetCredit/consume`, 2 banked, redemption **UNKNOWN**).

**Unlocks:** a separate account (if the user configures one) for R1-07's role split, a supervisor lane that is independent of
the executor lane (R1-10's health check on a separate account, if the user configures one), and a real answer to "what does
`Ack` mean" — Codex's `codex queue` gives a receipt at enqueue and **proves delivery by the row
disappearing**, which is the cleanest delivery semantics in the field.
**Do not forget:** pin `-m`, pin `-s`, pin `-c approval_policy`, and redirect stdin from `/dev/null`
on every spawn. Without the first, the run fails 100 %; without the last, it hangs all night.

### 3. A *provider lane* — GLM or DeepSeek behind the Claude Code driver — before any third CLI

This is the highest value-per-hour move in the entire scan and it is **a configuration change, not a
feature** (`glm-spike.md` §12, `deepseek-spike.md` §12.3). It requires one new method on the adapter
built in step 1 — `env_for(provider)` — plus one small provider-specific quota reader.

**Unlocks:** the `Provider` ↔ `Platform` split as *working code* rather than a diagram; cost
asymmetry as a real scheduling input (GLM-5.3-Flash at $0.15/$0.50 per Mtok against frontier pricing
is the difference between "runs all night" and "burns the weekly limit by 02:00"); and the
`Capacity = Window | Credit` type, exercised against two providers that genuinely differ.

**Then, in order, and only then:** **Droid** (tier-1, client-assigned ids, and the only platform that
*degrades instead of halting*), **Qwen Code** (the only drivable visible terminal — the answer to
R1-11's hybrid mode), **MiMoCode or pi** (the best D/G implementations, worth building against even
if never adopted). **Copilot CLI** is the adapter interface's best *design reference* — build against
its unauthenticated surface (nine of eleven recipes are verifiable without spending a credit) and make
the entitlement decision separately.

---

## 6. Cross-platform hazards

Things that only bite when one run mixes platforms.

### 6.1 Quota semantics do not commute
Three incompatible models coexist: **rolling window** with a reset time (Claude Code 5 h + 7 d,
Codex, Kimi, Copilot, GLM), **credit balance** with no reset at all (DeepSeek, Amp, Cursor's monthly
cycle), and **nothing** (pi, Qwen, MiMoCode, OpenCode, Aider). A scheduler written against "pause
until `resetAt`" will **wait forever** on a credit platform, and one written against "stop at 90 %"
has no percentage to read on a credit platform. `Capacity` must be a sum type with a policy per
variant, decided once, centrally. Worse: quota is pooled differently — Kimi pools **all devices and
API keys into one account pool**, so two lanes on one Kimi account do not double throughput, they
halve each other.

### 6.2 Transcript formats share no shape
JSONL-per-session (Claude Code, Codex, pi, Qwen, Gemini), SQLite (MiMoCode, Codex's projections,
Cursor), server-side API only (Amp), an SSE stream plus a store (OpenCode, Kimi), and **markdown
prose** (Aider). A supervisor that judges progress (R1-09) needs one normalised event vocabulary —
`turn_started / tool_call / waiting_on_human / compacted / turn_completed / failed` — produced by each
adapter. Do not let the orchestrator read platform-native records directly; that is how one platform's
schema change breaks the run loop for all of them.

### 6.3 Session-id collisions and shapes
UUIDv4 (Claude Code, Cursor, Gemini), ULID-ish (Codex `01a0b9dd-…`, MiMoCode), prefixed strings
(Amp `T-…`, OpenCode `ses_…`), and **none at all** (Aider). Three platforms let the client name the
id; five mint it server-side. **Never use the platform id as the orchestrator's primary key** — key
on `ticket_id`, store `(platform, account, session_id)` as an attribute, and make it a **list**,
because close-and-reseed (§3 D) turns one ticket into many sessions. pi will *silently fork* a session
if `--session-id` is used from a drifted cwd; Codex records a custom client's thread as
`source:"vscode"`, so ownership cannot be filtered by source and must be filtered by name prefix.

### 6.4 Permission defaults differ, and the unsafe ones are silent
OpenCode starts **permissive** when `OPENCODE_PERMISSION` is malformed JSON. Gemini CLI silently
downgrades `yolo` to `default` in an untrusted folder — denying every tool while looking fine.
Copilot has a **fail-closed policy path** that can strip the permission posture an unattended run
depends on. Amp allows `mcp__*`, Slack, Gmail, Drive and X by default. Kimi and pi have **no sandbox
at all**. MiMoCode's `permission/ask-timeout` defaults to `null` — *wait forever*. The orchestrator
must **assert the posture after launch on every platform**, from the platform's own report, and treat
the assertion as part of Д4's "verify the environment before the run".

### 6.5 Cost asymmetry is larger than scheduling asymmetry
Droid's credit multipliers span **150×** between its cheapest and dearest model — model routing, not
run scheduling, is the dominant cost control there. GLM-5.3-Flash ($0.15 in / $0.50 out per Mtok)
undercuts MiMo-V2.5-Pro ($0.435 / $0.87) roughly 3× on input. pi on an Anthropic subscription bills
**per token as extra usage**, so "run until the limit" has no natural stopping point — it just costs
money. Amp's model spend is uncapped by default with no window to hide behind, and a remote orb keeps
billing after a local `stop` until Amp's own pause timer fires. Д8's "use a cheap model to watch for
ticket changes" is right, and should be a **per-role model+provider pin**, not a per-lane one.

### 6.6 Model-capability asymmetry for the same role
The same role text produces different behaviour per lane: context windows range from ~200 K to
**1 M** (MiMo, Gemini, GLM with the right env), and GLM will quietly compact at 200 K if
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` disagrees with the model id. Reasoning-effort and thinking budgets
are per-platform knobs with no common units. A GSD-style engine that assumes subagents will simply
**not run** on Aider and will run under a different concurrency ceiling on GLM. Role definitions must
carry a **minimum capability** (`needs: [subagents, mcp, 200k_context]`) that preflight checks
against `capabilities()` before the lane is assigned.

### 6.7 Two orchestrators is the failure R1-10 names explicitly
*"якщо раптом одночасно два якісь оркестратори працюють, то це не окей"* [300–302]. Mixing platforms
multiplies the ways this happens: Codex has `~/.codex/cross-instance-locks/` and a process manager;
Qwen has a **fenced writer lease** with no programmatic recovery (on `session_writer_conflict` you
must fork to a fresh id, never retry); OpenCode and Kimi run **one server per account**, so "is the
orchestrator alive" is a different question per lane. The single-orchestrator invariant must be
enforced by the orchestrator's own lock file and log, not by any platform's.

### 6.8 Auto-update is the most under-rated overnight killer
Amp: five releases in fifteen hours, `updates.mode: "auto"` and `runner.autoUpdate: true` by default.
Copilot: 835 versions in twelve months. Kimi: auto-update on by default, staging binaries in the
background. Qwen, Droid, MiMoCode, pi, opencode: all ship on a daily-to-weekly cadence. A run that
starts on one flag surface and finishes on another is indistinguishable from a bug in the
orchestrator. **Pin the version in preflight and record it in the run log** — on every platform, in
every process.

---

## 7. Open questions for the owner — round 2

Per instruction **I1**, each of these is a requirement that a platform makes impossible or expensive.
Plain language, ready to paste.

### Ліміти й квоти (вісь E — найбільший розрив у полі)

1. Сім із п'ятнадцяти платформ **не дають прочитати залишок ліміту взагалі** (pi, Qwen, MiMoCode, OpenCode, Aider, Cursor на персональному плані, Amp). Твоє правило «дочекатись рестарту ліміту і продовжити» там просто нема на чому побудувати. Що робити з такою платформою: **не давати їй роботу взагалі**, давати тільки ту, де «впертись у стіну» не страшно, чи зупинятись і питати тебе?

2. Є два різні світи: **вікно** (скидається о конкретній годині — Claude, Codex, Kimi, Copilot, GLM) і **баланс/кредити** (не скидається ніколи, просто закінчуються гроші — DeepSeek, Amp, Cursor). Для «вікна» пороги у відсотках працюють. Для «балансу» відсотків не існує — треба стеля у грошах. Ти хочеш задавати **грошову стелю на ран** (наприклад «не більше $X за ніч»), чи обмежувати інакше?

3. На GLM ліміт одночасних сесій — це **умова підписки, а не технічна межа**: Lite 1, Pro 1–2, Max 2+, і після трьох порушень акаунт банять. Твоя ідея флоту з кількох паралельних сесій прямо в це впирається. Ставимо жорсткий governor по тарифу (і тоді GLM — це 1–2 лінії, не шість), чи GLM іде тільки як дешева лінія для одного виконавця?

4. На Kimi **усі пристрої й усі API-ключі ділять один пул**. Дві лінії на одному акаунті не подвоюють пропускну здатність — вони ділять її навпіл. Це змінює твій план «ролі на різних акаунтах»: для Kimi «різні ролі» означає **різні акаунти**, інакше сенсу нема. Готовий заводити окремий акаунт під кожну роль там, де пул спільний?

### Контекст і компакт (вісь D)

5. На чотирьох платформах (Amp, Gemini CLI, Cursor, DeepSeek `dsh`) компакт **неможливо запустити ззовні взагалі**. Твій «хард» режим (зупинити зараз, зробити компакт, продовжити) там не реалізується — доступний тільки «софт» через поріг, виставлений **до** старту рану і незмінний під час нього. Для таких платформ: працюємо тільки в софт-режимі, чи взагалі не пускаємо їх у ран, де контекст може закінчитись?

6. Універсальна заміна компакту, яка працює скрізь, — це **закрити сесію і відкрити нову з підсумком** (close-and-reseed). Але тоді один тікет = кілька сесій, і в реєстрі має бути ланцюжок, а не одне поле. Це ок для твого обліку, чи ти хочеш, щоб один тікет завжди мапився рівно на одну сесію?

7. Частина платформ після компакту видає **новий session id** (Droid). Тобто «продовжити руками» після компакту — це вже інший ідентифікатор. Записуємо обидва і показуємо ланцюжок, чи достатньо останнього?

### Акаунти (вісь F)

8. **На жодній із п'ятнадцяти платформ не можна змінити акаунт живої сесії.** Твоя «хард» зміна ролі-акаунта (діє негайно, зупиняє поточну роботу) фізично означає: зупинити сесію, запустити нову на іншому акаунті й **перезалити контекст** — тобто заплатити за нього ще раз. Підтверджуєш, що це прийнятна ціна хард-зміни, чи хард-зміна має чекати кінця поточного кроку?

9. На Cursor з логіном через браузер **кілька акаунтів на одній машині неможливі** (ім'я в keychain — жорстко зашитий рядок). Працює тільки API-ключ. На OpenCode **твоя підписка Claude Max взагалі не працює** — тільки API-ключ, тобто окремий рахунок. Це впливає на вибір: залишаємо ці платформи в списку з такою умовою, чи викреслюємо?

10. У Claude Code на macOS перший запуск під новим акаунтом може **відкрити діалог Keychain** — і нічний ран зависне на вікні, якого ніхто не бачить. Пропоную в префлайті вимагати, щоб кожен акаунт був хоча б раз запущений вручну і отримав "Always Allow". Робимо це обов'язковою умовою старту рану?

### Втручання і питання агента (вісь G)

11. На Gemini CLI у headless-режимі повідомлення в живу сесію взагалі не доставити, а в ACP-режимі воно **перериває поточний хід**, а не додається до нього. Тобто твій `stop-soft` там де-факто дорівнює `stop-hard`. Приймаємо це як відоме обмеження платформи, чи на таких платформах команди застосовуємо тільки на межі задач?

12. Там, де питання агента **не можна відповісти програмно** (Claude Code у `--bg`, DeepSeek SDK-лінія, Gemini headless), єдиний безпечний варіант — **не дати питанню виникнути**: дозволи/заборони списком + дозвільний режим. Але це прямо послаблює R1-02 (що саме можна віддавати на автономне виконання). Для таких платформ звужуємо перелік задач, чи розширюємо дозволи?

### Захист і пісочниця (вісь H)

13. Kimi і pi **не мають пісочниці взагалі** (ні контейнера, ні seccomp, ні обмеження ФС), а в Kimi ще й хуки «падають відкрито» — якщо сторож впав, дія дозволяється. Твоє правило «один текстовий файл із червоними лініями, без окремої процедури» на таких платформах залишається **єдиним** бар'єром. Додаємо для них обов'язковий worktree + жорсткий deny-лист як технічну умову, чи такі платформи взагалі не отримують прав на запис?

### Процес і ролі (вісь I)

14. Aider **не має ні MCP, ні сабагентів** — GSD або будь-який твій процес усередині нього не запуститься; він може бути тільки «листком», який виконує одну повністю описану задачу. Тримаємо такі платформи у флоті як дешевих виконавців, чи правило «процес має виконуватись усередині сесії» для нас безумовне?

### Що інсталювати й за що платити (вісь J)

15. Зараз на машині реально є тільки **claude** (свіжий), **codex** (на 3 релізи позаду) і **cursor-agent** (збірка річної давності, не залогінений). Усе інше — це нова інсталяція. Найсильніша платформа в усьому огляді за можливостями — **GitHub Copilot CLI** — недоступна, бо на акаунті `no_access` (реєстрація відкрита). Питання просте: на які платформи ти готовий витратити гроші/час на підключення **до** того, як ми почнемо писати їхні адаптери?

16. Ключ Xiaomi MiMo в `~/.config/claude-mimo/env` **мертвий** — сьогодні повертає 401 на обох хостах. Перевипускаєш, чи MiMo поки що викреслюємо?

17. Gemini: споживчий доступ до Gemini CLI закрився **2026-06-18**, наступник — **Antigravity CLI (`agy`)**, про який ми поки що не знаємо ні команди встановлення, ні headless-прапорців. Витрачаємо на нього окремий прохід дослідження, чи Gemini поки що поза списком?

18. Найдорожчий за віддачею експеримент у всьому огляді — **standalone-інсталяція Codex** (`chatgpt.com/codex/install.sh`). Якщо вона співіснує з npm-версією і піднімає daemon, то Codex стає беззаперечним tier-1, а оркестратор уперше отримує **супервізора, який переживає власну смерть**. Дозволяєш поставити її на цю машину?

---

## Appendix — where each claim lives

| Platform | Profile | Spike |
|---|---|---|
| Claude Code | `claude-code.md` | `claude-code-spike.md` |
| Codex CLI | `codex-cli.md` | `codex-cli-spike.md` |
| Droid | `droid.md` | `droid-spike.md` |
| Kimi Code | `kimi.md` | `kimi-spike.md` |
| Copilot CLI | `copilot-cli.md` | `copilot-cli-spike.md` |
| GLM | `glm.md` | `glm-spike.md` |
| DeepSeek | `deepseek.md` | `deepseek-spike.md` |
| OpenCode | `opencode.md` | `opencode-spike.md` |
| MiMoCode / Xiaomi | `xiaomi-mimo.md` | `xiaomi-mimo-spike.md` |
| Qwen Code | `qwen-code.md` | `qwen-code-spike.md` |
| pi | `pi.md` | `pi-spike.md` |
| Amp | `amp.md` | `amp-spike.md` |
| Gemini CLI | `gemini-cli.md` | `gemini-cli-spike.md` |
| Cursor CLI | `cursor-cli.md` | `cursor-cli-spike.md` |
| Aider | `aider.md` | `aider-spike.md` |
| Field resolution (“pi”, “Xiaomi”), local install inventory, multi-account machinery | `00-field-scan.md` | — |

**Known errors in the inputs, corrected here:** `00-field-scan.md` §2 claims Xiaomi is only an
env-var trick — `xiaomi-mimo.md` §0 disproves it. The orchestrator-landscape file this research was
told to avoid duplicating (`…/scratchpad/context/orchestrator-landscape.md`) **does not exist**; the
`context/` directory is empty (VERIFIED). Overlap with it could not be checked.
