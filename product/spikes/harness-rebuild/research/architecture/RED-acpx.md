# RED-acpx — independent verification of the one ADOPT recommendation

**Target:** `ADOPTION-VERDICT.md` §3, "`openclaw/acpx` — ADOPT AS A COMPONENT, pinned", and the four
rules attached to it.
**Method:** npm registry metadata, full `git clone` of `openclaw/acpx` (613 commits, HEAD `42bcbf2`,
2026-09-18), source read of `src/`, the published tarball `acpx-0.17.0.tgz`, the adapter tarball
`@agentclientprotocol/claude-agent-acp@0.76.0`, the SDK tarball `@anthropic-ai/claude-agent-sdk@0.3.274`,
GitHub issue/advisory API, and **hands-on execution of `acpx@0.17.0` on this machine** (Node 22.18.0).
**Date:** 2026-09-19.
**Tags:** VERIFIED (I read the primary artefact or ran it) · CLAIMED (asserted by a source I did not
independently confirm) · INFERRED (my reasoning from verified facts).

**Working artefacts** (scratchpad, one reboot from gone — regenerate, do not cite):
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/acpx/`
→ `repo/` (clone), `package/` (0.17.0 tarball), `adapter/` (claude-agent-acp 0.76.0),
`sdk/` (claude-agent-sdk 0.3.274), `install/` (working install used for the exit-code tests).

---

## Headline

**The recommendation stands. The reasoning underneath it does not.**

Adopt `acpx`, pinned. It is the right call and I could not break it. But four of the verdict's load-bearing
claims are wrong, and one of them — the Claude lane's settings isolation — would have silently removed
GSD, every one of your installed plugins, your hooks and your user permissions from every session the
orchestrator started, and you would have found out at 03:00 when a lane could not find `/gsd:execute-phase`.

Specifically:

| Verdict claim | Reality | Direction |
|---|---|---|
| "40 `### Breaking` sections in 44 releases" → pin or die | **4** non-empty, 3 released, **1** CLI-surface. 36 are empty template headers. | Verdict **understated** stability by ~10× |
| "across 44 versions the CHANGELOG contains no entry that changes an exit code. VERIFIED" | True of the CHANGELOG, **false of the code**: `PERMISSION_DENIED` was renumbered 4→5 on 2026-02-18 and never appeared in the CHANGELOG | Method was **unsound**; conclusion survives on other evidence |
| acpx "Prevented, deliberately" on R8; a question "fails with `user-answer-required`… exit `5`" | The refusal is gated on `agentInfo.name === "antigravity-acp"`. A **Claude** question becomes an ACP *elicitation*, which the CLI cancels as "handler unavailable" and the turn continues. The **embedded runtime accepts an elicitation handler** — R8 is *available*, not prevented | Verdict **overstated**; a whole architecture fork was built on it |
| "`npm i acpx@0.17.0` … pinned" closes the version risk | Pinning acpx pins the Claude adapter to `^0.76.0` → **exactly 0.76.0**, while upstream shipped **0.77.0, 0.78.0, 0.79.0 in the three days around it**. You are pinning to an adapter minor its own authors abandon in 72 hours | Verdict **missed the real version risk entirely** |

And one thing the verdict claimed as first-hand that I could not reproduce: *"It was installed and run on
this machine during the evaluation (`acpx@0.17.0`, Node 22.18.0, 41 packages, 6 seconds) — the CLI surface
and the exit codes match the docs. (VERIFIED first-hand.)"* — `acpx` is **not** on this machine's PATH and
is **not** in `npm ls -g`; `~/.acpx/sessions/index.json` exists with `"files": [], "entries": []`. Whatever
ran, it never created a session, so it cannot have verified the session layer. I installed it myself and
re-ran the tests below. (VERIFIED.)

---

## FINDING 1 — SEVERITY: RUN-ENDING. `acpx claude` does not load your user settings, which is where GSD, every plugin, your hooks and your permissions live.

**The code.** `src/acp/agent-command.ts:18`:

```ts
const CLAUDE_CODE_DEFAULT_SETTING_SOURCES = ["project", "local"] as const;
```

`resolveClaudeCodeSettingSources()` (`:326–331`) returns that list verbatim unless
`ACPX_CLAUDE_INCLUDE_USER_SETTINGS` is exactly `"1"`, and `:306` passes it to the adapter as
`claudeCodeOptions.settingSources`. `agents/Claude.md` states the intent in the open:

> Built-in `acpx claude` sessions load Claude project and local settings, **but not user settings**. This
> prevents globally enabled channel and daemon plugins from claiming singleton external resources in an
> ACP-spawned session.

**Why that is fatal for you specifically.** The Agent SDK's own type declaration
(`@anthropic-ai/claude-agent-sdk@0.3.274`, `sdk.d.ts:2124–2133`) says `'user'` is
`~/.claude/settings.json`, and "When omitted, all sources are loaded (matches CLI defaults)." acpx does not
omit it — it names two of three. And `~/.claude/settings.json` on **this machine**, read just now, has these
top-level keys:

```
enabledPlugins, hooks, permissions, env, model, statusLine, skillOverrides,
effortLevel, alwaysThinkingEnabled, attribution, extraKnownMarketplaces, …
```

with `enabledPlugins` containing `harness@sashamarchuk-plugins: true`,
`clickup@sashamarchuk-plugins: true`, `g-event@…`, `interview-handoff@…`, `morning-brief@…`, `msg@…`,
`figma@…`, `pr-review-toolkit@…` and the rest. **All of it is excluded from an `acpx claude` session at
default.** (VERIFIED — code read, SDK declaration read, your settings file read.)

Corroborating: the adapter never supplies the SDK's `plugins` option either. A full grep of
`claude-agent-acp@0.76.0/dist/` for `plugins` returns exactly two hits, both inside a comment in
`resolveSkillPath()` that only builds a *display link* for an already-running skill. Nothing in the adapter
passes `SdkPluginConfig[]`. (VERIFIED.)

**What I could not settle.** Whether user-level *skills* (`~/.claude/skills/gsd-*`, which is where your
~70 GSD skills actually live — not a plugin) survive the exclusion. The SDK's `skills` option comment says
omitting it means "no SDK auto-configuration. The CLI's own defaults still apply, so this is **not** 'skills
off'", which suggests skill discovery is independent of `settingSources`. But `skillOverrides` — the key
`/gsd:surface` writes, which decides *which* skills are surfaced — is in user settings and is definitely
lost. (INFERRED, and it is the single highest-value thing to test before you commit.)

**The trap in the fix.** `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1` restores everything — and restores exactly
the hazard the default was added to prevent. You are the worst case for it: `harness` is a daemon-shaped
plugin, and your MCP servers (`slack-user`, `playwright-persistent`, `n8n-mcp`, `sentry`) are singletons
that N parallel lanes will contend for. There is **no per-plugin granularity** — the env var is all-or-nothing.

**Design for it:**

- **DEFAULT: `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1`** for every orchestrator-started Claude lane. Losing
  GSD is not survivable; singleton contention is. Configurable per lane as
  `lanes.<id>.claude.includeUserSettings`, **default `true`**.
- **DEFAULT: the orchestrator writes a lane-local `.claude/settings.json`** into each worktree that
  re-disables the singleton-claiming plugins by name (`enabledPlugins: {"harness@…": false, …}`), since
  `project` *is* loaded and outranks `user`. Config slot `lanes.<id>.claude.disablePlugins`,
  **default `["harness@sashamarchuk-plugins"]`** — the orchestrator must never spawn itself.
- **PREFLIGHT GATE, non-optional:** before any run, one throwaway turn per lane asking the session to list
  its available slash commands, and fail the run if `/gsd:execute-phase` is absent. This is the R5 "verified
  before a run" clause applied to the *engine*, not the account. **Default: on.**

**Tension to record:** you asked for an orchestrator that does not own the process and that runs GSD.
acpx's Claude adapter takes a defensible position — isolate the spawned session from the user's global
config — that is directly hostile to that requirement. You are overriding a deliberate safety default of
your session layer, in writing, on purpose.

---

## FINDING 2 — SEVERITY: HIGH. Pinning `acpx` does not pin the thing that actually runs your code, and the thing that actually runs your code moves 15× faster.

`src/agent-registry.ts:7–12`:

```ts
const ACP_ADAPTER_PACKAGE_RANGES = {
  pi: "^0.0.33", codex: "^1.1.5", claude: "^0.76.0", mux: "^0.28.0",
} as const;
```

and `:80` launches `npx -y @agentclientprotocol/claude-agent-acp@^0.76.0`. Resolved just now:
`npm view '@agentclientprotocol/claude-agent-acp@^0.76.0' version` → **`0.76.0`** — the range is a `0.x`
caret, so it is `>=0.76.0 <0.77.0` and there are no patches in it. Meanwhile `dist-tags.latest` is
**`0.79.0`**. The adapter's release timeline: `0.77.0` on 2026-09-14, `0.78.0` on 2026-09-15, `0.79.0` on
2026-09-17 — **three minors in three days**, 90 published versions since 2026-03-26 (~3.5/week). acpx
published 44 versions in seven months (~1.5/week). (All VERIFIED from the registry.)

So "pin `acpx@0.17.0`" freezes you on an adapter release its own maintainers left behind within 72 hours,
and the *only* way to move the adapter forward is to unpin acpx — the two rules are in direct conflict and
the verdict states only one of them. Worse, the resolution happens through `npx -y` **at agent launch**,
i.e. inside the run, over the network, in your 03:00 window.

`agents/Claude.md` says the quiet part: *"ACPX pins the built-in package range so fresh installs pick up
Claude model and ACP adapter fixes without depending on a global adapter binary. Update ACPX to pick up
changes to the supported adapter range."* Adapter currency is coupled to acpx currency by design.

**Design for it:**

- **DEFAULT: do not use the built-in `claude` registry entry.** Pin both halves explicitly in acpx config:
  `agents.claude.argv = ["npx","-y","@agentclientprotocol/claude-agent-acp@0.76.0"]`. Config slot
  `adapters.claude.version`, **default `"0.76.0"`** (the version acpx 0.17.0 was tested against).
- **DEFAULT: pre-install the adapter, do not `npx` it at launch.** `npm i -g @agentclientprotocol/claude-agent-acp@<pin>`
  and point `argv` at the installed `claude-agent-acp` binary — acpx already prefers `installedArgv` when
  present. Removes a network dependency from the hot path. Config slot `adapters.preinstall`, **default `true`**.
- **DEFAULT: a single joint-upgrade review, monthly, of the pair (acpx, adapter).** Never one without the
  other. Config slot `adapters.upgradeReviewDays`, **default `30`**.
- **Preflight assertion, default on:** `acpx --version` equals the pin *and* the resolved adapter version
  equals its pin; refuse the run otherwise. This is the only defence against `npx` quietly resolving
  something new.

---

## FINDING 3 — SEVERITY: HIGH. R8 is not prevented. The verdict built an architectural fork on one adapter's quirk.

The verdict's "Change 2" reads the Unreleased→Breaking entry as the industry closing the door on answering
a session's question, and turns that into: exit `5` becomes a first-class state, Д6 becomes load-bearing,
R1-11's hybrid mode stops being optional. **The entry does not say that.** `src/acp/client.ts:1930–1942`:

```ts
// Antigravity encodes questions as permissions, with answers marked allow_once.
// Neither permission policies nor the host's allow/reject API can answer them.
if (
  this.initResult?.agentInfo?.name === "antigravity-acp" &&
  params.toolCall.toolCallId.startsWith("interaction_")
) { … PermissionPromptUnavailableError … }
```

Two guards, both required: the agent must self-identify as `antigravity-acp`, and the tool-call id must
start with `interaction_`. **A Claude Code question never enters this branch.** (VERIFIED.)

What actually happens to a Claude question is better and more interesting. `claude-agent-acp@0.76.0`
contains `elicitation.js` with `extractAskUserQuestions()` and *"Render the AskUserQuestion tool's questions
as an ACP form elicitation"* — 38 `AskUserQuestion` references across `tools.js`, `acp-agent.js`,
`elicitation.js`, `permissions/options.js`. So `AskUserQuestion` becomes an **ACP form elicitation**, not a
permission request. (VERIFIED.)

acpx routes elicitations through `handleElicitationRequest` → `resolveElicitationOwner` →
`active.elicitationHandler`. And `onElicitation` is set in **exactly one place**: the embedded runtime
(`src/runtime.ts:238,277`, `runtime/engine/manager.ts`, `runtime/engine/prompt-turn.ts`). The CLI path never
sets it, so `client.ts:2007` finds no handler and returns
`cancelledElicitationResponse("elicitation handler is unavailable")`. (VERIFIED by grep across `src/`.)

**Three consequences the verdict inverted:**

1. Through the **CLI**, a Claude question is *cancelled*, not fatal. The tool gets `action: "cancel"`, the
   model sees a declined question and decides what to do. The turn continues. There is no exit `5` on that
   path — exit `5` requires *every permission request in the turn* to have been denied or cancelled with
   none approved (`docs/permissions.md`, "Exit code 5"). A GSD `discuss-phase` that asks one question and
   then does ten approved file writes exits `0`.
2. Through the **embedded runtime**, the orchestrator **can answer**. `acpx/runtime` accepts an
   `onElicitation` handler per turn (CHANGELOG 0.13.1: *"turn-scoped ACP form and URL elicitation handlers
   with capability and cancellation fencing"*). That is R8 — "the orchestrator answers a session's own
   question" — available today, not prevented. It is the only mechanism I found in this entire research
   that does it.
3. The verdict's own Rule 2 forbids depending on the runtime API — which is where the R8 capability lives.
   **Rule 2 and Change 2 are in contradiction** and neither notices.

There is also a third, cheaper channel the verdict missed: `--permission-policy` with `escalate`.
`docs/permissions.md`: *"In non-interactive output, an escalated request is denied for the current turn…
JSON mode… includes structured escalation details, including tool input… in the
`session/request_permission` response `_meta.acpx.permissionEscalation` object **so an orchestrator can
resume with a broader policy**."* That is a real, documented, CLI-only escalate-and-resume loop for
*permissions*. It does not answer a question, but it covers the "session is blocked on approval" half of Д6.

**Design for it:**

- **DEFAULT: CLI transport, elicitation cancelled.** Simplest, matches Rule 2, and a cancelled question is
  not a dead lane. Config slot `lanes.<id>.transport`, **default `"cli"`**.
- **DEFAULT: `lanes.<id>.questionPolicy = "cancel-and-note"`** — cancel, record the question text from the
  JSON stream into the lane journal, and surface it on the Д6 channel as information. Alternatives:
  `"escalate"` (route to the Д6 channel and block the lane) and `"answer"` (requires the runtime transport).
- **Keep the runtime path as a named, opt-in second transport, not as dead code.** One lane config value
  (`transport: "runtime"`) and an `onElicitation` that posts to the Д6 channel and waits. **Default off**,
  **explicitly budgeted**, because it is the only R8 implementation in the field and it is the one thing
  here that would make your tool the thing it is.
- **Do not build the architectural fork of Change 2 on this evidence.** Keeping `harness-term.sh` as an
  interactive lane may still be right for *other* reasons (a human watching, a trust dialog, `/login`), but
  "questions are terminal in headless" is not one of them, and it is the reason the verdict gave.

---

## FINDING 4 — SEVERITY: MEDIUM-HIGH. A dead queue owner silently falls back to a brand-new empty session, and the turn still exits `0`.

`docs/CLI.md`, Auto-resume: *"If a saved session PID is dead, `acpx` respawns the agent, tries
`session/resume` when advertised or `session/load` otherwise, and **transparently falls back to
`session/new` when reconnecting fails**."* `docs/2026-02-23-session-identity-spec.md:54`: *"`acpxSessionId`
MAY change if acpx must create a fresh ACP session after load/reconnect failure."* (VERIFIED.)

This is FIELD-NOTES §11.4 — *reported success and did nothing* — reappearing as *reported success and
started over*. Prompt 7 of a ticket lands in a session with no memory of prompts 1–6, produces confident
nonsense, and exits `0`. Nothing in the exit-code contract distinguishes it.

The mitigating fact, and it is a real one: `claude-agent-acp@0.76.0` **advertises `loadSession: true`**
(`acp-agent.js:931`), so reconnect is a genuine ACP load for the Claude lane, not a stub. And the
fallback is *detectable*: `acpxRecordId` stays stable while `acpxSessionId` changes, and both are emitted
in JSON output per the identity spec. (VERIFIED.)

**Design for it:**

- **DEFAULT: the lane journal records `acpxSessionId` after every turn, and a change without an explicit
  `sessions new` is a lane-fatal event.** Config slot `lanes.sessionIdentityDrift`, values
  `fail` / `restart-ticket` / `warn`, **default `"fail"`**. Do not let a lane keep working in an amnesiac
  session.
- Do not paper over it with retries. A fresh session is a *state* change, not a transient error.

---

## FINDING 5 — SEVERITY: MEDIUM. The stability evidence the verdict used is unsound. The conclusion happens to survive.

Two separate errors, in opposite directions.

**(a) "40 Breaking sections" is a template artefact.** Parsing the CHANGELOG by release: 43 release
sections, 40 `### Breaking` headers, **36 of them empty**. Non-empty: 4 — one of which is Unreleased.
The three *released* breaking changes in acpx's entire history are:

| Release | Breaking change | Touches the "stable triple"? |
|---|---|---|
| v0.13.0 (2026-07-27) | Windows launches require structured `agents.<name>.argv`; *"Existing custom-agent sessions without saved argv must be recreated"* | Yes — config surface. **Windows only.** You are on macOS |
| v0.13.1 (2026-08-18) | Runtime API requires `AcpRuntimeTurn.promptStarted` | No — runtime API, Rule 2 already excludes it |
| v0.17.0 (2026-09-17) | `.stream.ndjson` now carries local lifecycle records; consumers must filter `jsonrpc: "2.0"` | No — session-journal schema, Rule 2 already excludes it |

**Zero** released breaking changes to subcommand names, exit codes or `--format json` in 43 releases.
That is a *far* stronger case for adoption than the verdict made, and it means Rule 1's stated rationale is
fiction even though Rule 1 itself is still correct (pin anyway — see Finding 2 for the real reason).
(VERIFIED by parsing the CHANGELOG.)

**(b) The CHANGELOG grep would have missed a real exit-code change, and did.** The verdict's proof was
*"across 44 published versions the CHANGELOG contains no entry that changes an exit code."* I re-ran that
grep: zero hits, correct. Then I ran `git log -L` on the `EXIT_CODES` block in `src/types.ts` — touched
twice in 613 commits, and commit `1dd7337` (2026-02-18, `feat: require explicit sessions and route by
directory walk`) is:

```diff
-  PERMISSION_DENIED: 4,
+  NO_SESSION: 4,
+  PERMISSION_DENIED: 5,
```

**An exit code was renumbered, and the CHANGELOG never mentioned it.** It happened one day after first
publish, before anyone depended on it, and the table has been frozen since — but the method the verdict
used to certify the contract is the exact method that fails to see that class of change. The contract is
stable; the *proof* was not. (VERIFIED.)

**Design for it:** **DEFAULT: a contract test in your own repo** that asserts all seven codes by running the
pinned acpx, on every upgrade of either pin. Not a doc read. Config slot `preflight.exitCodeContractTest`,
**default `true`**.

---

## FINDING 6 — SEVERITY: MEDIUM. `--timeout` defaults to no timeout, and `--ttl` defaults to a 5-minute resident process per lane.

`docs/config.md` table, verified against `src/cli/flags.ts`:

| Key | acpx default | What it costs you |
|---|---|---|
| `timeout` | **`null`** — no timeout at all | Exit `3`, the code that retires FIELD-NOTES §2.2 (*a shell that cannot exit reads as work*), **never fires unless you set it**. The single most valuable exit code is off by default |
| `ttl` | **`300`** | After every prompt, a detached queue-owner node process stays resident 5 minutes *per session*. `queue-owner-process.ts:221` `detached: true`, `:278` `child.unref()` — it outlives the CLI by design |
| `defaultPermissions` | `approve-reads` | A write-heavy GSD phase is denied by default |
| `nonInteractivePermissions` | `deny` | Un-promptable requests are silently denied, not surfaced |
| `defaultAgent` | `codex` | Bare `acpx sessions …` talks to Codex, not Claude |
| `format` | `text` | Human stream, not the NDJSON the orchestrator parses |

Every single default is wrong for unattended orchestration. None of them are wrong for acpx's stated
primary user. (VERIFIED.)

**Design for it — the full default set the orchestrator must impose:**

| Orchestrator slot | **DEFAULT** | Why |
|---|---|---|
| `lanes.turnTimeoutSeconds` | **`3600`** | A GSD phase turn that has not moved in an hour is stuck. Exit `3` is the whole point |
| `lanes.ttlSeconds` | **`60`** | Not `300` (five minutes × N lanes of resident node, and a five-minute tail after "the queue is empty" — R1's terminal condition gets fuzzy). Not `0` (never idle-shuts-down; a leak by construction) |
| `lanes.format` | **`"json"` with `--json-strict`** | Rule 2's stable triple |
| `lanes.permissionMode` | **`"approve-reads"`** + an explicit `--permission-policy` | Never `--approve-all` as a blanket default; see below |
| `lanes.permissionPolicy` | **`{"autoApprove":["read","search","edit"],"escalate":["execute"],"defaultAction":"deny"}`** | Writes proceed, shell escalates and is visible in `_meta.acpx.permissionEscalation` |
| `lanes.nonInteractivePermissions` | **`"fail"`** | Loud. `deny` is how you get a session that silently accomplished nothing |
| `lanes.maxTurns` | **unset** | acpx forwards `--max-turns` to the SDK. A cap kills long GSD phases mid-work with no distinguishing exit code |
| `lanes.noTerminal` / `lanes.noFs` | **both `false`** | GSD needs both. Note `docs/permissions.md` is explicit that `--cwd` fs-safe rooting is *"best-effort guardrails within acpx's trusted-user model, not an OS sandbox"* and *"do not confine arbitrary shell commands launched through terminal capabilities"* — it does **not** solve R11 |
| `lanes.sessionName` | **the ticket id** | `sessions ensure --name <ticket>`, idempotent, one session per ticket |
| `lanes.cwd` | **the ticket's worktree** | Also the fs-safe root and part of the scope key |
| `config.useProjectAcpxrc` | **`false`** | Do not let a `.acpxrc.json` appear in the project tree. It is a seventh config file the orchestrator does not own and your architecture rules do not have a slot for. Pass flags |
| `lanes.mcpConfigPath` | **per-run file via `--mcp-config`** | `docs/config.md`: *"An existing persistent session cannot switch MCP configurations while its queue owner is live."* Mid-run MCP change (R9) is **blocked** until the lane's session is closed. Record this as an R9 carve-out |

---

## FINDING 7 — SEVERITY: LOW, and it is the strongest thing here. The process-tree claim is true, and I broke it on purpose to check.

The verdict's best argument is that acpx retires FIELD-NOTES §2.2 (a lane holding an `until grep… sleep 5`
that could never match; another accumulating **58 concurrent child shells**). I tested it directly.

A fake ACP agent that never speaks the protocol *and* leaks a backgrounded grandchild:

```bash
#!/bin/bash
sleep 900 &          # grandchild, deliberately orphaned
exec sleep 900       # the "agent"
```

```
$ acpx --agent "$PROBE" --timeout 8 sessions new
Timed out after 8000ms
hint: increase `--timeout <seconds>` for long-running prompts, or check whether the agent/provider is stalled.
$ echo $?
3
$ ps -eo pid,ppid,etime,command | grep probe-agent   # (nothing)
$ ps -eo pid,ppid,etime,command | grep 'sleep 900'   # (nothing)
```

**Exit `3` on the nose, and both the child and the backgrounded grandchild were reaped.** (VERIFIED,
hands-on, this machine, 2026-09-19.) The CHANGELOG's *"clean up witnessed POSIX descendants after bridge
shutdown, startup failure, and observed exit"* (0.16.0) is real.

Also verified hands-on, same install:

| Case | Expected | Got |
|---|---|---|
| `acpx --version` | — | `0.17.0`, rc `0` |
| `--approve-all --deny-all` | `2` | **`2`** |
| `--agent 'foo' codex 'x'` | `2` | **`2`** |
| prompt in a dir with no session | `4` | **`4`**, with `⚠ No acpx session found (searched up to …)` |
| agent binary fails to start | `1` | **`1`**, `ACP agent exited before initialize completed (exit=1, signal=null): …` |
| `--timeout` expiry with leaked grandchild | `3` | **`3`**, tree reaped |
| `status` with no session | `0` | **`0`**, `status: no-session` |

A failed `sessions new` left **no** record behind (`index.json` still `"entries": []`). Clean.

Codes `0` and `5` are untested here — `5` needs a live agent and a denied turn, and I judged spending your
quota on it not worth it. **Test `5` yourself before you depend on it**, because it is the one code with a
subtle definition (*every* request denied, *none* approved) and the one the verdict wants to make a
first-class state.

---

## FINDING 8 — SEVERITY: LOW. The project's health is genuinely good, and better than the verdict said.

All VERIFIED via the GitHub and npm APIs, 2026-09-19:

- **2 open issues** (#527 "Add atomic cancel-and-replace", #499 "Follow-up on #433: ACP bridge lifeline /
  process cleanup"). The verdict said 4; it is now 2. Both are enhancement-shaped, neither blocks you.
- **Zero security advisories, lifetime.** `npm audit` on a clean `acpx@0.17.0` install: `0` across all
  severities, 39 packages.
- **~5.09M downloads in the last 30 days** (peak 347k/day). 3,263 stars, 335 forks, 16.9 MB.
- **Bus factor ≥ 3.** 613 commits: Steinberger 164, "Bob" 107, Vincent Koc 81, dependabot 68, Onur Solmaz
  75 (two identities), Sebastien Tardif 14. Not a one-person project.
- **Median time-to-close 208 h (8.7 days)**, p90 702 h, across 93 closed issues. Slow-ish, not abandoned.
- Commit velocity dipped (Jun–Aug: 50/31/31/month) and recovered (Sep: 87). Watch it, do not panic at it.
- **npm provenance attestation present** (SLSA v1), published by GitHub Actions OIDC, not a personal token.
- `VISION.md` is the right shape for a dependency: *"the smallest useful ACP client… The goal is not to
  build a giant orchestration layer… The primary user is another agent, orchestrator, or harness."* A
  dependency whose stated scope stops exactly where your product starts is a dependency that will not
  grow into a competitor or drag you along.

**One inherited-risk note the verdict should have raised and did not:** acpx depends on
`@openclaw/fs-safe@^0.10.0` (with a native `darwin-arm64` binary) and `skillflag@^0.2.1` — the first from
the same org whose main product carries **722 lifetime advisories**, the second a third-party package that
installs a `skill-install` binary into `node_modules/.bin`. Neither has a postinstall script and neither
writes to `~/.claude` on install (VERIFIED — `acpx`'s `package.json` has no install hooks, `files` is
`["dist","skills","README.md","LICENSE"]`). The risk is not present today; it is a surface to watch,
because `fs-safe` is the module that enforces `--cwd` rooting.

---

## The four rules, re-judged

| Verdict rule | My verdict |
|---|---|
| **1. Pin `acpx@0.17.0` exactly** | **KEEP — wrong reason, right rule.** Not because of 40 breaking changes (there were 3). Because the adapter range is baked into the acpx build, and an unpinned acpx silently changes which Claude adapter runs your code. **Amend:** pin the adapter explicitly too, and pre-install it (Finding 2) |
| **2. Depend only on subcommand names, exit codes, `--format json --json-strict`** | **KEEP, and it is now better evidenced than the verdict knew** — zero released breaking changes to any of the three in 43 releases. **Amend:** verify the exit codes by test, not by CHANGELOG (Finding 5b), and note that Rule 2 forecloses R8 (Finding 3) — make that a decision, not an accident |
| **3. Treat exit `5` as a first-class outcome; "a worker that asks a fixed-choice question does not wait; it fails the turn"** | **REJECT the premise, KEEP the handling.** Exit `5` is worth handling — it means every permission in a turn was denied, which is a real and useful signal. But it is **not** what happens when a Claude session asks a question, and the "hardening" cited is Antigravity-gated (Finding 3). Do not build the R8 fork on it |
| **4. Keep the queue, stop verbs, board write-back and quota policy in your own code** | **KEEP, unreservedly.** `VISION.md` confirms acpx will never grow into these. Add a fifth: **keep the defaults in your own code too** — every acpx default is wrong for unattended use (Finding 6) |

---

## The four questions the task asked

### Is adopting it right? — **Yes.** Two independent reasons, neither of which is the verdict's.

1. **It is the only artefact in this entire research that does the specific thing you need and has a
   published, code-verified, seven-month-stable machine contract.** Exit codes confirmed by running it, by
   reading `src/types.ts`, and by `git log -L` over the whole history. I tried to break the process-tree
   cleanup with a deliberately leaked grandchild and could not.
2. **Its stated scope stops where your product starts.** *"The goal is not to build a giant orchestration
   layer."* You are not adopting a competitor's substrate; you are adopting a component whose author has
   written down that he will not build your product.

The negative case I could not make: I looked for a reason to overturn and the failures I found are all
*configuration and integration* failures — severe, fixable, and cheaper than the 400–600 lines of
terminal-séance shell they replace. Finding 1 is the only one that could have been run-ending, and it is a
one-line environment variable plus a preflight gate.

### What is the real exit cost if it is abandoned?

The verdict says *"delete the dependency and go back to driving terminals… The reversal is an afternoon."*
**Closer to two to four days, and the shape matters more than the number.**

| Cost | Reality |
|---|---|
| Replace the spawn function and `case $?` | Genuinely small. A day |
| The session model | **This is the real cost.** `(agentCommand, absoluteCwd, name)` scope keys, `sessions ensure` idempotence, directory-walk resume, `acpxRecordId`/`acpxSessionId` drift detection, per-ticket named sessions — your ticket state machine will be written *in these terms*. Reverting means re-deriving "which conversation is this ticket in" from scratch |
| The exit-code state machine | Your orchestrator's outcome taxonomy becomes `{0,1,2,3,4,5,130}`. A terminal-driving replacement has to synthesise all seven from screen text — which is exactly what FIELD-NOTES says never worked |
| Process-tree cleanup | You would be re-writing the thing that made the 58-concurrent-child-shells bug possible. Do not reimplement; if you leave acpx, leave to **another ACP client**, not to a TTY |
| What you keep | Everything that matters: queue, stop verbs, board write-back, quota policy, config scopes, prohibitions file. Rule 4 is what makes the exit cheap, and it is the rule to defend hardest |

**The honest framing:** the exit is cheap *in code* and expensive *in concepts*. Mitigate it by putting
acpx behind a `SessionLane` interface with exactly seven outcomes and five verbs
(`ensure`, `prompt`, `cancel`, `status`, `close`) and letting nothing else in the orchestrator import it.
**DEFAULT: `adapters.sessionLane = "acpx"`**, with the interface written so a second implementation is
possible without touching the state machine. That is a day of extra work that turns a four-day exit into a
one-day exit, and it is also the thing that lets you run a non-ACP lane later.

### What does it constrain?

1. **Node ≥ 22.13 on every host that runs a lane.** (You are on 22.18.0. Fine, but it is now a runtime
   requirement of your orchestrator, which was previously pure shell.)
2. **Session state lives in `~/.acpx/`, globally, keyed by absolute cwd.** Not in your project, not in your
   run directory. It is a state store you do not own and your config levels do not reach.
   **DEFAULT: set `ACPX_*`/`HOME`-scoped session roots per run if acpx supports it; otherwise treat
   `~/.acpx/sessions` as orchestrator-owned and prune it (`sessions prune --older-than`) at run end** —
   config slot `lanes.pruneAfterRunDays`, **default `7`**.
3. **One extra config file wants to exist in every project** (`.acpxrc.json`). Refuse it (Finding 6).
4. **MCP configuration is frozen for the life of a lane's queue owner.** A genuine, documented carve-out of
   R9's "changeable during a run."
5. **A detached queue-owner process per active session**, outliving the CLI by `ttl` seconds. Your "kills
   only what it started" accounting must include them, and your terminal condition must wait for or reap
   them. This is a small resident daemon — the exact architecture you rejected in OpenClaw — arriving
   through the side door, at a much smaller scale.
6. **The Claude lane is the Agent SDK, not the Claude Code CLI.** `claude-agent-acp` depends on
   `@anthropic-ai/claude-agent-sdk@0.3.274` (exact pin). Hooks, statusline, output styles, `skillOverrides`
   and plugin loading all behave differently from the CLI you tested GSD against. Finding 1 is the sharpest
   edge of this, but it is not the only one.
7. **R8, if you want it, forces the runtime API** — which Rule 2 forbids. That is a real fork; make it
   deliberately (Finding 3).

### What would reverse the recommendation?

Concrete, checkable triggers. Any one of these and I would reopen:

1. **The preflight gate in Finding 1 fails and cannot be fixed.** If, with
   `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1` and a lane-local `.claude/settings.json`, a spawned session still
   cannot resolve `/gsd:execute-phase`, acpx cannot drive your engine and nothing else here matters.
   **This is the test to run first, before any other work.**
2. **Exit `5` does not behave as documented** under a real denied Claude turn (untested here).
3. **The Antigravity refusal generalises.** If a future release drops the `agentInfo.name ===
   "antigravity-acp"` guard and applies `PermissionPromptUnavailableError` to any fixed-choice question,
   Finding 3 inverts and the verdict's Change 2 becomes correct. **Watch `src/acp/client.ts:1930–1942`
   on every upgrade.** This is a one-line diff away from being true.
4. **`ACPX_CLAUDE_INCLUDE_USER_SETTINGS` is removed**, or the adapter stops honouring `settingSources`.
   The escape hatch is undocumented-adjacent (it appears in `docs/config.md`, `docs/CLI.md` and
   `agents/Claude.md`, and has two tests) but it is an env var, not a contract.
5. **The adapter gap becomes a compatibility break.** acpx 0.17.0 → adapter 0.76.0 while upstream is at
   0.79.0. If Claude Code ships a change that 0.76.0 cannot speak and acpx does not widen the range within
   ~30 days, the Claude lane rots and you are pinned to a broken pair.
6. **Anthropic ships a first-party stateful headless session contract** with exit codes. That is the one
   event that makes acpx redundant rather than wrong, and it is plausible within a year (INFERRED).
7. **The bus factor collapses** — Steinberger leaves and the Sep-2026 velocity recovery does not hold, or
   the org's advisory pattern reaches `fs-safe`.

---

## What to do, in order

1. **Run the Finding 1 test before writing any orchestrator code.** `acpx claude sessions ensure` in a
   worktree with `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1`, one prompt asking the session to name its available
   slash commands and skills. Compare with and without the env var. That one experiment decides whether
   this adoption is possible at all, and it costs one cheap turn.
2. **Correct ADOPTION-VERDICT.md** on the four claims in the headline table, and **retract "Change 2"**
   pending Finding 3. An architectural fork is being justified by a misread of an Antigravity-gated branch.
3. **Pin both halves and pre-install the adapter** (Finding 2). Add the version-equality preflight.
4. **Write the seven defaults in Finding 6 into the config spec** before the first line of lane code, and
   write the exit-code contract test (Finding 5).
5. **Put acpx behind a five-verb `SessionLane` interface** and let nothing else import it. This is the
   entire exit strategy, and it is one day of work.
6. **Decide R8 explicitly.** Either accept `cancel-and-note` and say so in the requirements, or budget the
   runtime transport. Do not let Rule 2 decide it silently.
