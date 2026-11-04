# ARCH-adapters.md — the orchestrator, designed adapter-and-extensibility-first

**Date:** 2026-09-19. **Lens:** *Adapter and extensibility first.*
**Subject:** the plugin working-named `orchestrator`, replacing `plugins/harness/`.
**Requirements source:** `../../round-1/ANALYSIS-01.md` (item codes `R1-nn`, `Д-n`, `I-n`) over
`../../round-1/TRANSCRIPT-01.md` (row anchors `[nnn]`). The owner's decisions are given; where one is
uncomfortable it is designed for and the tension is recorded under its own heading (§19), never
quietly replaced.
**Other inputs read in full or in the parts cited:** `../platforms/ADAPTER-CONTRACT.md`,
`../LANDSCAPE.md`, `../adoption/ADOPTION-VERDICT.md`, `../clusters/C1,C3,C4,C5,C6,C7,C8,C9-*.md`,
`../extract/*.md`, `plugins/harness/docs/FIELD-NOTES.md`,
`<baseline-marketplace>/requirements/OWNER-DECISIONS.md`
and `docs/config-levels.md` there, `~/.claude/gsd-core/`.

**Evidence tags.** **VERIFIED** — established by a cited source that ran or read the thing.
**CLAIMED** — asserted by a vendor or a non-primary source. **INFERRED** — this document's reasoning.
A default the owner never stated is tagged **DEFAULT-PROPOSED** and says what it protects against.
Every configurable thing in §17 has a default; that table is the contract, and nothing outside it is
allowed to invent one at runtime.

---

## 0. The thesis of this lens, in one page

The owner's system is not a workflow. It is **a configuration and control plane over other people's
workflows and other vendors' agents** (ANALYSIS headline, R1-03, R1-04, R1-17). Read adapter-first,
that sentence has a precise architectural consequence:

> **Nothing in the core may name a platform, a provider, or an engine.** Adding Kimi, or superpowers,
> or a ClickUp board, is a directory with a manifest in it. If a change to the core is required, the
> seam was drawn in the wrong place.

Three seams carry the whole design, and they never touch each other:

| Seam | What crosses it | Who may know about the other side |
|---|---|---|
| **Platform seam** | bytes in and out of an agent session | the adapter knows its CLI; the core knows only `manifest.json` and normalised events |
| **Engine seam** | what a session is told to do, and how its progress is read | the engine descriptor knows GSD; the core knows only eight interface points |
| **Board seam** | where work comes from and where status goes back | the board adapter knows GitHub; the core knows only the five-state readiness contract |

The seams meet in exactly one place: **the normalised event log** (§6). The core reads that file and
nothing else. `ADAPTER-CONTRACT.md` §6.2 states the reason and this design takes it as law: *"Do not
let the orchestrator read platform-native records directly; that is how one platform's schema change
breaks the run loop for all of them."*

Two structural findings from the research shape everything below:

1. **The adapter count is smaller than the platform count.** Four of the fifteen names are *providers*
   — another CLI pointed somewhere else by environment (GLM, DeepSeek-as-lane, Kimi-as-endpoint,
   Xiaomi-as-model). VERIFIED, `ADAPTER-CONTRACT.md` §0. So the config has two objects, not one, and
   `Lane = Platform × Provider × Account × Role` is the unit that actually runs.
2. **Capability is not uniform and never will be.** Seven of fifteen platforms cannot report remaining
   capacity at all; four cannot be told to compact; one cannot be sent a message mid-turn. VERIFIED,
   `ADAPTER-CONTRACT.md` §1, §3. A design that assumes uniformity does not degrade — it lies. So
   **capability negotiation is a first-class run phase**, not a lazy check, and it happens before any
   token is spent.

---

## 1. The object model

Five objects. Each is a config record; none is code in the core.

```
Provider = { id, base_url, auth_ref, model, small_model, context_window,
             capacity_model: Window | Credit | None | Unknown,
             capacity_probe?: <probe object>, concurrency_ceiling?, price_hint? }

Platform = { id, adapter_id, binary, version_pin, transport: exec|rpc|http|acpx|pty,
             home_env, manifest: <capability map>, invariants: [...] }

Account  = { id, platform, credential_kind: config_dir|api_key|login_only,
             env: {...}, identity_probe: <probe object>, roles_allowed: [...] }

Role     = { id, needs: [capability requirements], model_pin?, provider_pin?,
             authority: <authority object>, needs_predictable_capacity: bool }

Lane     = Platform × Provider × Account × Role        # the runnable slot
Engine   = { id, protocol_version, points: {start, step, progress, completion,
                                            branching, verification, delivery, state_ref} }
```

**Why Provider and Platform are separate, concretely.** GLM is Claude Code plus three environment
variables; the same `claude` binary against a different `ANTHROPIC_BASE_URL` is a different provider
with a different capacity API and a **contractual** concurrency ceiling (Lite 1 / Pro 1–2 / Max 2+,
three violations → ban). VERIFIED, `glm-spike.md` §12 via `ADAPTER-CONTRACT.md` §0. One method on the
platform adapter — `env_for(provider)` — plus a provider-side `capacity_probe` covers GLM, DeepSeek's
API lane, Kimi-as-endpoint and MiMo-as-model with **no new adapter**. That is the highest
value-per-hour move in the whole scan (VERIFIED as the research's own conclusion,
`ADAPTER-CONTRACT.md` §5.3) and it falls out of the object split for free.

**Roles.** Six ship in the box; the set is open (a role is a config object).

| Role | What it is | `needs` (default) | `needs_predictable_capacity` |
|---|---|---|---|
| `orchestrator` | the judging agent — "mind" (§2) | `send`, `answer`, `readContext`, `compact`, `resume` | **true** |
| `executor` | does one ticket | `launchHeadless`, `transcript`, `status`, `resume` | false |
| `validator` | independent check, when the engine declares one | `launchHeadless`, `transcript` | false |
| `sentinel` | the external health check, different account **and** different provider (R1-10) | `launchHeadless`, `preflight` | false |
| `ticket-watcher` | Д8 — watches the active ticket's source | `launchHeadless` | false |
| `answerer` | resolves `question.raised` when `mind` is busy or absent | `send`, `answer` | false |

`needs_predictable_capacity: true` is the design's use of the owner's own lever at [270]/[276] —
*"лише для оркестратора або лише для виконавця"*. A platform at capacity-tier 4 (nothing readable) is
simply **not eligible** for a role that declares it, and the config says so in words at negotiation
time rather than producing a broken guarantee at 03:00. VERIFIED as the research's recommendation,
`C4-capacity-research.md` §5.2.

---

## 2. Processes: what exists, and who starts what

Five process kinds. Only one of them is allowed to write the control plane.

| # | Process | Model tokens | Started by | Lifetime |
|---|---|---|---|---|
| 1 | **`orchd`** — the conductor | **zero, always** | `/orchestrator:run` → `bin/orchd start`, detached | the run |
| 2 | **`mind`** — the orchestrator agent | yes | `orchd` | restartable within one run |
| 3 | **workers** — executor / validator sessions | yes | `orchd` (never by `mind` directly) | one ticket (or a lineage of sessions for one ticket) |
| 4 | **`sentinel`** — external health check | yes, small | the OS scheduler (`launchd` agent), registered by `orchd` at PREFLIGHT | fires every `sentinel.interval`, exits |
| 5 | **watchers** — ticket-watcher, question-channel | mostly zero | `orchd` | the run, or per tick |

**`orchd` is deterministic and tokenless.** It is POSIX shell plus `jq` plus the adapters. It holds
`run.lock`, ticks, reads events, computes evidence, executes decisions, and writes every file in
the control plane. It spends no model tokens ever, which is the direct answer to
Д11's *"мінімальна кількість токенів"* [512] and to FIELD-NOTES §3.1 (one lane burned **445k tokens —
77% of all context growth in that window — on `echo idle`**, VERIFIED).

**`mind` is where judgement lives.** R1-09 [231] is explicit that the agent decides about silent
sessions, and R1-10 speaks of the orchestrator as a session that can die and be restarted. So `mind`
is a lane like any other, with role `orchestrator`, subject to the same context governor and the same
capacity governor. `orchd` asks `mind` a question only when the deterministic evidence is
**ambiguous** — defined in §10.3 — and records the answer with its authority basis (§13.4).

**The single-orchestrator invariant** [300–302] is enforced on `orchd`, not on `mind`:

> **Invariant SO-1.** At most one `orchd` process per run directory, enforced by `flock` on `run.lock`
> held for the process's entire lifetime. `orchd` never parses this file, never cleans it up, and
> never applies a TTL. The kernel is the authority. VERIFIED contract, `dsh`
> `native/system/docs/flock-contract.md`: *"Holder process exits or is killed → Acquisition succeeds
> after process exit, without a stale-lock timeout."*

> **Invariant SO-2.** At most one `mind` session per `orchd` epoch. `orchd` restarting `mind` is not a
> second orchestrator; it is the same orchestrator replacing its own brain. Every externally visible
> act carries the epoch (§8.3), so a stale `mind` waking from a quota pause is refusable and **loud**.

*(Tension recorded: the owner's words describe one orchestrator, singular. Splitting it into a
tokenless conductor and a model mind is this design's reading of [300–302] + Д11 + FIELD-NOTES §3.1,
not his statement. See §19.1.)*

**Who starts `orchd`.** `/orchestrator:run` is a thin command over a skill (OWNER-DECISIONS 6.6). The
skill resolves config, runs PREFLIGHT, prints the plan, and then:

```bash
setsid nohup "$PLUGIN/bin/orchd" start --run-dir "$RUNDIR" </dev/null >>"$RUNDIR/orchd.log" 2>&1 &
```

and **exits**. The invoking Claude Code session is not the run and holds nothing. This is deliberate:
FIELD-NOTES §12.4 records environment that detached processes do not inherit, and §11.6 records an
85-minute loop that ended only when an external `SIGTERM` arrived. A run that lives inside the
session that launched it dies with the owner's terminal.

`stdin` is closed on every spawn, everywhere, without exception. VERIFIED failure modes: Codex hangs
all night without `< /dev/null`; MiMoCode hangs forever; Aider needs a pty instead
(`ADAPTER-CONTRACT.md` §2.4.3).

---

## 3. The control plane: exact paths, formats, and the read/write protocol

### 3.1 The layout

```
<project>/.orchestrator/
├── control/                                  ← THE WATCHED DIRECTORY. survives runs.
│   ├── control.yaml                          stop verbs, live overrides, account assignments
│   ├── redlines.md                           R1-15's one text file
│   ├── stops/<name>.md                       stop-custom definitions
│   └── inbox/                                Д6 question channel (one file per answer)
├── adapters/{platforms,engines,boards,channels}/…   project-committed adapters
├── adapters.local/…                          personal, gitignored
├── current -> runs/20260919-201055           symlink, atomically replaced
└── runs/<run-id>/                            run-id = YYYYMMDD-HHMMSS, local time, never reused
    ├── run.lock                              flock latch. never read, never parsed, never removed.
    ├── lease.json                            atomic rewrite every 30 s by orchd
    ├── plan.json                             the frozen negotiation. written once. immutable.
    ├── journal.jsonl                         append-only. one line per lifecycle fact.
    ├── ledger.jsonl                          append-only. everything this run CREATED.
    ├── teardown.jsonl                        append-only. everything this run asserted GONE.
    ├── status.json                           projection. rewritten each tick. carries written_at.
    ├── lanes/<lane-id>/
    │   ├── lane.json                         immutable identity, written at bind
    │   ├── events.jsonl                      NORMALISED events. append-only. THE SEAM.
    │   ├── cursor.json                       {transcript_cursor, last_event_seq}
    │   └── handoff.md                        the lane's position file
    ├── tickets/<ticket-id>.json              projection of the board row + claim + digests
    ├── claims/<ticket-id>.d/                 mkdir-claim (local backend)
    ├── ctx/<session-id>.json                 context probe output, adapter-written
    ├── capacity/<account-id>.json            capacity reading cache, with observed_at
    └── answers.jsonl                         every question the orchestrator answered (§13.4)
```

### 3.2 Four file classes, four protocols

This is the part that stops the previous generation's worst failures from recurring. The rule:
**one file, one writer, one shape; a derived file is never an input to a decision.**

| Class | Files | Write protocol | Read protocol |
|---|---|---|---|
| **Latch** | `run.lock` | `flock(2)` / `lockf -k -t 0`, held for process lifetime | never read; acquisition *is* the read |
| **Journal** | `journal.jsonl`, `ledger.jsonl`, `teardown.jsonl`, `events.jsonl`, `answers.jsonl` | one `O_APPEND` `write(2)` of one line ≤ 64 KiB. never truncated, never rewritten, never globbed away | seek from a recorded byte offset; readers never lock |
| **Projection** | `status.json`, `lease.json`, `tickets/*.json`, `ctx/*.json`, `capacity/*.json` | `open(O_CREAT|O_EXCL)` a random-suffix sibling → write → `fsync` → `rename(2)`. never follows a symlink | read whole; if it fails to parse, use the previous in-memory value and journal `projection.invalid` |
| **Watched input** | `control/control.yaml`, `control/redlines.md`, `control/inbox/*` | cross-process writer lock; atomic rename through a random-suffix sibling; `0600` under `0700`; leaf-level edits preserve comments; self-write suppressed by content hash | poll by **content hash**, not mtime (§3.4) |

The journal rule is not decoration. FIELD-NOTES §2.1 (VERIFIED): `state/attention.tmp` was `: >`
truncated and `mv`'d over **every single watch cycle**, destroying everything any other process wrote
to it, unnoticed all night — *"including a measured rebuttal written while the orchestrator was
weighing killing a 378-test suite at test 240."* A journal that any component rewrites is not a
journal.

The watched-input protocol is lifted wholesale from `dsh`'s settings-file contract (VERIFIED,
`packages/settings/settings-file/README.md` via `ADOPTION-VERDICT.md` §4.9), including the two
properties that matter at 02:00: **boot fails loud, reload keeps last good.** A hand-edit that breaks
the YAML stops a *start*, and during a run it is journalled, notified, and the previous good document
stays in force. It never takes the run down.

### 3.3 `journal.jsonl` — the format

One line per lifecycle fact. Closed event vocabulary, versioned.

```json
{"seq":41,"at":"2026-09-19T20:11:03.114Z","epoch":7,"event":"orchestrator.claim",
 "run":"20260919-201055",
 "actor":{"platform":"claude-code","provider":"anthropic-max","account":"<profile-A>",
          "session_id":"ac653a10-…","pid":86924,
          "proc_start":"Sat Sep 19 12:51:09 2026","boot_id":1788417532,
          "host":"<host>"},
 "probe":{"cmd":["claude","agents","--json"],
          "env":{"CLAUDE_CONFIG_DIR":"/Users/…/.<switcher>/profiles/<profile>"},
          "match":{"sessionId":"ac653a10-…"},"alive_when":"row present"},
 "prev":{"epoch":6,"verdict":"dead","evidence":["pid 61402 absent","lease expired 41m"]}}
```

Vocabulary: `run.create · run.plan · orchestrator.claim · orchestrator.release · orchestrator.evict ·
lease.renew · lane.bind · session.spawn · session.close · session.observe · step.intent · step.result ·
health.probe · provider.failover · capacity.verdict · context.verdict · control.applied ·
control.refused · owner.action · ticket.claim · ticket.release · quarantine · notify.sent`.

Four properties, each earning its place:

1. **`epoch` on every line** is the fencing token *and* the crash-loop detector: N
   `orchestrator.claim` lines within T minutes with no `step.result` between them **is** a restart
   loop, findable by `grep`. That is the owner's own named fear — *"нескінченний цикл оркестраторів"*
   [300] — made mechanically detectable.
2. **`probe` is data, not code.** The journal carries *how to ask whether this actor is alive*, in the
   actor's own terms, including its env. This is [310] (*"для кожної платформи можна
   налаштовувати"*) and [312] (*"може написати свої власні скіли"*) expressed as a field. A platform
   nobody has installed costs one config entry, not a code change.
3. **`prev` records the verdict and the evidence** that the previous holder was dead. [300]'s
   *"переконуєш що воно не спрацювало, а після того запускаєш новий"*, written down and auditable.
4. **`step.intent` before the side effect, `step.result` after**, both carrying
   `action_id = run:epoch:lane:step:attempt`. The dedup key goes **into** the side effect — the ticket
   comment trailer, the branch name, the commit trailer — so a replayer finds it without trusting the
   journal. VERIFIED source of the rule: `dsh` `docs/subsystems/compaction.md` — *"a crash leaves a
   detectable orphan rather than a false claim of completion."* This is the antidote to FIELD-NOTES
   §11.4 (a merge printing `Already up to date` and doing nothing) and §12.7 (an audit log recording
   events that never happened).

### 3.4 `control/control.yaml` — the read/write protocol

One YAML document. Everything the owner can change *during* a run lives here. Written by
`orchestrator:stop`, `orchestrator:set`, or the owner's editor — all three go through the same writer
lock.

```yaml
schema: 1
stop:            null            # null | hard | soft | custom:<name>
intake:          open            # open | capped | frozen        (Д2)
on_only_blocked: wait            # wait | end | ask              (Д7)
overrides:                       # the RUN scope. highest precedence, ephemeral. §12.3
  concurrency.max: 2
  context.roles.executor.percent: 70
accounts:                        # R1-07: role → account, re-read live
  executor:     { account: <profile-A>, apply: soft }
  orchestrator: { account: work,       apply: hard }
answers_channel: control/inbox   # Д6
```

**Polling by content hash, not mtime.** `extract/corrections.md` records (VERIFIED) that mtime was a
*hedged example* — *"Можливо, там, наприклад, по даті"* — and that ANALYSIS-01 overstated it as the
named mechanism. Content hashing costs nothing at this scale and survives an editor that rewrites the
file without changing its content. **DEFAULT-PROPOSED:** `control.poll_seconds: 10`. Protects against
a stop verb sitting unseen for a whole lane tick.

**Apply classes.** Every leaf key in the schema carries `apply: hard | soft | next-run | frozen`,
with a per-key override in the file. This is R1-07's soft/hard [195] generalised to all configuration,
which is what the ANALYSIS cross-cutting finding 3 asks for.

| Class | Meaning | Example keys |
|---|---|---|
| `hard` | applies now; stops current work if it must | `stop`, `accounts.*` when marked hard, `redlines` |
| `soft` | applies at the next step boundary, or to the next task | `concurrency.max`, `context.*`, `accounts.*` default |
| `next-run` | recorded, refused for this run, reported in status | `notifications.channels`, `board.backend` |
| `frozen` | changing it invalidates the negotiation; refused, loudly | `engine.id`, `lanes[*].platform`, `worktree.owner` |

A `frozen` key changed mid-run is **journalled as `control.refused` and surfaced in `status.json`**,
never silently ignored. Sortie's config doc is the precedent for documenting the keys that
deliberately do not reload (VERIFIED, `LANDSCAPE.md` §5 "R9").

---

## 4. The platform adapter: what it is, and how one plugs in

### 4.1 The four files

An adapter is a **directory**, discovered on a path, containing exactly four things. No registration,
no code change, no rebuild.

```
adapters/platforms/<id>/
├── manifest.json     the capability map + provider axes. static. no network. no tokens.
├── adapter            an executable. 17 subcommands. JSON on fd 1, logs on fd 2.
├── normalize          an executable (or a .jq file). platform-native → normalised events.
└── probes.json        liveness / identity / capacity probes AS DATA (see §3.3 property 2)
```

**Discovery order** (first hit wins), mirroring the owner's config ranking — personal beats
project-committed beats shipped (OWNER-DECISIONS 4.15):

```
1  ./.orchestrator/adapters.local/platforms/<id>/          personal, this project, gitignored
2  <config-root>/shared/orchestrator/adapters/platforms/<id>/   personal, this machine
3  ./.orchestrator/adapters/platforms/<id>/                 project, committed
4  <plugin>/adapters/platforms/<id>/                        shipped with the plugin
```

`<config-root>` resolves exactly as OWNER-DECISIONS 3.3 requires: `CLAUDE_CONFIG_DIR` verbatim if set,
otherwise `os.homedir()` + `/.claude`. Never a literal `~` in a file call.

### 4.2 `manifest.json`

```json
{
  "contract_version": 1,
  "id": "claude-code",
  "binary": "claude",
  "version_pin": "2.1.278",
  "transport": "exec",
  "home_env": "CLAUDE_CONFIG_DIR",
  "capabilities": {
    "A_launch":      "native",   "B_identity":  "native",
    "C_transcript":  "native",   "D_context":   "native",
    "E_quota":       "native",   "F_accounts":  "native",
    "G_send":        "native",   "G_answer":    "emulated",
    "H_sandbox":     "native",   "I_extend":    "native"
  },
  "quotaModel": "Window",
  "idAssignment": "client",
  "attachable": true,
  "sandbox": true,
  "hazards": ["keychain-gui-dialog-on-first-use-per-account"],
  "ops": { "launchAttached": "native", "costMeter": "emulated", "…": "…" }
}
```

Closed vocabulary per axis: `native | emulated | impossible | unknown | undocumented`. Two rules,
taken verbatim from GSD's own `host-integration.cjs` (VERIFIED, `C9-process-delivery-research.md`
§3.1) because the owner's own engine already solved this problem in the same shape:

- **An out-of-vocabulary value is not a capability verdict.** It validates, and it never propagates
  into effective axes.
- **`undocumented` ≠ `impossible`.** A missing declaration and a declared absence are different facts
  and are reported with different words. GSD's own review note is the argument: telling a user their
  runtime *"declares no executor-isolation primitive"* when the **resolver** failed *"is false"*.

**`capabilities()` must be derivable with no network call and no model token** (`ADAPTER-CONTRACT.md`
§2.0). And the one rule that the whole design rests on: *never report `native` for a capability whose
only implementation is a regex over English prose.*

### 4.3 The 17 operations

Twelve REQUIRED for tier-1, five optional with a defined degradation. Signatures and contracts are
`ADAPTER-CONTRACT.md` §2.1–§2.3 and are not restated here; what this document adds is **the process
contract they run under**.

| Group | Ops |
|---|---|
| negotiation | `capabilities` |
| lifecycle | `preflight` · `launchHeadless` · `launchAttached`\* · `resume` · `stop` |
| observation | `status` · `transcript` · `readContext` · `costMeter`\* |
| non-negotiables | `compact` · `readCapacity` · `detectLimitHit` · `selectAccount` · `send` · `answer` |
| provider split | `env_for(provider)` |

\* optional.

**Calling convention.** `adapter <op> --lane <lane.json> [--handle <h>] [args…]`. JSON result on fd 1,
free-form logs on fd 2 (GLM always writes `[claude-code:unrecognized_model]` to stderr; Cursor writes
a 502-byte ANSI splash to *stdout* — VERIFIED, `ADAPTER-CONTRACT.md` §2.4.7). The core never reads
fd 2 for meaning.

**Exit codes — the adapter's own, not the underlying CLI's.** Borrowed from `acpx` because across
44 published versions its CHANGELOG contains **no entry that changes an exit code** (VERIFIED,
`ADOPTION-VERDICT.md` §3), which makes it the only stable exit contract in the field.

| Code | Meaning |
|---|---|
| `0` | ok |
| `1` | agent / runtime error |
| `2` | usage error (the core called it wrong — a bug in the core) |
| `3` | timeout (the external wall-clock fired) |
| `4` | no such session |
| `5` | **needs a human** — a question the adapter may not answer (first-class, §9.4) |
| `64` | capability not supported by this adapter (declared, not a failure) |
| `65` | contract violation — the adapter caught itself about to lie |
| `70` | environment error (binary missing, credential dead) |
| `130` | interrupted |

> **Invariant AD-1. Never branch on the underlying CLI's exit code.** VERIFIED failures: Aider
> `main.py:1133` returns 0 on auth failure, rate limit and success alike; pi `--mode json` exits 0 on
> provider failure; GLM exits 0 on quota exhaustion *with* `subtype:"success"`; MiMoCode's exit code
> is always 0. The adapter translates; the core sees only the table above.

The remaining nine invariants of `ADAPTER-CONTRACT.md` §2.4 — own stdin, impose an external
wall-clock timeout, pin the version and disable auto-update, pin the model explicitly, keep stdout and
stderr separate, union the roster across accounts, re-attach handlers on every resume, assert teardown
by process rather than by the command's word, never trust HTTP 200 or a `success` string — are
**conformance tests**, not prose. See §4.5.

### 4.4 `probes.json` — liveness and identity as data

```json
{
  "identity": { "cmd": ["claude","--print","/status"], "env_from": "account",
                "extract": {"account":"$.oauthAccount.emailAddress"},
                "cost": "zero-model", "timeout_s": 10 },
  "alive":    { "cmd": ["claude","agents","--json"], "env_from": "account",
                "match": {"sessionId":"{{session_id}}"}, "alive_when": "row present",
                "status_field": "status", "blocked_field": "waitingFor" },
  "capacity": { "kind": "provider_api", "cmd": ["…"], "buckets_at": "$.five_hour,$.seven_day",
                "min_interval_s": 3600, "burst": 2 }
}
```

Probes are data so that a platform nobody has installed costs **one config entry** and an owner-written
skill is a legal probe (`{"cmd":["claude","-p","/my-skill"], …}`) — R1-10 [310], [312] directly.

### 4.5 Conformance: `orchestrator:adapter verify <id>`

A shell script. Runs the 17 ops against recorded fixtures, then a **live smoke** against the
configured account. Exit `0` pass · `65` contract violation (named) · `70` environment.

Ten of the checks are the invariants above, mechanised. Three are the ones that catch lying manifests:

- **`compact` must return a `Proof`.** A typed event, a durable transcript entry, or a *measured* drop
  in used tokens with provenance. An adapter returning success without proof fails with `65`. This is
  the FIELD-NOTES "reports success and does nothing" class (§4.1, §11.4) made mechanically impossible
  to declare.
- **`send` must distinguish `accepted` from `delivered` from `processed`.** The fixture asserts that
  an adapter which only has an enqueue receipt reports `accepted` and nothing stronger. Kimi's 200
  means *accepted*, never *ran* (VERIFIED).
- **`readCapacity` must return the sum type, never a scalar**, and `Unreadable` must carry a typed
  reason. A `200` the adapter cannot parse must raise, not return zero: Z.ai's
  `TOKENS_LIMIT`→`CREDIT_LIMIT` rename rendered **0% used**, which reads as *plenty of room*
  (VERIFIED, `C4-capacity-research.md` §5.3).

> **Gate.** A lane whose adapter has not passed `verify` **today** is not dispatchable.
> `ADAPTER-CONTRACT.md` §3-J: *"Preflight must refuse to dispatch to a lane that has not been proven
> today."* **DEFAULT-PROPOSED:** `adapter.verify_max_age_hours: 24`. Protects against §6.8's
> under-rated overnight killer — Amp shipped five releases in fifteen hours; Copilot 835 versions in
> twelve months; a run that starts on one flag surface and finishes on another is indistinguishable
> from a bug in the orchestrator.

### 4.6 `acpx` as a transport, not as the seam

`acpx@0.17.0`, pinned exactly, is adopted as the **default transport for the platforms it supports**
(`transport: "acpx"` in the manifest). It retires the terminal séance: a prompt is an argument, a
timeout is exit `3`, an interrupt is `130`, and liveness is a process rather than a screen — which is
six FIELD-NOTES records deleted at once (VERIFIED table, `ADOPTION-VERDICT.md` §3).

The four rules ship with it, unchanged: pin exactly (40 `Breaking` sections in 44 releases); depend
only on subcommand names, exit codes and `--format json --json-strict`; treat exit `5` as a
first-class outcome; keep the queue, the stop verbs, the board write-back and the quota policy in our
own code.

**The seam is above acpx, deliberately.** A platform acpx does not support declares `transport: exec`
or `rpc` or `http` or `pty` and implements the same 17 ops. If acpx breaks, the exit path is *delete
the dependency and set `transport: exec`* — an afternoon, and no other file changes. That is the test
of whether the seam is real.

**`pty` is tmux only.** Retire AppleScript: Terminal.app is refused by the old code's own hand
(`harness-term.sh:163-181` — `send` and `key` *"explicitly refused as undrivable"*, VERIFIED), and
iTerm2/AppleScript is where every recorded delivery failure lives. tmux runs *inside* an iTerm2 window
so the owner's visible terminals still look like his terminals (`claude --tmux` exists and *"uses
iTerm2 native panes when available"*, VERIFIED). **DEFAULT-PROPOSED:** `pty.backend: tmux`,
`pty.host: iterm2-if-present`. Protects against the entire §4.4/§4.5 class in `C7`.

---

## 5. Capability negotiation — the run phase that makes the rest honest

Three documents, in order. All deterministic, all zero-token.

```
manifest.json  (what the adapter claims)
      ∩
preflight()    (what this machine and this account prove TODAY — may only downgrade)
      ↓
requirements   (what THIS run needs, derived from the resolved config)
      ↓
plan.json      (the negotiated result. written once. immutable for the run.)
```

### 5.1 `requirements.json` — in the core, the one place platforms are *not* named

```json
{ "contract_version": 1,
  "requirements": [
    {"id":"R1-08.hard-compact","axis":"D_context","needed_when":"context.mode == hard",
     "on_impossible":"degrade","degrade_to":"close-and-reseed","owner_item":"R1-08"},
    {"id":"R1-06.wait-for-reset","axis":"E_quota","needed_when":"capacity.on_exhausted == wait",
     "on_impossible":"deny-role","applies_to_roles":["*needs_predictable_capacity"],"owner_item":"R1-06.1"},
    {"id":"R1-07.role-accounts","axis":"F_accounts","needed_when":"always",
     "on_impossible":"refuse-run","owner_item":"R1-07"},
    {"id":"R1-11.takeover","axis":"A_launch","needed_when":"runtime.visibility == visible",
     "on_impossible":"degrade","degrade_to":"handoff","owner_item":"R1-11"},
    {"id":"D12.stop-hard-midturn","axis":"G_send","needed_when":"always",
     "on_impossible":"degrade","degrade_to":"kill","owner_item":"Д12"},
    {"id":"R1-11.answer-question","axis":"G_answer","needed_when":"authority.may_answer",
     "on_impossible":"degrade","degrade_to":"prevent-the-question","owner_item":"R1-11"},
    {"id":"R1-15.floor","axis":"H_sandbox","needed_when":"always",
     "on_impossible":"degrade","degrade_to":"worktree+denylist","owner_item":"R1-15"},
    {"id":"R1-03.engine-in-session","axis":"I_extend","needed_when":"engine.needs_subagents",
     "on_impossible":"deny-role","applies_to_roles":["executor"],"owner_item":"R1-03"}
  ]}
```

Every requirement names its owner item. **Adding a requirement is a row here, and every existing
manifest answers it `unknown`** — which degrades closed. A new requirement therefore cannot silently
pass on an old adapter. That property is the whole reason `unknown` is in the vocabulary.

### 5.2 The negotiation algorithm

```
for lane in fleet:
    caps  = manifest(lane.platform)
    caps  = downgrade_only(caps, preflight(lane.account))     # never upgrades
    for r in requirements where r.needed_when(config):
        level = caps[r.axis]
        native | emulated -> ok            (emulated records its cost in plan.json)
        undocumented      -> if probes.json has a probe, run it; else treat as impossible
        unknown           -> treat as impossible
        impossible        -> apply r.on_impossible
```

`on_impossible` has exactly four values.

| Value | Effect | When it is right |
|---|---|---|
| `deny-role` | the lane keeps existing but may not hold that role | the capability is required *for a role*, and another lane has it |
| `degrade` | take the named fallback and **record the weakened requirement in `plan.json`** | there is an honest, platform-independent fallback |
| `ask` | pause PREFLIGHT and ask the owner, with the Ukrainian question text from the requirement row | the trade is his to make |
| `refuse-run` | do not start; print which lane, which axis, which owner item | the requirement has no fallback and no role split saves it |

**DEFAULT-PROPOSED:** `negotiate.on_unknown: impossible`. Protects against the single failure this
whole document exists to prevent — *"an adapter that reports `native` and then degrades at 03:00."*
**DEFAULT-PROPOSED:** `negotiate.interactive: ask` when a TTY is present, `refuse-run` when not.
Protects an unattended start from silently choosing the weaker half of a trade the owner never saw.

### 5.3 `plan.json` — the frozen result

Written once, at the end of PREFLIGHT. Never rewritten. Anything that would change it is a `frozen`
config key (§3.4).

```json
{"schema":1,"run":"20260919-201055","created_at":"…","contract_version":1,
 "engine":{"id":"gsd","version":"1.14.0","points_declared":["start","step","progress","completion",
                                                            "branching","verification","delivery","state_ref"]},
 "board":{"adapter":"github-issues","repo":"…","statuses_verified":true},
 "lanes":[
   {"id":"L1","role":"orchestrator","platform":"claude-code","provider":"anthropic-max",
    "account":"<profile-B>","verified_at":"…","capacity_model":"Window",
    "emulations":[], "denied_roles":[]},
   {"id":"L2","role":"executor","platform":"codex-cli","provider":"openai",
    "account":"personal","verified_at":"…","capacity_model":"Window",
    "emulations":["B_identity: id minted server-side; first 8s unrecoverable by id"]},
   {"id":"L3","role":"executor","platform":"claude-code","provider":"glm",
    "account":"zai","capacity_model":"Window","concurrency_ceiling":2,
    "notes":["contractual ceiling, not technical: 3 violations → ban"]}],
 "weakened":[
   {"owner_item":"R1-08","lane":"L4","axis":"D_context","was":"hard","now":"close-and-reseed",
    "consequence":"ticket→session becomes one-to-many for this lane"}],
 "denied":[
   {"owner_item":"R1-06.1","lane":"L5","platform":"pi","reason":"quotaModel None",
    "effect":"not eligible for any role with needs_predictable_capacity"}]}
```

`weakened[]` and `denied[]` are printed at start and carried into `status.json`. **A requirement that
quietly stopped holding is the failure mode this design is most afraid of**, so it is written into a
file the owner can read at any hour without asking a model.

### 5.4 The two capacity worlds, as a type

```
Capacity = Window { used_pct, resets_at }
         | Credit { remaining, unit, no_reset: true }
         | None
         | Unreadable { reason: auth_expired|throttled|unsupported|network|schema_unknown }
```

Policy per variant, decided once, centrally — never per adapter, because *"a rule replicated per
adapter is a rule a new adapter can omit, and omission here is silent"* (VERIFIED, Sortie ADR 0025 via
`LANDSCAPE.md` §4):

| Variant | Policy |
|---|---|
| `Window` | thresholds in **percent**; on exhaustion **pause until `resets_at`, auto-resume** (R1-06.1 exactly) |
| `Credit` | thresholds in **money**; on ceiling **stop and notify a human**, never auto-resume — there is nothing to wait for |
| `None` | local ledger, conservative ceiling, react to `detectLimitHit` only, and **never hold a role with `needs_predictable_capacity`** |
| `Unreadable` | policy is **per stop-class**: a soft stop may proceed; a **hard** stop must not silently become no stop |

**DEFAULT-PROPOSED:** `capacity.on_unreadable.hard: hold-and-escalate`,
`capacity.on_unreadable.soft: proceed`, and `schema_unknown` is always **noisy**. This is the highest-
value single correction in the research: the previous generation's default was
`limits.on_unreadable: proceed`, combined with a schema drift that made *every* read unreadable, so
the run kept going with no cap enforcement at all, for days (VERIFIED, FIELD-NOTES via
`C4-capacity-research.md` §5.3).

**DEFAULT-PROPOSED:** `capacity.spend_ceiling_usd: null` with a **start-time refusal** if any lane's
`capacity_model == Credit` and no ceiling is set. Protects against the DeepSeek/Amp/pi case where
*"run until the limit"* has no natural stopping point — it just costs money.

---

## 6. The normalised event vocabulary — the one seam the core reads

`lanes/<lane-id>/events.jsonl`. Produced by `normalize`, consumed by `orchd`. The core opens no
platform-native transcript, ever.

### 6.1 The closed set

```
lifecycle  session.spawned · session.resumed · session.exited · session.lost
turn       turn.started · turn.completed · turn.failed
work       tool.called · tool.denied · output.written
blocking   question.raised · question.answered · permission.requested · permission.decided
capacity   capacity.read · limit.hit
context    context.read · compaction.started · compaction.proved · compaction.unproven
engine     step.started · step.finished · step.verdict · engine.needs_human
```

Twenty-four kinds, versioned by `contract_version`. Six of them (`turn.*`, `tool.called`,
`question.raised`, `compaction.*`, `step.*`) are the ones the governors in §10 act on.

### 6.2 The record

```json
{"seq":1204,"at":"2026-09-19T21:04:18.221Z","epoch":7,"lane":"L2","session":"01a0b9dd-…",
 "kind":"context.read",
 "source":{"adapter":"codex-cli","op":"readContext","native_kind":"token_count"},
 "provenance":{"text":"verbatim","value":"provider_measured"},
 "payload":{"used":118442,"window":272000,"pct":43.5,"is_estimated":false}}
```

**Provenance is two-axis and mandatory**, copied from agent-deck's `ctxinspect` (VERIFIED,
`LANDSCAPE.md` §4): `text ∈ {verbatim, reconstructed, absent}` says how good the bytes are;
`value ∈ {provider_measured, tokenizer, estimated, derived, unknown}` says how good the number is.
Collapsing them onto one axis forces a lie in one direction. Its governing rule is adopted verbatim:
**a wrong token number is worse than no token number**, and **numbers cannot exist without
provenance** — the event schema has no path that produces a bare number.

### 6.3 Four hard rules for `normalize`

1. **An adapter that cannot produce an event emits nothing.** It never synthesises one. Absence is
   `unknown`, never `false`. `missing ≠ zero`.
2. **`session.lost` ≠ `session.exited`.** The first says the adapter lost the channel; the second says
   the process exited with a code. Conflating them is how a pipe-only transcript (Amp, `dsh`) reads as
   a finished session.
3. **Every event carries `epoch`.** An event from a lower epoch is recorded and **discarded, never
   applied** — the fence that stops a paused orchestrator waking after a quota reset and merging a
   phase the new one already merged.
4. **`seq` is dense per lane and assigned by `normalize`**, not by the platform. Platform ids are
   never the primary key: key on `ticket_id`, store `(platform, account, session_id)` as an attribute,
   and make it a **list**, because close-and-reseed turns one ticket into many sessions (VERIFIED,
   `ADAPTER-CONTRACT.md` §6.3).

### 6.4 Where the transcript has to be persisted by us

Where the transcript exists only on the pipe (Amp, `dsh`), the adapter **tees it to disk under the run
directory and says so in `capabilities()`** (`C_transcript: "emulated"`). Otherwise a dead supervisor
destroys the evidence — which collides head-on with R1-10's requirement that the orchestrator's own
death be survivable.

---

## 7. The run state machine

```
                 ┌──────────────┐
                 │ CONFIGURING  │  config resolved; missing answers asked (OWNER-DECISIONS 6.1)
                 └──────┬───────┘
                        ▼
                 ┌──────────────┐  adapters verified · accounts proven · board statuses checked
                 │  PREFLIGHT   │  notification channels proven · worktree owner asserted
                 └──┬────────┬──┘
           refuse   │        │ ok
                    ▼        ▼
              ┌─────────┐  ┌──────────┐   plan.json written, immutable
              │ ABORTED │  │ PLANNED  │
              └─────────┘  └────┬─────┘
                                ▼
   ┌────────────────────── ┌─────────┐ ──────────────────────┐
   │                       │ RUNNING │                       │
   │        ┌───────────── └────┬────┘ ─────────────┐        │
   │        ▼                   │                   ▼        │
   │  ┌──────────┐              │             ┌──────────┐   │
   │  │ HOLDING  │  human owed  │  quota      │  PAUSED  │   │
   │  └────┬─────┘              │             └────┬─────┘   │
   │       │ answer arrives     │    resets_at     │         │
   │       └────────────────────┴──────────────────┘         │
   └───────────────────────────┬─────────────────────────────┘
                               ▼  no ready work · or stop-soft · or ceiling reached
                        ┌────────────┐
                        │  DRAINING  │  intake closed; lanes finish their current step
                        └─────┬──────┘
                              ▼
                        ┌────────────┐  iterate ledger.jsonl; assert each entry gone
                        │  TEARDOWN  │
                        └─────┬──────┘
                              ▼
                        ┌────────────┐  exit 0 clean · 75 orphans · 70 unassertable
                        │   ENDED    │
                        └────────────┘
                              ▲
   RECOVERING ────────────────┘   (entered on orchd start when `current` exists; §14)
```

**Transitions, with trigger and actor.**

| From → To | Trigger | Fired by |
|---|---|---|
| CONFIGURING → PREFLIGHT | config resolved, no unanswered required key | `/orchestrator:run` skill |
| PREFLIGHT → ABORTED | a `refuse-run` requirement; or a `frozen` collision; or a required notification channel unproven | `orchd`, exit `78` |
| PREFLIGHT → PLANNED | every lane verified today; `plan.json` written | `orchd` |
| PLANNED → RUNNING | `run.lock` acquired, epoch minted, `mind` spawned | `orchd` |
| RUNNING → PAUSED | `Window` capacity crosses `hard` threshold, or `limit.hit{kind:window}` | capacity governor |
| PAUSED → RUNNING | `now >= resets_at + resume_margin` **and** a fresh reading confirms headroom | capacity governor |
| RUNNING → HOLDING | every unfinished ticket is `needs-input`, and `on_only_blocked: wait` (Д7 default) | `orchd` |
| HOLDING → RUNNING | an answer lands in `control/inbox/`, or new ready work appears | inbox watcher |
| HOLDING → DRAINING | `on_only_blocked: end`, or the owner writes `stop: soft` | control watcher |
| RUNNING → DRAINING | board ready-count 0 **and** every lane IDLE (Д3) — **the terminal condition** | `orchd` |
| any → DRAINING | `stop: soft` | control watcher |
| any → TEARDOWN | `stop: hard` | control watcher |
| DRAINING → TEARDOWN | every lane RETIRED | `orchd` |

**PAUSED is not HOLDING.** PAUSED has a clock and resumes itself; HOLDING has a human and does not.
Conflating them is the mistake that makes a run wait forever on a `Credit` platform, where there is no
`resets_at` to wait for.

---

## 8. The lane state machine

```
UNBOUND ──negotiated──► NEGOTIATED ──preflight ok──► IDLE
IDLE ──claim won──► CLAIMED ──worktree ready──► DISPATCHED ──session.spawned──► WORKING

WORKING ──question.raised (unanswerable)──► BLOCKED_HUMAN
WORKING ──permission.requested──►           BLOCKED_TOOL ──permission.decided──► WORKING
WORKING ──context threshold──►              COMPACTING ──compaction.proved──► WORKING
WORKING ──capacity hard / stop-soft──►      SUSPENDED  ──resume──► WORKING
WORKING ──step.finished(last)──►            FINISHING ──► VERIFYING ──► DELIVERING ──► RELEASING ──► IDLE

any ──3 identical failures (Д5)──► QUARANTINED
any ──adapter exit 4 / session.lost──► LOST ──recovery ladder──► {WORKING | DISPATCHED | QUARANTINED}
any ──teardown──► RETIRED
```

Notes that matter:

- **`BLOCKED_HUMAN` is a distinct state from `WORKING`.** Conflating them is how an overnight run dies
  quietly (VERIFIED, `qwen-code-spike.md` via `ADAPTER-CONTRACT.md` §2.2). It is also where adapter
  exit `5` lands.
- **`COMPACTING` is a state, not an event**, because it can fail, and because any reading taken inside
  `[compaction_started, +grace]` must be **discarded, not queued** (VERIFIED,
  `C5-context-research.md` §5.1).
- **`LOST` is not `QUARANTINED`.** Losing the channel is the adapter's problem; three identical
  failures is the work's problem.
- **`QUARANTINED` is terminal for the run.** Д5 [442]: three identical failures → notify through the
  configured channel and stop, or just stop; anything beyond that needs the owner's permission. The
  retry budget is **charged before dispatch, retained across an `orchd` restart, refunded only on an
  explicit pre-acceptance rejection**, and exhaustion **tombstones** rather than loops (VERIFIED
  design, OpenClaw `docs/gateway/restart-recovery.md` via `ADOPTION-VERDICT.md` §4.5). That is what
  makes Д5's count survive the orchestrator's own death, which is the case where looping forever
  actually happens.

### 8.1 Claiming

**The single-claimer rule.** Only `orchd` moves a ticket to `active`. Executors never claim. This
follows directly from SO-1 and from the previous generation's practice.

**Belt and braces — an atomic claim that costs almost nothing**, because the single-claimer rule is
one crashed-and-restarted orchestrator away from being violated (Д10 [497]):

| Board | Claim primitive | Evidence |
|---|---|---|
| local files | `mkdir .orchestrator/runs/<run>/claims/<id>.d` | **1 winner at 50-way, measured** (VERIFIED, `C3` §5.4) |
| GitHub Issues | `POST /git/refs {"ref":"refs/heads/claim/<id>"}` → 422 if taken | **measured** (VERIFIED) |
| ClickUp | no CAS exists — assignee + re-read, and **the config output says so** | VERIFIED absence |

The claim record is `{holder, run_id, epoch, taken_at, heartbeat_at}`, and `heartbeat_at` is refreshed
on every lane tick.

### 8.2 Releasing

Release only if **idle beyond the threshold AND the readiness floor still passes**; otherwise print
`STUCK … needs a human` and leave it. Two fixes the previous generation needs, both VERIFIED defects:
drive idleness from **`heartbeat_at` in the claim**, never from the board's `updatedAt` (which the
orchestrator's own comments bump); and **remove the previous state label** on transition so a ticket
cannot hold `blocked` and `done` at once.

**DEFAULT-PROPOSED:** `claim.stale_seconds: 1800`. Protects against a crashed lane holding a ticket
for the rest of the night; long enough that a normal long turn does not trip it.

**Withholding, from Sortie's ADR 0020** (VERIFIED, `LANDSCAPE.md` §4): a lane that exits cleanly having
produced nothing must not take the same path as one that did the work. `delivery.evidence:
observed | strict | off`, **DEFAULT-PROPOSED `observed`** — withhold the `done` transition only on
*positively observed* emptiness. The asymmetry is the argument: *"The first error is silent and leaves
the system; the second is visible and stays inside it."*

### 8.3 The fence

`epoch = max(lease.epoch, max epoch in journal) + 1`, minted at each `orchestrator.claim`. It is
stamped into every externally visible act:

- ticket comments and transitions: a trailer `orchestrator-epoch: 7`
- session names: `o7-x-T118` — so a stale-epoch session is identifiable at a glance in
  `claude agents --json` and in a terminal title
- commits the orchestrator itself makes: an `Orchestrator-Epoch: 7` trailer
- every `step.intent` / `step.result`

**The rule the fence buys:** a step may only be committed by the epoch that opened it; anything
arriving from a lower epoch is recorded and discarded. `lockf` alone covers crash and SIGKILL, which
is most of reality; the epoch covers **pause**, which is the owner's own named death mode
(*"кредит закінчився"* [266]).

---

## 9. The engine seam — driving GSD (or a custom process) without owning it

### 9.1 The descriptor

`adapters/engines/<id>/engine.json` plus `engine.md` (prose the session reads, rendered into the
prompt). Eight interface points. **Only `start` is mandatory.** Everything else absent →
`SAFE_DEFAULTS`, the most restrictive value per point, and reported as `undocumented` (not `none`).

| Point | What the engine declares | If absent, the orchestrator… |
|---|---|---|
| `start` | how to begin one unit of work (command / skill / prose prompt) | **cannot run this engine** — the only mandatory point |
| `step` | what a step boundary is, and how one is signalled | falls back to `turn.completed`; R1-08 soft mode and `stop-soft` degrade to turn granularity |
| `progress` | a command returning machine-readable progress | reports `progress: unavailable` and **never guesses a percentage** |
| `completion` | how done / failed / needs-human is signalled | falls back to session exit + a declared marker file |
| `branching` | who creates branches and worktrees, and from which base | assumes the engine owns nothing and takes ownership itself |
| `verification` | whether the engine verifies, and how to read its verdict | records `verification: engine-none` and **imposes nothing** (R1-13) |
| `delivery` | whether the engine opens PRs / merges | takes delivery itself, subject to §9.5 |
| `state_ref` | where the engine's own record lives, and its witness anchor | keeps its own record (R1-06.3's third case) |

Rules, taken from GSD's own `host-integration.cjs` so the shape is one the owner's engine already
speaks: closed vocabulary per field; `undocumented ≠ none`; `SAFE_DEFAULTS` most restrictive;
`protocol_version` integer plus a `--exit-contract`-style pin so a descriptor written for v1 keeps
working.

### 9.2 Three descriptors ship, and they prove the range

**`gsd` — all eight points populated.** Every command below is VERIFIED as executed on this machine
(`C9-process-delivery-research.md` §3.1), costs zero model tokens, and returns JSON:

```json
{"id":"gsd","protocol_version":1,"runtime":"@opengsd/gsd-core","version_probe":["gsd-tools","runtime-identity"],
 "points":{
   "start":      {"kind":"command","value":"/gsd:progress --next","autonomous":"/gsd:autonomous"},
   "step":       {"kind":"hook","point":"execute:post","emits":"step.finished",
                  "install":"gsd_run loop render-hooks execute:post"},
   "progress":   {"cmd":["gsd-tools","progress"],"format":"json",
                  "map":{"percent":"$.percent","phase":"$.phases[-1].number"}},
   "completion": {"cmd":["gsd-tools","smart-entry"],"done_when":"/100% · complete/"},
   "branching":  {"cmd":["gsd-tools","state","--pick","use_worktrees"],
                  "isolation":["gsd-tools","dispatch-isolation"],
                  "base_check":["gsd-tools","worktree","base-check"]},
   "verification":{"cmd":["gsd-tools","windows","status"],"format":"json",
                  "human_needed_when":"$.entries[?(@.status=='human_needed')]"},
   "delivery":   {"kind":"command","value":"/gsd:ship"},
   "state_ref":  {"path":".planning/STATE.md","anchor":"state_head","kind":"git-sha"}}}
```

Two things make this an *adapter* rather than a fork:

- **The step marker is installed through GSD's own twelve named loop-hook points**
  (`discuss:pre … ship:post`, VERIFIED) as a `contribution` hook. The orchestrator gets a
  step-boundary signal **without patching GSD**, which is the concrete meaning of "drives it without
  owning it".
- **`state_ref` implements R1-06.3 literally.** [189]: *"нічого не треба окремо записувати, а лише
  записувати оце референс"*. The journal line is
  `{"event":"step.result","process":"gsd","ref":".planning/STATE.md","state_head":"5154f24…","read_at":"…"}`.
  GSD's `STATE.md` frontmatter already publishes `state_head` as a git SHA (VERIFIED).
  **One caution the owner should hear:** that same file's own `last_activity` contains the sentence
  *"the false claim that state.json is derived from that table withdrawn and the file declared
  hand-maintained"*. A process's own record can be hand-maintained, and a reference to it is then a
  reference to a claim. His three-way rule at [171] already covers this; what is **open** is how the
  orchestrator decides a process's record is insufficient.

**`feature-dev` — only `start`.** VERIFIED: 125 lines of pure prose, no state file, no status command,
no git, no resumability, human-gated by design. It exists in the box as the **calibration**: if the
contract cannot express `feature-dev`, it is a GSD-shaped contract wearing a generic name. GSD is the
outlier, not the norm.

**`custom` — the owner's "повністю свій" branch.** A step schema, nine keys, seven optional
(`C9` §5.2); minimum viable step is two keys:

```yaml
steps:
  - id: build            # required, unique, stable
    run: npm run build   # required: exactly one of run | uses
    name: Build          # optional
    needs: [install]     # optional — the DAG edge
    if: "…"              # optional
    success: "exit 0"    # optional; DECLARED, never guessed
    timeout: 30m         # optional
    retry: {max: 2, backoff: 60s, never: [auth_expired]}
    artifacts: [dist/]   # optional — the existence test
    on_fail: stop        # stop | continue | ask
```

`artifacts` is what makes the owner's *"чи буде перевірка"* [118] answerable **without imposing a
check**: the step declared it would produce this file; the file is there or it is not. That is an
existence test, not a quality judgement, so it does not cross the R1-13 line.

### 9.3 R1-03's no-mixing rule, enforced mechanically

> **Invariant EN-1.** `plan.json` carries exactly one `engine.id`. A second engine descriptor
> referenced anywhere in the resolved run config is a `refuse-run` at PREFLIGHT, with a message naming
> both. *"Комбінувати ні, тут або або"* [118].

The one thing that is *not* a second engine, stated explicitly so nobody argues about it at 03:00: the
orchestrator's own internal steps — claim, dispatch, compact, deliver, teardown — are not a process.
They are the harness. If they were an engine, R1-03 would forbid the plugin from existing.

### 9.4 A question is a terminal outcome, and that is an architectural fork the owner has not ruled on

Both candidate projects, and the field, are **closing the door** on "the orchestrator answers a
session's own question": `dsh` disables `AskUserQuestion` and fails blocking dialogs closed; acpx
makes fixed-choice questions fail with `user-answer-required` and says it *"takes precedence over
`--approve-all`, permission policies, and embedding host permission callbacks"*; Claude Code headless
`AskUserQuestion` **reports "answered" with `answers:{}`** — a silent-corruption bug, not a risk
(VERIFIED, `C7` §4.1). Meanwhile R1-11 [324] is unambiguous: *"якщо він раптом використовує ask user
question, то оркестратор може відповідати на ці питання, і це повністю окей."*

**The design that keeps his decision.** For every session the orchestrator runs headless:

1. **Disallow the platform's native user-question tool.**
2. **Inject one MCP tool, `ask_supervisor(question, options[])`,** which the orchestrator answers. MCP
   is supported by Claude Code, Codex, Gemini CLI and opencode, so **one implementation covers every
   platform**, including the two that expose no question event at all (VERIFIED end to end, `C7` §P2).
3. **Also watch for question-shaped assistant text** as a fallback, because a session that ignores the
   instruction and finds no `AskUserQuestion` will improvise.
4. **Interactive PTY sessions keep the native tool** — there it works, and a human may want to answer.
5. Adapter exit `5` and `question.raised` are first-class: the lane goes `BLOCKED_HUMAN`, the ticket
   goes `needs-input` with a `reason`, and the question is written to `control/inbox/` — a **durable
   pending state with four terminals** (`answered | timeout | run_terminal | interrupted`), copied
   from claudexor's `InteractionStore`, the only working implementation found (VERIFIED,
   `LANDSCAPE.md` §4).

**DEFAULT-PROPOSED:** `questions.native_tool: disallow-headless`. Protects against the verified
silent-corruption case where a headless session is *told* it was answered when it was not — which is
strictly worse than not answering.

**DEFAULT-PROPOSED:** `questions.authority: refuse-and-escalate` for any question whose options
include an irreversible external effect (push to a protected branch, delete, spend, message a third
party), regardless of run mode. The owner said *"повністю і повністю окей"* with no condition at [324];
the *"в межах налаштованих повноважень"* qualifier at [325] was **the interviewer's phrase, not his**
(VERIFIED, `extract/corrections.md`). So this default is this document's, it is marked as such, and
R1-14's own machinery already licenses it: *"Якщо агент вирішив, що це точно має бути хардстопом …
відбувається хардстоп … навіть якщо це автономний ран"* [082].

**Every answer is recorded** in `answers.jsonl`: platform, session id, the question and options
verbatim, the answer, **the authority basis it was given under**, and the timestamp. R1-14 makes the
*basis* configurable — user-written rules, a "tone of voice" of past decisions, previous answers to
similar questions, the agent's project knowledge — and none of that is learnable unless answers are
recorded. In a **controlled** run the same record is what the human reviews before the hard stop
releases.

### 9.5 Delivery — the orchestrator verifies its own actions, never the work

R1-13 is given: verification belongs to the configured process; the orchestrator imposes no checks of
its own. This section sits **next to** that decision, not over it. Every check here is about an action
**the orchestrator itself performed**, costs zero model tokens, and works identically whether or not
the project has tests (N2 [344]: there may be no tests, and that is okay).

The merge-landed assertion — the one that would have caught FIELD-NOTES §4.1:

```bash
BASE=$(gh pr view "$PR" --json baseRefName --jq .baseRefName)
HEAD=$(gh pr view "$PR" --json headRefOid  --jq .headRefOid)
git fetch origin "$BASE"
git merge-base --is-ancestor "$HEAD" "origin/$BASE" \
  || fail "PR $PR reports merged; $HEAD is NOT an ancestor of origin/$BASE"
[ "$(gh pr view "$PR" --json state --jq .state)" = MERGED ] || fail "PR $PR is not MERGED"
```

VERIFIED working against PR #26 (`C9` §5.3). Two independent oracles; the §4.1 failure mode (a branch
merged into itself) fails the second one instantly.

Same class: capture `EXPECTED_BASE=$(git rev-parse HEAD)` before dispatch and assert it inside the
worktree; prefer `gh pr merge --match-head-commit "$HEAD"`; assert the process stage actually ran
before accepting its verdict; and **never parse a test summary** — read the engine's declared verdict
or record `verification: engine-none` and carry that into the PR body and `status.json` so the owner
sees what was and was not checked.

**Respecting repo rules** — a three-source ladder, all cheap: forge rulesets/branch protection →
the engine's own protected-branch list → the project's prose (`CLAUDE.md`, `CONTRIBUTING.md`) at a
config-pinned path. **DEFAULT-PROPOSED:** `delivery.mode: pr-only` unless config says otherwise.
Protects against exactly the case measured on the owner's own flagship repo, where all three machine
sources say *"nothing is protected"* while `CLAUDE.md` says *"no direct pushes to `main`"*.

### 9.6 Worktrees — one owner, declared, asserted

Three legal values, matching the three parties that all want to create worktrees:

| `worktree.owner` | Who creates it | Engine setting required | Consequence |
|---|---|---|---|
| `orchestrator` *(DEFAULT-PROPOSED)* | `git worktree add -b <branch> <path> <base>` | GSD `workflow.use_worktrees: false` | Д4's *"кожна задача у своєму ворктрі від main"* [433]; costs GSD's intra-phase parallelism |
| `engine` | GSD via the host harness | leave `use_worktrees: true` | keeps GSD's parallelism; the orchestrator does not create a worktree and does not assume the base |
| `host` | `claude --worktree` | `use_worktrees: false` | cheapest; least control over the base |

PREFLIGHT **refuses to start on a mismatch** and says so in those words. There is no configuration
that gives both his uniform default and GSD's parallelism today, and the choice is his.

Per-lane health each tick, four `git` calls, no model: `git worktree list --porcelain`;
`git rev-parse HEAD` vs the recorded `EXPECTED_BASE`; `git status --porcelain=v2 --branch`; the
declared env/service probe list. That is Д4's *"постійно переконуватись"* at four invocations per lane
per tick.

---

## 10. The three governors: capacity, context, liveness

Each is a pure function from events plus readings to a proposed action. Each carries an idempotency
watermark. Each has a bounded escalation that ends at a human. None of them acts on a single signal.

### 10.1 Capacity governor (R1-06)

Reads `capacity/<account-id>.json`, refreshed by `readCapacity` with a **single-flight cache per
account**. **DEFAULT-PROPOSED:** `capacity.poll_min_seconds: 3600`, burst 2. Never poll per session —
it earns a 429 exactly when quota matters (VERIFIED, `ADAPTER-CONTRACT.md` §2.3).

Three rules that make readings comparable across a fifteen-platform fleet:

1. **Enumerate buckets, never name them.** Take every bucket carrying a utilization or a balance; stop
   on **the worst**. Survives Anthropic adding a bucket and Z.ai renaming one.
2. **`window_seconds` is derived, never assumed**; a window that cannot be decoded is reported
   `null` and **still counted** — an unknown window is not a missing one.
3. **Every reading carries `account_id`, and readings are never compared across accounts.** VERIFIED
   from the owner's own run: *"a weekly-usage figure can move without any usage changing — when the
   supervisor was repointed from one account to another mid-run, the weekly reading fell from 26% to
   6% from the account switch alone."* A threshold crossing computed across an account switch is
   meaningless.

Actions: `soft` → close dispatch, let current work finish. `hard` → suspend lanes now, checkpoint,
release sessions. `intermediate` → **save state, close the session, resume it later by id** — and the
research's most useful finding for the item the owner left open [171] is that *what gates the
intermediate mode is not quota at all*, it is whether the platform can close a session and reopen
**that** session later. VERIFIED available on Claude Code, Codex, opencode and Cursor; UNKNOWN on
Copilot, Amp, Droid, `agy`. **DEFAULT-PROPOSED:** `capacity.mode: soft`. Soft is the near-universal
mode; hard is the scarce one.

Where the platform enforces the cap itself — Claude Code's `--max-budget-usd` in print mode (VERIFIED)
— use that instead of watching. Fewer moving parts is what [171] asked for.

### 10.2 Context governor (R1-08) — the mechanism that must be guaranteed

The owner's words are the strongest in the interview: *"повинен бути механізм, який гарантовано робить
цю дію"* [204]. One state machine per supervised session, owned by `orchd`, persisted on disk so a
restart resumes it rather than re-trips it.

```
OK ──pct ≥ threshold on TWO consecutive fresh readings──► ARMED
ARMED ──soft: wait for step boundary | hard: interrupt now──► PREPARING
PREPARING ──refresh handoff; REQUIRE PROOF the file moved──► TRIGGERING
TRIGGERING ──run the ladder rung for this platform; stamp watermark──► VERIFYING
VERIFYING ──rank-1/2 proof within verify_timeout──► RECOVERING ──► OK
          ──timeout, or a terminal compaction state──► ESCALATING
ESCALATING ──next rung; after the last──► FRESH SESSION ──still failing──► NOTIFY + HOLD
```

Trigger ladder, cheapest rung first, per platform:
`rung 0` pre-set threshold so the platform compacts at *our* number ·
`rung 1` native RPC · `rung 2` peer message · `rung 3` tty keystroke (preconditions checked, never
assumed) · `rung 4` **close-and-reseed**.

**Rung 4 is built once, centrally, and it is the platform-independent guarantee.** On Amp, Gemini CLI,
Cursor and `dsh` there is **no external compaction trigger at all** (VERIFIED), so hard mode is not
implementable there by compaction — but it is implementable by closing the session and opening a new
one seeded with the handoff. The cost, stated: **ticket→session becomes one-to-many**, so the ledger
must hold a lineage, not a field.

Verification is by a signal the compaction itself produced, ranked: PostCompact hook /
`thread/compacted` / `session.compaction.*` (rank 1) → a `compact_boundary` record on disk (rank 2) →
`current_usage == null` in the next status payload (rank 3) → a percentage that merely dropped
(rank 4, *"this is the one that lies"*). **Failure is a timer, not a guess**: no rank-1/2 signal within
`verify_timeout` means the trigger did not execute. **DEFAULT-PROPOSED:** `context.verify_timeout: 10m`
(measured: 67% → 0% in about seven).

Three states abort the ladder and go straight to a fresh session, all VERIFIED as real Claude Code
conditions: `autocompact: fixed prefix … — compaction cannot help`; `Autocompact is thrashing … 3
times in a row`; `failure_breaker_open`. Detect them from the session's own log stream, never the
screen.

Non-negotiables, each earned from a recorded failure:

1. **Two consecutive fresh readings before arming**, hysteresis on the way down.
2. **Idempotency by watermark** `(session_id, threshold, armed_at)`, written before acting.
   FIELD-NOTES §11.6: an 85-minute loop in which the watch matched a rate-limit banner inside the
   orchestrator's **own wrapped prose**, pressed Escape and sent `continue` every ~60 s for ever; line
   5620 of that log reads `NO ONE IS BEING TOLD`. **Any detector that re-reads its own effect must be
   idempotent per trip.**
3. **Bounded escalation with a human at the end.** The failure mode is not acting wrongly; it is
   acting the same way for ever.
4. **Never log the trigger phrases.** A governor that prints `/compact` or `rate-limit` on its own
   screen gets matched by its own detector. Write `context action` and `none|present`.
5. **A probe that can return empty on error must distinguish empty from failed.** FIELD-NOTES §11.3:
   BSD `find -newermt "-10 minutes"` errors out, and with stderr to `/dev/null` returns empty every
   time — which would have declared every healthy session idle for ever.
6. **Refill rate is a signal, not just level.** `Δpct/hour` above a bound is a defect, not a threshold.
   The 445k-token `echo idle` lane would have been papered over by compaction; it stopped within one
   minute of being told to end its turn.
7. **Watch the watcher's own window.** *"You watch the orchestrator's context. Nothing watches yours."*
   Because `orchd` is tokenless, this design has no watcher window to watch — which is the single
   largest structural gain from making the conductor deterministic.

**Post-compaction re-injection of the red lines.** After every proved compaction, re-read
`control/redlines.md`, extract the configured H2/H3 sections, and prepend them to the next turn with
*"Session was just compacted. The conversation summary above is a hint, NOT a substitute for your
startup sequence."* Heading extraction is fenced-code-block aware, `YYYY-MM-DD` is substituted with
the real date, bounded at 1800 chars with UTF-16-safe truncation, and **every failure path returns
null** — a missing or oversized file degrades to no injection, never to an error. VERIFIED design,
OpenClaw `post-compaction-context.ts` via `ADOPTION-VERDICT.md` §4.3. This answers a failure R1-15 does
not anticipate: **compaction deletes the red lines mid-run**, repeatedly, in a run long enough.

**DEFAULT-PROPOSED thresholds** (raw percent, defined once as `100 − remaining_percentage`, matching
`/context`): executor 75 · context roles 85 · orchestrator 66. These are the previous generation's
numbers restated on the raw scale; note that a threshold migrated from the old screen-scraped numbers
must be **lowered by ~13 points**, and the owner should be asked which "66" he means.

### 10.3 Liveness governor (R1-09, R1-10)

R1-09 [231] delegates the judgement to the agent. This design keeps that and makes the judgement
cheap: **`orchd` assembles the evidence; `mind` renders the verdict; `orchd` executes.**

`orchd` never acts on one signal, because every cheap signal's false-positive mode is documented from
this system's own logs:

| Signal | Proves | Documented false positive |
|---|---|---|
| `flock` refused | an orchestrator process exists | none |
| pid + `proc_start` + `boot_id` | **that exact process** | none known |
| `kill -0 pid` alone | *a* process with that number | PID reuse |
| platform `status` field | the platform's own idle/busy/waiting | **invisible under the wrong `CLAUDE_CONFIG_DIR`** |
| heartbeat file age | the last **turn boundary** | *"nudged six times in this run … every one of those sessions was healthy"* |
| transcript mtime | a message was appended | **0 bytes of growth over 3 s while a subagent did heavy work** |
| tool-call cadence | tools are being called | 3,466 of 3,626 Bash calls were `echo idle` |
| child-process count | a command is running | *"a shell that cannot exit reads as work"* |
| git activity | real output landed | silent for planning, research, review, docs — and there may be no repo at all |
| screen scrape | **nothing reliably** | the 85-minute loop |
| board transition | a status was written | the underlying action may have done nothing |

**DEFAULT-PROPOSED:** `liveness.ask_mind_when: signals_conflict OR action_is_destructive`. Protects
`mind`'s context window (the previous generation's largest cost) while leaving R1-09's decision with
the agent. Everything unambiguous — a process that is provably gone, a lane that has emitted
`turn.completed` and nothing since — `orchd` handles alone and journals.

**Distinguish a quota pause from a crash before acting.** Gas Town's eleven-line idea, adopted
verbatim in spirit: a session at a usage-limit prompt has a stale heartbeat, which from outside is
*indistinguishable* from a crash — but killing and respawning does not help and the repeated kills
burn the crash-loop budget. Capture the evidence to disambiguate; record the event as a **pause**
(which does not spend the restart budget); escalate on a crash loop instead of restarting forever.

**The sentinel (R1-10).** A one-shot agent on a **different account and a different provider**, fired
by `launchd`, not resident. It reads `lease.json` and `journal.jsonl` (both cheap), and has exactly
three powers: restart `orchd` if the lock is free and the lease is stale; notify; and refuse. It never
dispatches work. **DEFAULT-PROPOSED:** `sentinel.interval_minutes: 30`, `sentinel.required: true` when
any lane's `capacity_model` is `Window` (because a window exhaustion is exactly when the primary
provider cannot run its own health check). Nobody in the field runs a watchdog on a different
subscription (VERIFIED, `LANDSCAPE.md` §5 "R7") — this is unowned work, and it is the owner's explicit
requirement [246], [255], [266].

---

## 11. Boundaries: stopping only what it started

The owner ruled out heavy isolation: *"я не хочу якихось детерміністського варіанту … дуже складний
оверінжиринг, але дуже якісь простий та надійний варіант … має бути прописаний в плагіні"* [370].

The design takes the two layers that cost him nothing and contradict nothing he said.

**Layer 1 — the ownership ledger.** `ledger.jsonl`, append-only. *The orchestrator may stop only a
thing whose identifier it wrote into the ledger at the moment it created it.* No pattern matching,
ever. At spawn: `set -m` and record the PGID; record the tmux pane / session id; record the compose
project name plus a `label=orchestrator.run=<id>`; record the worktree path and branch. Teardown
iterates the ledger **and nothing else**.

> **Invariant BD-1.** `pkill`, `killall`, and an unscoped `docker compose down` do not appear anywhere
> in plugin source. **A lint rule in the test harness fails the build if they do.**

This is exactly the fix for the two recorded incidents where the owner's own parallel work was hit,
including FIELD-NOTES §5.1 — his own container killed for memory *by* the run. Cost: zero settings,
identical on every engine.

**Layer 2 — worktree anchoring.** Д4's default promoted to the boundary mechanism: every task in its
own worktree, cwd set at spawn, his parallel work left in the main checkout. The orchestrator writes
only inside worktrees it created plus the run's own state directory. Worktree identity is **verified
at spawn, not assumed** — a branch name computed one word off, or a lane slug reused from an earlier
wave, spawned into a stale worktree last run (VERIFIED, FIELD-NOTES §11.8). Owner-facing files live
**outside** the worktree or are explicitly synced, because `QUESTIONS.md` and `JOURNAL.md` forked into
a worktree's own copy last run.

**Where `sandbox: false`, the lane is confined and its ticket eligibility narrows.** On Kimi and pi
there is no sandbox at all and Kimi's hooks **fail open** — a crashed guard permits. There, R1-15's
text file is the **only** barrier, and this design does not pretend otherwise: it adds a mandatory
worktree plus a static deny list for destructive commands and **raises it as a question** rather than
assuming the text file suffices.

**`redlines.md` stays exactly as he specified**: one file, user-maintained, appendable, mandatory
reading, no separate procedure. It is injected at session start and re-injected after every proved
compaction (§10.2). Making it *enforceable* — a `PreToolUse` hook that hard-denies its `never-touch`
paths — is **offered as a setting, defaulted off**, because it is precisely the *"окрема обов'язкова
процедура"* he said was unnecessary [357]. **DEFAULT-PROPOSED:** `redlines.enforce: false`.

---

## 12. Configuration: the owner's three scopes, and a run scope that is not a seventh file

### 12.1 The six slots, unchanged

The plugin is `orchestrator`, so the six files are, lowest to highest (OWNER-DECISIONS 3.3, 4.15):

```
1  ./.claude/shared/identity.json                       project, general, committed
2  ./.claude/shared/plugins/orchestrator.json           project, this plugin, committed
3  <config-root>/shared/identity.json                   user, general
4  <config-root>/shared/plugins/orchestrator.json       user, this plugin
5  ./.claude/shared/identity.local.json                 project, general, personal
6  ./.claude/shared/plugins/orchestrator.local.json     project, this plugin, personal
```

A person's own files beat the project's committed files; among a person's own, this project beats the
home folder; inside either, the plugin's own file beats the general one. A person's `never` entries
accumulate and hold against everything, that person's own pick included.

**What goes where.** Reusability is the test (OWNER-DECISIONS 3.4). Connectors — the board, the
notification channel, the task manager — are reusable by other plugins and belong in `identity.json`.
Lanes, roles, engine choice, thresholds and worktree ownership are usable by nothing else and belong
in `plugins/orchestrator.json`.

**`recommended.json` is advice, never a value.** `plugins/orchestrator/config/recommended.json` carries
`strength: weak | strong` per recommendation and is read by the configurator and the builder, **never
by the resolver**. GitHub Issues as the board is a `weak` recommendation (R1-04 named it first, and a
project can have anything). Claude Code as the first platform is `strong` — it is the only lane that
can run tonight (VERIFIED). The *text* never says "because that is how it is here"; the strength field
says it.

**A run without config still works** (OWNER-DECISIONS 6.1): `/orchestrator:run` asks what is missing,
and writes the answer to the person's own file after asking where (3.9). `/orchestrator:config`
re-asks whether what is already set is still current (6.2).

### 12.2 Why there is no seventh slot

LANDSCAPE §5 notes that nobody in the field has a run scope, and the owner's own marketplace fixes the
level count at three (OWNER-DECISIONS 3.6: *"remove the fourth level entirely"*). So the run scope is
**not a config file**:

```
resolved config (slots 1–6)
    → frozen into plan.json at PREFLIGHT                     ← the run's identity
    → live-overlaid by control/control.yaml `overrides:`     ← the run scope, ephemeral
```

`control.yaml` is not a config slot: it does not persist across runs (only the *stop verbs* and
account map do, and those are operational, not configuration), it is not merged by the resolver, and
it cannot defeat a `never`. It is the run's control surface. That keeps three levels exactly three.

### 12.3 How a mid-run change is picked up

1. `orchd` hashes `control/control.yaml` every `control.poll_seconds` (**DEFAULT-PROPOSED 10**).
2. Hash changed → acquire the reader's view of the writer lock → parse.
   - Parse fails → keep last good, journal `control.invalid`, notify once. **Never take the run down.**
3. Leaf-diff against the applied document. Each changed leaf gets its apply class (§3.4).
4. `hard` leaves: applied this tick, with a `control.applied` journal line naming each leaf.
   `soft` leaves: queued and applied at each lane's next step boundary.
   `next-run` / `frozen` leaves: journalled as `control.refused` and shown in `status.json` with the
   words *"takes effect on the next run"*.
5. A `never` in the person's own config vetoes the override; the veto is journalled with the file that
   holds it.

This is Д7 [455], [458] implemented literally: the owner may change behaviour **during** the run, and
it overrides both the run's initial choice and the default.

### 12.4 The two other watched surfaces

**`control/inbox/` (Д6).** One file per answer, any format the channel adapter declares. Watched on
the same tick. The owner's insight that this may be *a different place from the task board* — a local
file, a GitHub issue with a tag, a task in the tracker — is honoured by making it a **channel
adapter**, discovered on the same path as platform adapters, with three ops: `watch`, `post`,
`verify`. A local directory is the zero-config implementation and is the **DEFAULT-PROPOSED** value.

**`control/redlines.md` (R1-15).** Watched; a change is apply-class `hard` (it is re-injected into
every live session at its next turn boundary).

---

## 13. Stop: hard, soft, custom

Д12 is UNRATIFIED in the analysis — the session ended on it — so this section is designed to his
stated shape and flagged.

**No stop command signals anything.** All three write into `control/control.yaml` under the writer
lock and exit. The mechanism is his own: *"the command writes into the file the orchestrator reads
every tick, and the change is applied on the next tick"* [520], [524]. The command prints the tick at
which it will be seen, so the owner is never left wondering.

| Verb | Written | `orchd` does | Exit |
|---|---|---|---|
| `stop-hard` | `stop: hard` | write the `ESTOP` sentinel; `adapter.stop(h,"hard")` on every ledger entry; **assert each process gone by pid+proc_start**; then TEARDOWN | `0` clean · `75` orphans (named) · `70` unassertable |
| `stop-soft` | `stop: soft` | `intake: frozen`, dispatch closed; each lane finishes its current **step** (the engine's definition, R1-08/Д12); then DRAINING | as above |
| `stop-custom <n>` | `stop: custom:<n>` | run the `verbs:` block of `control/stops/<n>.md` deterministically, then hand the prose to `mind` with authority basis | as above |

**The ESTOP carve-out, copied verbatim from Gas Town** (VERIFIED): the sentinel file freezes every
agent session, and **the coordinator is exempt, so it survives to coordinate recovery.** Without the
carve-out, `stop-hard` kills the only thing that can clean up after it.

**`stop-custom` degrades honestly.** It needs a model, and the model may be the thing that is broken.
If `mind` is absent or does not respond within `custom_stop_timeout`, `orchd` falls back to
`stop-soft` and journals `stop.custom.degraded`. **DEFAULT-PROPOSED:** `custom_stop_timeout: 120s`.
Protects against a custom stop that silently does nothing — the exact FIELD-NOTES "reported success
and did nothing" class, in the one place where it would be worst.

**Where `stop-hard` cannot be honoured.** On Gemini CLI headless a mid-run message cannot be delivered
at all and in ACP it **aborts the turn** rather than adding to it; on `dsh` ACP an instruction is
impossible mid-prompt. There `stop-hard` degrades to *kill the process* and `stop-soft` degrades to
*apply at the next task boundary*. This is recorded in `plan.json.weakened[]` at negotiation time, so
the owner knows before the night starts, not after.

---

## 14. Crash and recovery

### 14.1 What survives

| Survives | Does not |
|---|---|
| `journal.jsonl`, `ledger.jsonl`, `events.jsonl`, `answers.jsonl`, `teardown.jsonl` | `status.json` (derived, rebuilt) |
| `plan.json`, `lease.json`, `tickets/*.json`, `claims/` | in-memory cursors (rebuilt from `cursor.json` + the events tail) |
| the board's own state and claim refs | any adapter handle (re-acquired by `resume`) |
| the engine's own record via `state_ref` | the pipe-only transcript of a platform that did not tee |

### 14.2 The recovery decision, in order

`orchd start` with `current` present:

1. **Acquire `run.lock`.** Refused → an orchestrator is alive → **exit 3, which is not an error.**
2. **Mint the epoch** and append `orchestrator.claim` with `prev.verdict` and the evidence for it.
3. **Crash-loop check:** N `orchestrator.claim` lines in T minutes with no `step.result` between →
   refuse to start, notify, hold. **DEFAULT-PROPOSED:** N=3, T=15m. Protects against the owner's own
   named fear at [300] and against the FIELD-NOTES record of a dead run flagging itself **1,085 times
   over five days**.
4. **Probe every ledger entry** with its recorded `probe` data. Alive → per Д10 [497], `mind` decides
   *stop or wait* within its permissions, and `orchd` executes; Dead → mark and proceed.
5. **Find orphans:** every `step.intent` with no `step.result`. Before redoing anything, search its
   `action_id` **in the side effect itself** — the ticket comment trailer, the branch name, the commit
   trailer. A found `action_id` means the side effect landed and the crash was after it.
6. **Recover each affected lane by the configured ladder**, R1-10 [293], [307], [310]:

   ```
   rung 1  state files            (default; the orchestrator's own journal + the ticket)
   rung 2  engine state_ref       (GSD's STATE.md + state_head)
   rung 3  resume by session id   (adapter.resume — must resume exactly or declare itself lossy)
   rung 4  transcript replay      (where the adapter has a durable transcript)
   rung 5  re-dispatch            (always available; loses the session's working memory)
   ```

   A rung the config does not allow is **skipped, not degraded past silently**. Each rung declares
   what it costs and what it may lose. On Aider, "resume" means "re-run with a handoff file" — its
   resume is lossy by construction (5 turns kept, 48 tool lines dropped), and the adapter says so in
   `capabilities()` rather than pretending.
7. **Where the platform mints the id server-side** (Codex, Kimi, Amp, MiMoCode) there is a crash window
   between launch and first record. Treat the first N seconds of a task as **unrecoverable by id** and
   recover by **re-dispatch**. On Gemini CLI a session with no completed model turn is **deleted and
   unresumable** — there is no recovery point at all, and the adapter declares `B_identity: emulated`.
   **DEFAULT-PROPOSED:** `recovery.id_grace_seconds: 20`.

**"Start over" means restart the orchestrator, not redo the work** [300]. Nothing in the recovery path
re-dispatches a ticket whose `step.result` is present.

---

## 15. The end of the run, and what it cleans up

**The terminal condition** — the thing LANDSCAPE §5 confirms nobody in the field ships:

```
DRAINING  when  intake closed OR (board.ready_count == 0 AND every lane IDLE)
ENDED     when  every lane RETIRED
            AND every ledger.jsonl entry has a teardown.jsonl verdict
            AND status.json written with final:true
```

**Teardown iterates `ledger.jsonl` and nothing else** (§11). For each entry, one of three verdicts is
written to `teardown.jsonl`: `gone` (asserted by identity — pid+proc_start absent, container id
absent, pane absent), `orphan` (still present after `stop` reported success — the `cursor-agent worker
kill` class, VERIFIED to report success and leave the process at 100% CPU), or `refused` (a guard
declined, e.g. a worktree with uncommitted work).

Д3's *"щоби не залишати хвостів"*, without touching anything else:

| Created | Stopped | Not touched |
|---|---|---|
| sessions this run spawned | yes, by handle and asserted by pid | any session not in the ledger |
| containers with `label=orchestrator.run=<id>` | yes, by that label | every other container |
| tmux panes / windows this run opened | yes, by pane id | the owner's panes |
| worktrees this run created | **only if clean and merged-or-pushed**; else left and reported | the main checkout, always |
| launchd sentinel job | unregistered | every other job |
| the `current` symlink | repointed to nothing | prior run directories, kept |

**Run exit codes:** `0` drained clean · `75` orphans remain (each named on stdout and in
`teardown.jsonl`) · `70` could not assert a teardown · `78` refused to start (PREFLIGHT) ·
`3` another orchestrator holds the lock.

**Run directories are kept, not deleted.** **DEFAULT-PROPOSED:** `runs.retain: 20`, pruned oldest-first
at the *start* of a run, never at the end — so a post-mortem of the night that just failed is never
the thing that gets cleaned up.

---

## 16. What the owner sees, when, and only when he asks

Д11 [508] is unambiguous: *"оркестратор не повинен нічого виводити для мене … якщо я хочу отримати
статус виконання, то я можу запустити окремий термінал, прописати orchestrator двокрапка статус."*

**`orchestrator:status` is a shell script, not a skill.** Zero model tokens. It reads `status.json` and
the tail of `journal.jsonl` and prints. Human text by default; `--json` for machines; `--why <ticket>`
prints that ticket's slice of `events.jsonl`. Exit `0` healthy · `1` needs-a-human · `2` stale reading.

The regression to avoid is named: the previous generation already wrote this exact contract in
bash+jq, and *the regression was routing the command through a skill.*

`status.json` carries `written_at`, and the script **prints the staleness prominently** — because a
JSON file goes stale the moment its writer dies and shows the last good state as though it were
current. Staleness is a fact to display, never a verdict to act on.

**Notifications (R1-17)** are the only unsolicited output, and only the types the owner configured.
Two-tier verification at PREFLIGHT: a credential check per channel (Telegram `getMe`, Slack
`auth.test`, SMTP `EHLO`+auth, or a declared `test_command` — the phone call at [395] is a
`test_command`), then **one real message with the service's receipt recorded**. Labelled *delivered*,
never *seen* — that is the ceiling of what is provable. If a channel marked `required` fails, the run
**refuses to start**: a run that cannot reach him is a run he will not know has stopped.

**DEFAULT-PROPOSED notify set:** `run.ended`, `run.holding`, `quarantine` (Д5), `capacity.exhausted`
when the model is `Credit`, `control.invalid`, `teardown.orphan`. Everything else silent. Protects
against the two opposite failures: a night of noise, and FIELD-NOTES §11.6's `NO ONE IS BEING TOLD`.

---

## 17. Every configurable thing, and its default

The owner made almost everything configurable and stated almost no defaults. This table is the
contract; **nothing outside it may invent a default at runtime.** Every row is DEFAULT-PROPOSED unless
it cites an owner row. Scope column: `U` user, `P` project, `R` run (`control.yaml overrides`).

| Key | Default | Scope | Apply | Protects against |
|---|---|---|---|---|
| `run.mode` | `ask` (R1-14 [075] gives three values) | U P R | frozen | a controlled run silently going autonomous |
| `engine.id` | *(required, no default)* | P | frozen | R1-03's no-mixing rule |
| `engine.mode` | `autonomous` when `run.mode: autonomous`, else `interactive` | P R | soft | an engine prompting a human nobody is watching |
| `concurrency.max` | `2` | U P R | soft | FIELD-NOTES §5.2's load under two lanes; GLM's contractual ceiling |
| `intake` | `capped` at 10 started per run | P R | soft | the queue that grew 236 → 327 in a day |
| `on_only_blocked` | `wait` (Д7's stated recommendation) | U P R | soft | an unattended run ending on a question |
| `board.backend` | *(required)*; `github-issues` recommended `weak` | P | next-run | — |
| `board.write_back` | `true` (R1-04: the board is a working surface) | P R | soft | a night whose record exists only locally |
| `worktree.owner` | `orchestrator` (Д4) | P | frozen | the three-way worktree collision |
| `delivery.mode` | `pr-only` | P R | soft | the owner's own repo: machine sources say unprotected, prose says no direct pushes |
| `delivery.evidence` | `observed` | P R | soft | advancing an empty issue into a human's queue |
| `capacity.mode` | `soft` | U P R | soft | hard mode is unavailable on most of the field |
| `capacity.soft_pct` / `hard_pct` | `85` / `95` (Window only) | U P R | soft | a wall in the middle of a step |
| `capacity.spend_ceiling_usd` | `null`, **and a start-time refusal if any lane is `Credit`** | U P R | soft | `Credit` lanes have no natural stopping point |
| `capacity.on_unreadable.hard` | `hold-and-escalate` | U P R | soft | the previous generation's `proceed`, which ran for days uncapped |
| `capacity.on_unreadable.soft` | `proceed` | U P R | soft | a throttled read stopping a healthy run |
| `capacity.poll_min_seconds` | `3600`, burst 2 | U P | soft | a 429 exactly when quota matters |
| `capacity.resume_margin_seconds` | `120` | U P R | soft | resuming one second before the window actually rolls |
| `context.mode` | `soft` | U P R | soft | hard mode is impossible on four platforms |
| `context.step` | the engine's `step` point; else `turn.completed` | P R | soft | "soft" meaning nothing on an engine with no steps |
| `context.percent` (executor / watcher / orchestrator) | `75` / `85` / `66` raw | U P R | soft | an auto-compact choosing the moment mid-mutation |
| `context.verify_timeout` | `10m` | U P | soft | a compaction believed rather than proved |
| `context.on_terminal_state` | `fresh-session` | U P | soft | three verified dead-ends where `/compact` can never work again |
| `context.refill_rate_alarm` | `15 pct/hour` | U P | soft | the 445k-token `echo idle` lane |
| `liveness.ask_mind_when` | `signals_conflict OR action_is_destructive` | U P | soft | `mind` burning its window on routine checks |
| `liveness.tick_seconds` | `30` | U P | soft | 33 nudges to healthy sessions |
| `control.poll_seconds` | `10` | U P | soft | a stop verb sitting unseen |
| `custom_stop_timeout` | `120s` → falls back to `stop-soft` | U P R | soft | a custom stop that silently does nothing |
| `questions.native_tool` | `disallow-headless`, inject `ask_supervisor` | U P | soft | a headless session told it was answered when it was not |
| `questions.authority` | `refuse-and-escalate` on irreversible external effects | U P R | hard | an autonomous run pushing, deleting or spending on a guess |
| `questions.channel` | `control/inbox` (local directory) | U P R | soft | a channel that needs a service to be up |
| `runtime.drive` / `runtime.visibility` | `protocol` / `hidden` per platform, `pty`/`visible` for `run.mode: controlled` | U P R | frozen per lane | the four-mode boolean that cannot express `--bg` |
| `pty.backend` / `pty.host` | `tmux` / `iterm2-if-present` | U P | frozen | every recorded AppleScript delivery failure |
| `adapter.verify_max_age_hours` | `24` | U P | soft | Amp's five releases in fifteen hours |
| `negotiate.on_unknown` | `impossible` | U P | frozen | an adapter that claims `native` and degrades at 03:00 |
| `negotiate.interactive` | `ask` with a TTY, `refuse-run` without | U P | frozen | an unattended start taking the weak half of a trade |
| `sentinel.interval_minutes` | `30`; `required: true` when any lane is `Window` | U P | soft | the provider that cannot run its own health check once exhausted |
| `recovery.sources` | `[state-files, engine-state-ref, resume-by-id, transcript, re-dispatch]` | U P | soft | a rung silently skipped |
| `recovery.id_grace_seconds` | `20` | U P | soft | the server-mints-id crash window |
| `failure.identical_limit` | `3` (Д5), durable across restarts, then tombstone | U P R | soft | a retry budget that resets on every crash |
| `crashloop.n` / `.window` | `3` / `15m` | U P | soft | 1,085 self-flags over five days |
| `claim.stale_seconds` | `1800` | U P R | soft | a crashed lane holding a ticket all night |
| `redlines.path` / `.enforce` | `control/redlines.md` / `false` | U P | hard / next-run | R1-15 as stated, with the teeth optional |
| `notifications.types` | `[run.ended, run.holding, quarantine, capacity.exhausted, control.invalid, teardown.orphan]` | U P R | soft | a night of noise, and `NO ONE IS BEING TOLD` |
| `status.output` | `minimal` | U P R | soft | Д11's token budget |
| `runs.retain` | `20`, pruned at run **start** | U P | soft | cleaning up the post-mortem of the night that failed |

---

## 18. What is impossible as stated, and what keeping it costs

Per the brief: the exact part, and the price.

| Owner item | The part that is impossible | What it would cost to keep |
|---|---|---|
| **R1-07** — *hard* account change ("applies now, stops current work") | Changing a **running** session's account is impossible on **all fifteen** platforms (VERIFIED) | Stop the session, relaunch on the other account, **re-seed the context**. You pay for the context a second time, and the lineage becomes one-to-many. The alternative is to redefine *hard* as "at the next step boundary", which is what *soft* already means |
| **R1-08** — *"механізм, який гарантовано робить цю дію"* in hard mode | On Amp, Gemini CLI, Cursor and `dsh` there is **no external compaction trigger at all** | Keep the *outcome* guarantee by close-and-reseed (built once, centrally). Cost: ticket→session becomes one-to-many, a re-seed costs the session's working memory, and the ledger must hold a lineage rather than a field. The *action* guarantee cannot be kept on those four |
| **R1-06.1** — "wait for the reset and continue" | Seven of fifteen platforms report no capacity at all, and `Credit` platforms have **no reset to wait for** | Either exclude those lanes from roles that need predictable capacity (this design's default), or accept a money ceiling in place of a percentage threshold. There is no third option: the model is money, not time |
| **R1-11** — hybrid (interactive *and* supervised) | On Gemini CLI, ACP **replaces** the TUI: supervision and human takeover are mutually exclusive *per process*. On Amp and `dsh` there is no attachable local pane at all | Takeover becomes a **handoff**: stop → relaunch attached → resume. One restart, visible in the run log, never silent |
| **Д12** — `stop-hard` as an instruction into a live session | On Gemini headless a mid-run message cannot be delivered; in ACP it **aborts the turn** | `stop-hard` degrades to killing the process. `stop-soft` degrades to the next task boundary. Recorded in `plan.json.weakened[]` before the run starts |
| **R1-15** — one text file, no enforcement machinery | On Kimi and pi there is **no sandbox at all** and Kimi's hooks fail open. The file is then the only barrier, and a model that ignores it has nothing beneath it | Either narrow what those lanes may be given, or turn on `redlines.enforce` — which is the separate mandatory procedure he said was unnecessary. The design defaults to the first and offers the second |
| **R1-09 / R1-10** — the orchestrator judges, and an external watchdog exists | Not impossible, but **unowned**: nobody in the field runs a watchdog on a different account or provider (VERIFIED) | Real build time. The sentinel in §10.3 is new work, not adoption |
| **R1-16, case 2** — the owner's parallel work in the same folder | **Nobody solves it**, unanimously (VERIFIED, `LANDSCAPE.md` §5). A sandbox is the wrong shape: it confines the agent to the workspace root, which is exactly where his parallel work lives | Worktree anchoring plus the ownership ledger reduce it to "the agent is not in your folder" for processes and containers. **They do nothing about files.** A path-level, per-run ownership rule has to be invented, and this lens does not invent it |

---

## 19. Tensions with the owner's decisions, recorded rather than resolved

**19.1 One orchestrator, split into two processes.** He said the orchestrator is a thing that can die,
be health-checked and be restarted [246]–[302], and that *"два якісь оркестратори"* is not okay. This
design splits it into a tokenless conductor (`orchd`, which holds the lock and is the thing the
invariant protects) and a model mind (`mind`, restartable inside one epoch). That is a reading, not his
words. **It is the right call if Д11's token budget and FIELD-NOTES §3.1 are taken seriously; it is
wrong if he meant that the judging agent itself must be the singleton.** Ask him.

**19.2 `undocumented`, `unknown` and `ask` make the run refuse to start.** He wants unattended nights.
This design will sometimes refuse at PREFLIGHT for a reason he never asked about. The trade is
deliberate — an honest refusal at 22:00 beats a silent degradation at 03:00 — but it is friction he did
not sign up for, and `negotiate.interactive` is the knob that lets him turn it into a question instead.

**19.3 The questions authority default is stricter than his words.** [324] is unconditional; [325]'s
qualifier was the interviewer's. This design defaults to refusing questions with irreversible external
effects. Flagged, defaulted, and easy to turn off.

**19.4 The control file is three files.** He said one text file for red lines [357] and "the file the
orchestrator reads every tick" for stops [520]. The analysis notes nothing says these are the same
file. This design makes them three files in one watched directory, with different writers. If he wants
literally one file, the design collapses cleanly — the cost is that a stop verb and a prohibition then
share a writer lock and a parse failure in one takes both down.

**19.5 `stop-custom` cannot be guaranteed.** It is the one verb that needs a model, and `mind` may be
the thing that is broken. The design degrades it to `stop-soft` and says so. Д12 is UNRATIFIED anyway.

**19.6 Machine-resource awareness is absent, by his retraction** [163]. FIELD-NOTES §5.1 records his
own container being killed for memory by the run. The ownership ledger prevents the orchestrator from
*killing* his work; nothing here prevents it from *starving* his machine. That is his call, recorded.

---

## 20. Honest assessment

### What this lens makes worse

1. **It delays the first working night.** Nothing runs until at least one adapter passes conformance
   and one engine descriptor is written. The previous generation could be started by hand on day one;
   this one has a negotiation phase first, and PREFLIGHT can refuse. An owner who wants a run *tonight*
   will experience adapter-first as an obstacle, and he would be right.
2. **It multiplies surfaces to keep in sync.** Seventeen operations, ten capability axes, eight engine
   points, twenty-four event kinds, five adapter classes — against a field where Amp ships five
   releases in fifteen hours and Copilot 835 versions in twelve months. Every abstraction is a thing
   that drifts. A monolith that knew about `claude` and nothing else would be smaller, and for a
   one-platform night it would be better.
3. **It pushes the hard problems into config.** `plan.json.weakened[]` is an honest mechanism and it is
   also a way of handing the owner a list of trades at 22:00 that he did not ask to make. Verbose
   configuration is the price of not lying, and it is a real price.
4. **The tokenless-core decision sits against R1-09's plain reading.** He said the agent decides.
   `orchd` decides most things and asks `mind` only when signals conflict. That is cheaper and it is
   less than what he described.
5. **Two-axis provenance on every number is annoying to implement** and will be the first thing an
   adapter author skips. The schema forbids the shortcut, which means adapter authors will feel the
   friction on every field.

### What it drops

- **Machine resources** (R1-05's retraction) — CPU, memory, disk, ports. Deliberate, and recorded as a
  tension.
- **Multi-machine and remote lanes.** Everything here is one host, one `flock`, one `boot_id`.
- **The learning half of R1-14's "tone of voice".** `answers.jsonl` records the basis; nothing in this
  design turns a corpus of past decisions into a policy. That is a whole subsystem and this lens does
  not design it.
- **R1-16 case 2** beyond process-and-container ownership. Files are untouched by this design.
- **Cost as a scheduling input.** §6.5 of the adapter contract shows a **150×** credit spread inside one
  platform's model list; this design pins model per role and stops there. Routing by price is left out.
- **Stacked PRs** beyond one branch per ticket with a recorded merge base. Without `--update-refs`
  (git 2.33 here), the rebase cost is manual, and the design recommends independent PRs.

### The single weakest point

**The capability manifest is a claim, and every safety property downstream of it is only as true as
that claim.**

`negotiate.on_unknown: impossible` protects against a manifest that *omits* something. Nothing in this
design protects against a manifest that is *wrong in the confident direction* — an adapter declaring
`D_context: native` whose `compact` works in testing and silently no-ops against a longer session, or
`E_quota: native` against a schema the provider renamed last week. The conformance suite is written
from the same reading of the platform that produced the manifest, by the same author, against fixtures
recorded on the same day. It cannot catch a shared misunderstanding, and the field has already shown
exactly this failure twice: Z.ai's `TOKENS_LIMIT`→`CREDIT_LIMIT` rename rendered **0% used** — read as
*plenty of room* — and `cursor-agent worker kill` **reports success and leaves the process at 100%
CPU**.

The mitigations are real but partial, and it is worth naming what each one actually buys. The `Proof`
requirement on `compact` makes a false `native` **loud after the fact** rather than silent — the run
learns it was lied to at the moment it needed the capability, not before. The two-axis provenance on
every number makes a *derived* figure impossible to pass off as a *measured* one. `adapter verify`
run within 24 hours catches a version drift but not a semantic one. The
`schema_unknown`-must-be-noisy rule catches a parse that silently yields zero.

What none of them buys is the thing that matters: **there is no independent oracle for a capability
claim.** Everywhere else in this design, a fact has two sources — the forge state *and* the git graph;
the lock *and* the epoch; the platform's report *and* the process table. The manifest has one. That is
the design's single point of trust, and it is trusted at exactly the hour when nobody is watching.
