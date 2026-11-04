# ARCH-operability — the orchestrator designed from the operator surface inwards

**Date:** 2026-09-19. **Lens:** operability and cost first.
**Status:** a design proposal against settled owner decisions. It is not a decision record.
**Inputs read in full:** `round-1/ANALYSIS-01.md`, `research/platforms/ADAPTER-CONTRACT.md`,
`research/adoption/ADOPTION-VERDICT.md`, `research/LANDSCAPE.md`,
`plugins/harness/docs/FIELD-NOTES.md`, the nine cluster files (targeted sections named inline),
`<baseline-marketplace>/requirements/OWNER-DECISIONS.md` + `docs/config-levels.md`,
`~/.claude/gsd-core/` (probed for its machine-readable surfaces).

**Evidence tags used throughout.** **VERIFIED** — read in a primary source on this machine, or
measured here. **CLAIMED** — a vendor, README or third party asserts it. **INFERRED** — my reasoning
from verified facts; the reasoning is stated so it can be rejected.

**Tag on every default I invented:** `DEFAULT-PROPOSED`. The owner made almost everything
configurable and stated almost no numbers. Every such default is listed once here, in context, and
again in §15 as one table, each with the failure it protects against.

---

## 0. The lens, stated as a rule, and what it is allowed to decide

The brief is: *optimise for what the owner actually experiences.* Concretely, six constraints that
I treat as binding and design backwards from.

| # | Constraint | Source |
|---|---|---|
| O1 | **No output unless asked.** The run writes nothing to a terminal he is looking at. | Д11 [508] |
| O2 | **Status comes from a separate command**, in a separate terminal, on demand. | Д11 [508] |
| O3 | **One questions channel** he answers in his own time; independent work keeps moving. | Д6 [449] |
| O4 | **Notifications only where he configured them**, and only the types he configured; possibly none at all. | R1-17 [395] |
| O5 | **Cheap models for watch duties.** | Д8 [466] |
| O6 | **Minimum tokens spent on supervision itself**, by default. | Д11 [512], R1-07 cost-awareness |

And one the brief adds: **a morning artifact that makes the next run better** (§14.3).

### 0.1 The single architectural consequence of this lens

Every failure in `FIELD-NOTES.md` that cost the owner a night has the same shape: **a model was in
the supervision loop, and the loop's inputs were things a model wrote.** The 85-minute loop matched
the orchestrator's own prose (§11.6). Six healthy sessions were nudged on a heartbeat signal the
session itself authored (§1.5). A detector re-read its own effect for ever. 445k tokens went into
`echo idle` (§3.1). The watch's own collector was OOM-killed 26 times (§12.3).

So the design's central inversion is:

> **The loop is deterministic and holds no model. The model is a callable the loop wakes when there
> is a decision to make, and the loop pays for every wake out of a declared budget.**

That inversion is what makes O6 achievable at all, and it is what makes O1 true by construction: a
bash loop under `nohup` has nothing to print to.

The cost of the inversion is stated honestly in §16: judgement arrives later than it would if a
model were always watching, and the owner explicitly delegated judgement to the orchestrator under
R1-09 («агент сам повинен це вирішувати»). §7.4 is where that tension is resolved and §17 is where
it is named as the weakest point.

### 0.2 What I am not allowed to change

The owner's decisions are given. Where I found one uncomfortable or impossible as stated I designed
for it and recorded the tension in §16 rather than substituting my preference. Four decisions in
particular pull against this lens and are kept: the orchestrator decides where he declined to
specify a rule (R1-09, Д9, Д10, Д3); verification belongs to the configured process, not to the
orchestrator (R1-13); the red line is one text file with no enforcement machinery (R1-15); and there
is no deterministic isolation for his parallel work in the same folder (R1-16).

---

## 1. The operator surface

This is the whole of what he touches. Everything after §1 exists to make this section true.

### 1.1 Commands

Seven, flag-routed to one backing skill, per the marketplace rule that a command is thin and the
behaviour lives in the skill (OWNER-DECISIONS 6.6). **Four of the seven spend zero model tokens** —
that is the point of the column.

| Command | Model tokens | What it does | Exit codes |
|---|---|---|---|
| `/orchestrator:config` | yes | The config verb (OWNER-DECISIONS 6.2, 6.5): re-asks every setting already present, writes to the person's own file (3.9). Also runs the **preflight proofs** of §1.4 on demand. | 0 ok · 64 usage · 78 a proof failed |
| `/orchestrator:run` | yes, once | Preflight, then detach. Prints one line and returns the shell. After that line it is silent for ever. | 0 detached · 69 preflight refused · 73 another run holds the lock |
| `/orchestrator:status` | **zero** | Plain shell + `jq`. Reads `status.json`, prints. `--json` for machines, `--lanes`, `--cost`, `--why <lane>`. | 0 healthy · 1 needs a human · 2 status is stale · 4 no run |
| `/orchestrator:stop` | **zero** | `--hard` · `--soft` · `--custom <name>`. Writes `control.yaml` under lock (§11). | 0 written · 1 no live run · 3 rejected (see `control.ack.json`) |
| `/orchestrator:ask` | **zero** | Prints the open questions from the Д6 channel and, with `--answer <id> <text>`, writes an answer into that channel in the channel's own idiom. A convenience; the channel remains answerable by hand (O3). | 0 · 1 nothing open |
| `/orchestrator:report` | zero to render, model only on `--explain` | Renders `RUN-REPORT.md` / `NEXT-RUN.md` for the named or last run. | 0 · 4 no run |
| `/orchestrator:resume` | yes, once | Re-enters the recovery tree of §12.4 against an existing run id. | 0 · 73 lock held · 75 refused, evidence in the journal |

**`/orchestrator:status` is a script, not a skill.** This is deliberate and it is a correction of a
verified regression: the previous generation already had `harness-run.sh do_status --json` in bash,
and then routed the *command* through a skill, so asking for status cost a model turn (C9 §4.8,
VERIFIED). Д11 is the owner saying the opposite. The status command must be executable by
`bash "$CLAUDE_PLUGIN_ROOT/bin/orc-status.sh"` with no model in the path, and a test must assert
that the command file contains no agent dispatch.

### 1.2 What he sees, and when

| Moment | What appears | Where |
|---|---|---|
| `run` | one line: run id, lanes planned, queue depth, capacity verdict, the path to the run dir | his terminal, once |
| during the run | **nothing** | — |
| he asks | the status render | the terminal he asked in |
| a configured notification type fires | one message | only the configured channel |
| the run ends | **nothing in any terminal.** A `run.finished` notification if he configured that type. | channel |
| next morning | `RUN-REPORT.md`, `NEXT-RUN.md`, `tuning.patch.yaml` | files in the run dir |

O1 is enforced structurally, not by discipline: after `run` detaches, no orchestrator process holds
a tty. `stdout` and `stderr` of every process go to files under the run directory. A component that
wants to say something has exactly three places to put it — the journal, an attention item in
`status.json`, or the notification spool — and a lint rule in the test harness fails the build on a
bare `echo` outside a `log_*` helper in plugin source.

### 1.3 The status render — the exact contract

`status.json` is a versioned document (`"schema": 1`) rewritten atomically each tick by one writer
(§3.4). The render is derived from it and nothing else.

```
run 20260919-201055 · project <work-project> · engine gsd 1.14.0 · epoch 7
started 21:10 · 4h 12m ago · status RUNNING · written 19s ago

capacity   claude-code/<profile-A>  window  32% used · resets 11:59Z  (read 11m ago)
           claude-code/work        window  7%  used · resets 17:50Z  (read 11m ago)
           glm/main                window  unknown — never proven this run
queue      ready 6 · active 2 · needs-input 1 · done 11 · (+3 arrived since start)

lanes
  L1  T-118  gsd:execute-phase  worktree <work-project>-p22  ctx 61%  working   1h 04m
  L2  T-121  gsd:plan-phase     worktree <work-project>-p23  ctx 18%  working     22m
  --  T-119                                                       needs-input 3h 41m
                                  "which of the two auth flows is canonical?" → QUESTIONS.md#Q-14

attention  1 item
  ! capacity read for glm/main has never succeeded this run — that lane is unschedulable

cost       supervision $0.41 · work — (not measured on subscription lanes)
```

Four rules the render obeys, each traceable to a recorded failure:

1. **`written NNs ago` is always printed, prominently.** A JSON file goes stale the moment its writer
   dies and then shows the last good state as though it were current. Exit code 2 when
   `now - written_at > 3 × tick_seconds`.
2. **Staleness is a fact displayed, never a verdict acted on.** `FIELD-NOTES.md` §1.5: heartbeat
   staleness is not a stall, and treating it as one produced 33 nudges to healthy sessions.
3. **`unknown` is printed as `unknown`, never as `0`.** From `agent-deck`'s rule — *"a wrong token
   number is worse than no token number"* (LANDSCAPE §4) — and from the previous generation's
   `weekly_all=unreadable%` degrading to a state the system treated as benign (C4 §3.1b, VERIFIED).
4. **A lane in `needs-input` prints the question and the anchor into the channel.** That is O3 made
   visible: he can read the whole of his obligation from one screen.

### 1.4 The proofs — everything that must be shown working before a run starts

R1-07 [199], R1-17 [395], R1-04 [153] and Д4 [433] each say the same thing in a different place:
*prove it, do not assume it.* The preflight is one pass with one output — a table of proofs, each
`proven | failed | unprovable`, and a refusal to start if a `required` proof is not `proven`.

| Proof | How | If it fails |
|---|---|---|
| `lock` | `flock -n` on the run lock | refuse, exit 73 |
| `adapter.<platform>` | `preflight(account)` per the adapter contract §2.1: binary present, **version pinned and recorded**, and **which account this spawn would use**, from the platform's own report | that platform's lanes are unschedulable |
| `account.<platform>/<name>` | the account assertion above, after a throwaway launch, not from the env var we set (ADAPTER-CONTRACT §3 F) | that account is unschedulable |
| `keychain.<account>` | on Claude Code / macOS: a non-interactive read that would raise the GUI dialog if access was never granted (`00-field-scan.md` §4, ADAPTER-CONTRACT §7 Q10) | **refuse by default** — an unattended run blocking on a dialog nobody sees is the cheapest night to lose |
| `capacity.<account>` | one `readCapacity`; result cached for `capacity_ttl` | lane runs with `Capacity: Unknown` policy (§7.1) |
| `board` | read one ticket; the five **role** statuses of §6.1 map to real statuses, **confirmed by the owner at config time, not derived** | refuse |
| `board.write` | write and revert one throwaway status transition or comment on a scratch ticket the owner names at config time | board becomes read-only for this run; `orchestrator:status` says so |
| `channel.<name>` | Telegram `getMe` · Slack `auth.test` · SMTP `EHLO`+auth · declared `test_command` for anything else (C9 §5.6 tier 1) | refuse if `notifications.required: true`, else downgrade to terminal-only and record it |
| `channel.<name>.delivery` | **one real message**, receipt stored (`message_id` / `ts`). Labelled *delivered*, never *seen* | as above |
| `questions.channel` | read it, and write+revert one probe item | refuse — a controlled run with no answerable channel cannot honour R1-14 |
| `engine` | the engine adapter's `describe()` returns a capability descriptor with no `unknown` on an axis the config depends on (§8.2) | refuse, naming the axis |
| `worktree.env` | for each lane template: create the worktree, run the declared readiness command, tear it down (Д4 [433]) | that lane template is unschedulable |
| `red_line` | the one prohibitions file (R1-15) exists, is readable, is under `red_line_max_bytes` | refuse |

The one real message of `channel.<name>.delivery` is output the owner did not ask for. That is a
knowing, minimal violation of O1, argued in §16.4.

---

## 2. Processes — what exists and who starts what

Six kinds. Only three of them ever hold a model.

```
       he types /orchestrator:run
                 │
                 ├─ preflight (model, once) ──▶ writes preflight.json, then
                 │
                 └─ spawns ──▶ PACER ◀── holds run.lock for the whole run
                                │        deterministic bash, no model, tick = 30s
                                │
        ┌───────────────────────┼──────────────────────┬─────────────────┐
        │                       │                      │                 │
      wakes                 launches                spawns            spools
        ▼                       ▼                      ▼                 ▼
      BRAIN                   LANES                  SCOUT           NOTIFIER
   (model, on demand)   (model, per ticket)    (cheap model, on a    (no model)
        │                  via adapters         confirmed change)
        │
        └── may request: spawn/stop a lane · claim/release a ticket · answer a question ·
            open a ticket · run an engine command · escalate to the Д6 channel

   WARDEN  — launchd KeepAlive, no model, every 120s, outside the run's process tree
   SENTINEL — model, another account/provider, every 4h, judgement only
```

### 2.1 The pacer

**Started by:** `/orchestrator:run`, via `setsid nohup`, after preflight passes.
**Holds:** `run.lock` (`flock -n`) for its entire lifetime, and a `caffeinate -i` bound to its own pid.
**Model:** none, ever. This is a hard invariant with a test.
**Tick:** `tick_seconds`, `DEFAULT-PROPOSED: 30`. Protects against: a cadence slow enough that a
`stop-hard` takes minutes to land (Д12 says the change applies on the next tick), and fast enough to
matter. At 30 s a 34-hour run is ~4,080 ticks; each tick is bash and `jq` over files already in the
page cache.

Each tick, in this order, short-circuiting on the first stop verb:

1. read `control.yaml` if `(mtime, size, inode)` moved → parse → classify changed keys (§10.3)
2. renew `lease.json`
3. run every liveness probe recorded in the journal for every live lane (§7.3) — zero tokens
4. read every lane's context reading from its adapter's bridge file (§7.2) — zero tokens
5. capacity: if any account's cached reading is older than `capacity_ttl`, refresh **one** account
   (never all, §7.1)
6. run the deterministic change detector over active tickets, tiers 0 and 1 only (§6.4)
7. evaluate the **decision predicates** (§2.2). If any fires and the wake budget allows, wake the brain
8. drain the notification spool
9. rewrite `status.json` atomically
10. append at most one `tick` line to the journal — **sampled**, `DEFAULT-PROPOSED: every 20th tick or
    whenever anything changed**. Protects against a journal that is 4,000 identical lines a night.

**Why the pacer and not the brain holds the lock.** The lock must die with its holder and never
earlier (ADOPTION-VERDICT §4.7, the flock contract: *"acquisition succeeds after process exit,
without a stale-lock timeout"*). A model session can be compacted, respawned, or replaced under
R1-08; the pacer cannot, because it is 400 lines of shell that never grows a context window. The
single-orchestrator invariant (R1-10 [300–302]) therefore rests on a process that has no reason to
die.

### 2.2 The brain — the orchestrator session

**Started by:** the pacer, never by the owner directly.
**Model:** yes. Role `orchestrator`, its own account per R1-07 [270].
**Lifetime:** `brain_mode`, `DEFAULT-PROPOSED: resident`. Two supported shapes, and the owner already
named both at [204] («як компактити, так і запускати повністю новий оркестратор»):

- `resident` — one long-lived session the pacer wakes by delivering a message over the adapter's
  `send` channel. Cheaper per wake (the project context is already loaded and cached), but it
  accumulates context and must be compacted (§7.2).
- `ephemeral` — a fresh session per wake, seeded from `handoff.md`. Costs a cold read every wake,
  but has no context problem and no compaction machinery at all.

`ephemeral` is strictly more operable and strictly more expensive. The default is `resident` because
the measured cost of a cold seed on a real project is a whole prompt-cache miss per wake, and the
wake count is in the low hundreds per night; §14 has the arithmetic. The choice is a config key.

**Decision predicates — the only reasons the pacer wakes the brain.** This list is the token budget.

| Predicate | Fires when | Wake class |
|---|---|---|
| `capacity_free` | a lane slot is free, a ticket is `ready`, dependencies satisfied, capacity policy permits | `dispatch` |
| `lane_terminal` | a lane's adapter handle reached `finished` / `failed` / `dead` | `harvest` |
| `lane_waiting_human` | the adapter reports `waitingOnHuman` — a *distinct* state from working (ADAPTER-CONTRACT §2.2) | `answer` |
| `stall_confirmed` | two independent signals agree on two consecutive ticks (§7.3 rule R1/R3) | `judge` |
| `ticket_changed` | tier-2 scout reported a change touching Outcome, Scope or a ticked AC anchor | `adapt` |
| `question_answered` | the Д6 channel gained an answer matching an open question id | `resume` |
| `capacity_threshold` | a soft or hard limit threshold crossed (§7.1) | `brake` |
| `context_threshold` | a lane armed for compaction and needs a step boundary judged (§7.2) | `brake` |
| `engine_escalation` | the engine emitted its own "wants a human" signal — for GSD, `human_needed` / `insufficient_spec` (C9 §3.1, VERIFIED) | `answer` |
| `control_change_warm` | a warm config key changed and needs applying at a boundary (§10.3) | `apply` |
| `drain_check` | no `ready` work and no live lanes, for `drain_grace` | `finish` |
| `repeated_failure` | the same ticket failed the same way `failure_streak` times (Д5, owner's number: 3) | `escalate` |

**Wake budget.** `brain_max_wakes_per_hour`, `DEFAULT-PROPOSED: 12`. On exhaustion the pacer stops
waking, raises an attention item, notifies if that type is configured, and keeps ticking. Protects
against the single worst recorded failure class: a detector that re-reads its own effect and re-fires
for ever (`FIELD-NOTES.md` §11.6 — 85 minutes, ~60 s apart, ended only by an external SIGTERM; and
the 1,085-times-over-five-days flag in the same section). A budget converts "acting the same way for
ever" into "acting twelve times and then telling someone", which is the behaviour the owner actually
wants and the previous generation never had.

**Idempotency.** Every predicate firing produces a `trip_key` — `(predicate, subject, epoch,
armed_at)` — written to `state/trips/<sha>.json` *before* the wake. A trip already on disk is not
re-fired. This is the watermark rule from C5 §5.6 non-negotiable 2, generalised from compaction to
every detector.

### 2.3 The lanes

**Started by:** the brain, through a platform adapter (§9), one per claimed ticket.
**Model:** yes, role `worker` (and `validator` etc. if the configured process asks for them).
**Isolation:** a git worktree per task off the main branch, Д4's stated default, with the declared
readiness command proven before the ticket is handed over.

A lane is not supervised by typing into it. The only channels are the adapter's `status`,
`transcript`, `readContext`, `send` and `answer` operations. `harness-term.sh` and the whole
screen-scraping family are **not carried forward** except as the interactive lane of §9.4.

### 2.4 The scout

**Started by:** the pacer, only after tier-0/tier-1 deterministic detection confirms a real body
change (§6.4).
**Model:** `models.scout`, `DEFAULT-PROPOSED: the cheapest model the configured provider offers`.
This is Д8 [466] implemented — «немає сенсу перевіряти фейбл моделю … чи змінився якийсь тікет».
**Input:** the textual diff, never the two full bodies. On GitHub the previous body is free from
`userContentEdits[].diff` (C3 §5.3, VERIFIED).
**Output:** which of Outcome / Scope / which AC anchors moved. Nothing else.
**Silence:** when nothing changed the scout is never invoked at all, which is stronger than "silent".

### 2.5 The warden

**Started by:** `/orchestrator:run`, which installs a **LaunchAgent** (`KeepAlive: true`,
explicit `ThrottleInterval`, explicit `EnvironmentVariables` for `PATH`, `CLAUDE_CONFIG_DIR`,
`GH_CONFIG_DIR`).
**Model:** none.
**Cadence:** `warden_seconds`, `DEFAULT-PROPOSED: 120`.
**Does exactly three things and restarts nothing on its own judgement:** read the lease; if
`now − renewed_at > ttl` **and** `flock -n` on the run lock succeeds, append a `health.probe` line
with the verdict and the evidence; if a recovery policy is configured, invoke `/orchestrator:resume`
**once**, subject to the crash-loop budget of §12.5.

Why launchd rather than `nohup`: `FIELD-NOTES.md` §12.4 (three detached scripts had to export their
own `gh` account because launchd and `nohup` start with no environment) and §11.6 (the previous
watchdog *"had already exited ('run finished') and was never restarted"* while a loop ran for 85
minutes). `KeepAlive` is the only thing that fixes the second, and only launchd has it.

### 2.6 The sentinel

**Started by:** the pacer on a schedule, `sentinel_hours`, `DEFAULT-PROPOSED: 4`.
**Model:** yes, on an account allowlisted for the `orchestrator` role, ideally a different provider —
this is R1-10 [246] as the owner stated it, and R1-07 [270]'s restriction.
**Inputs:** exactly three — the last N hours of `journal.jsonl`, the current `lease.json`, and the
board's diff over the same window. **One question:** *has this run produced anything in the last N
hours, and if not, why not?*
**Verdicts:** `progressing` · `stalled-but-recoverable` · `wedged` · `finished` · `unknown`. Written
to the journal; acted on or notified per config.

It is the only component that can catch a run that is alive, busy, costing money and producing
nothing — the `echo idle` lane (`FIELD-NOTES.md` §3.1) and the `docker desktop start` retry loop
(§11.1) are both invisible to every deterministic probe and both obvious to this one question.

### 2.7 The notifier

**Model:** none. Reads `outbox/*.json`, delivers, writes the receipt back, moves the item to
`outbox/sent/`. Retries with backoff; caps at `notify_max_per_run`,
`DEFAULT-PROPOSED: 40`, and **coalesces identical subjects within `notify_coalesce_minutes`**,
`DEFAULT-PROPOSED: 30`. Protects against the 1,085-identical-alerts case, which is a product failure
before it is an API failure (C9 §5.6).

---

## 3. The control plane

### 3.1 Paths

Two roots, and the separation matters: **configuration** obeys the owner's marketplace layout
(OWNER-DECISIONS 3.3) and is version-controlled or personal; **run state** is runtime and is
gitignored.

```
# Configuration — the owner's six binding slots, unchanged (see §10)
./.claude/shared/identity.json                       committed, general
./.claude/shared/plugins/orchestrator.json           committed, this plugin
~/.claude/shared/identity.json                       user, general
~/.claude/shared/plugins/orchestrator.json           user, this plugin
./.claude/shared/identity.local.json                 personal, gitignored
./.claude/shared/plugins/orchestrator.local.json     personal, gitignored
plugins/orchestrator/config/recommended.json         marketplace: advice, never a value

# Run state — one directory, gitignored, in the project
./.orchestrator/
  control.yaml                 THE watched file. One. (§3.3)
  control.yaml.lock            writer lock, never read
  control.ack.json             written by the pacer, read by the stop commands (§3.3)
  current                      symlink → runs/<run-id>
  claims/                      local backend only: <ticket-id>.d claim directories
  adapters/                    project-local platform adapters (§9.1)
  processes/                   custom process definitions (§8.3)
  runs/<run-id>/               run-id = YYYYMMDD-HHMMSS, local time, the owner's existing convention
    run.lock                   flock; held by the pacer; never read, never parsed, never cleaned up
    lease.json                 atomic rewrite every lease_renew_seconds
    journal.jsonl              append-only; the record of what happened
    ledger.jsonl               append-only; the record of what this run created and may destroy
    status.json                atomic rewrite every tick; the status command's only input
    preflight.json             the proof table of §1.4, frozen at start
    trips/<sha>.json           detector idempotency watermarks
    outbox/*.json              notification spool; outbox/sent/ after delivery
    lanes/<lane-id>/
      lane.json                the lane's own record; writer = the pacer
      handoff.md               position, not narrative; writer = the lane
      ctx.json                 context readings; writer = the adapter's bridge
      cursor                   transcript cursor, opaque
      stdout.log, stderr.log   the lane's process output, never a terminal
    questions/<qid>.json       the orchestrator's mirror of a Д6 channel item
    artifacts/
      RUN-REPORT.md
      NEXT-RUN.md
      tuning.patch.yaml
    logs/pacer.log             the pacer's own stderr, rotated at rotate_bytes
```

**The Д6 questions channel is deliberately not in this tree.** It is wherever the owner put it — a
file in his repo, a GitHub issue with a tag, a task in the tracker (Д6 [449]). The orchestrator
holds a *mirror* under `questions/` so that a channel outage does not lose the question, and so that
the status render can print it without a network call.

### 3.2 Formats, and one rule per format

| File | Format | Why |
|---|---|---|
| `control.yaml` | YAML | the owner named YAML [118] and he hand-edits this one |
| `journal.jsonl`, `ledger.jsonl` | JSONL, one fact per line, ≤ `journal_line_bytes` (`DEFAULT-PROPOSED: 4096`) | appendable without a lock; greppable; a truncated last line is one lost fact, not a lost file |
| `status.json`, `lease.json`, `lane.json`, `preflight.json`, `ctx.json` | JSON, `"schema": <int>` | machine-read by a script with `jq`; the integer moves on any breaking change, following `git status --porcelain=v2` and GSD's `--exit-contract=v1\|v2`, both precedents on this machine (VERIFIED) |
| `handoff.md` | Markdown | a human reads it at 03:00, and a fresh session is seeded with it |
| `RUN-REPORT.md`, `NEXT-RUN.md` | Markdown | he reads them |
| `tuning.patch.yaml` | YAML | it is a diff against `control.yaml` |

### 3.3 `control.yaml` — the one file the owner and the commands write

The owner's decision is explicit (Д12 [520–524]): the stop command *writes into the file the
orchestrator reads every tick*, and the change applies on the next tick. R1-07 [195] puts account
assignments in one re-read file. Д7 [455] puts behaviour overrides there too. The analysis notes
that nothing in his answers says these are the same file — but nothing says they are not, and one
file is what he described in each case. **Decision: one file.** The tension this creates is in §16.5.

```yaml
# .orchestrator/control.yaml — read every tick. Hand-edit freely; changes apply per §10.3.
schema: 1

stop: null              # null | hard | soft | <custom-name>
stop_reason: ""
stop_at: null           # ISO8601, written by the command

mode: autonomous        # autonomous | controlled   (R1-14; overridable per run)

lanes:
  max: 2                # R1-05: the user sets the maximum
  intake: capped        # open | capped | frozen    (Д2, §6.6)
  intake_cap: 20

accounts:               # R1-07: role → provider/account, re-read every tick
  orchestrator: { platform: claude-code, account: <profile-B>, change: soft }
  worker:       { platform: claude-code, account: <profile-A>, change: soft }
  scout:        { platform: glm,         account: main,       change: soft }
  sentinel:     { platform: codex,       account: personal,   change: soft }

behaviour:              # Д7: changeable DURING the run, overriding the run's own choice
  when_only_human_blocked: wait     # wait | finish
  on_repeated_failure: notify_stop  # notify_stop | stop | continue
  on_contradicting_change: ask      # adapt | restart | finish_then_new_ticket | orchestrator | ask

custom_stops:           # Д12: "прочитати що це означає і відповідно зробити"
  gentle: |
    Finish the plan currently being executed, commit it, write its summary,
    push the branch, do not open a PR, leave the worktree in place, then stop.
```

**Write protocol.** Every writer — the owner's editor is not a writer we control, so: every *command*
— takes `flock control.yaml.lock`, re-reads, applies a **leaf-level merge that preserves comments,
anchors and key order**, writes to a random-suffix sibling in the same directory, `fsync`s, and
`rename()`s. It never follows a symlink at the destination. Mode `0600` inside a `0700` directory.
This is the settings-file protocol taken from `dsh` (ADOPTION-VERDICT §4.9), which is already
designed, including the failure mode the owner would otherwise discover by hand-editing at 02:00.

**Read protocol.** The pacer reads on `(mtime, size, inode)` change, parses, and:

- **parse failure → keep the last good document**, raise an attention item, notify if that type is
  configured, and never exit. *Boot fails loud, reload keeps last good.* A YAML typo at 02:00 must
  not kill the run.
- **self-write suppression by content**, not by timestamp: the pacer records the sha256 of the
  document it last wrote and ignores a change whose sha matches.

**`control.ack.json`** is the pacer's reply, so the file never needs a writer that is also a reader:

```json
{"schema":1,"read_at":"2026-09-19T21:41:09Z","doc_sha256":"7f3c…","epoch":7,
 "applied":["stop"],"deferred":[{"key":"lanes.max","until":"lane boundary"}],
 "rejected":[{"key":"engine","reason":"cold key — needs a new run"}],
 "parse":"ok"}
```

`/orchestrator:stop` reads it to tell the owner whether his command landed, which is the one thing
the previous generation could never tell him: `FIELD-NOTES.md` §11.2 records two real operator
instructions — `push master` and `carry on with the queue` — sitting unsubmitted in input boxes
while the engine's log recorded them as delivered.

### 3.4 Single-writer table

Multiple writers to one file is the mechanism behind `FIELD-NOTES.md` §2.1, where the watch loop
truncated `state/attention` every cycle and destroyed a night of another process's corrections
unnoticed. So: **every file has exactly one writer, named here, and a lint rule enforces it.**

| File | Writer | Readers | Mode |
|---|---|---|---|
| `run.lock` | the kernel | nobody | `flock`; never parsed |
| `lease.json` | pacer | warden, resume, sentinel | atomic rename |
| `journal.jsonl` | **any component**, append-only | everyone | `O_APPEND`, no locks, never truncated |
| `ledger.jsonl` | the component that created the thing, append-only | teardown | `O_APPEND` |
| `status.json` | pacer | status command | atomic rename |
| `control.yaml` | owner + `orchestrator:*` commands, under lock | pacer | lock + atomic rename |
| `control.ack.json` | pacer | commands | atomic rename |
| `lanes/*/handoff.md` | that lane | brain, resume | atomic rename by the lane |
| `lanes/*/ctx.json` | that platform's context bridge | pacer | atomic rename |
| `outbox/*.json` | whoever raises the notification (one file each) | notifier | create-new, never append |
| `trips/*.json` | whoever fires the predicate | pacer | create-exclusive (`O_EXCL`) |

**`journal.jsonl` is the exception and it is the important one.** It is append-only, every line is
self-describing, nobody locks it, nobody rewrites it, and no component may glob it away. That last
clause is not decoration — it is the direct negation of §2.1 of the field notes.

### 3.5 The journal

One line per lifecycle fact. Vocabulary, deliberately small:

```
run.create · run.finish · orchestrator.claim · orchestrator.claim.refused · orchestrator.release
lease.renew (sampled) · epoch.bump
lane.spawn · lane.observe · lane.close · lane.orphan
step.intent · step.result
ticket.claim · ticket.release · ticket.transition · ticket.comment
capacity.read · capacity.hit · context.read · context.trip · context.proof
brain.wake · brain.decision · scout.report · sentinel.verdict
health.probe · provider.failover · control.apply · stop.apply
owner.action · notify.send · notify.receipt
```

Line shape, with the fields that earn their place:

```json
{"seq":41,"at":"2026-09-19T20:11:03.114Z","epoch":7,"event":"lane.spawn",
 "run":"20260919-201055","lane":"L1","ticket":"T-118",
 "actor":{"platform":"claude-code","account":"<profile-A>",
          "config_dir":"/Users/…/.<switcher>/profiles/<profile>","version":"2.1.278",
          "session_id":"ac653a10-…","pid":86924,
          "proc_start":"Sat Sep 19 12:51:09 2026","host":"<host>","boot_id":1788417532},
 "probe":{"cmd":["claude","agents","--json"],
          "env":{"CLAUDE_CONFIG_DIR":"/Users/…/.<switcher>/profiles/<profile>"},
          "match":{"sessionId":"ac653a10-…"},"alive_when":"row present","status_field":"status"}}
```

Four properties, each with its reason:

1. **`epoch` on every line.** It is the fencing token (§12.3) and it is also the crash-loop detector:
   N `orchestrator.claim` lines within T minutes with no `step.result` between them *is* a restart
   loop, findable with `grep` alone. That is the owner's own stated fear — «нескінченний цикл
   оркестраторів» [300] — made detectable by one field.
2. **`probe` is data, not code.** The journal carries *how to ask whether this actor is alive*, in
   the actor's own terms, including its environment. This is R1-10 [310] («для кожної платформи
   можна налаштовувати») and [312] («може написати свої власні скіли») expressed as a field. A
   platform nobody has installed costs one config entry, not a code change.
3. **`step.intent` before the side effect, `step.result` after**, both carrying
   `action_id = run:epoch:lane:step:attempt`, and **the dedup key goes into the side effect itself** —
   the ticket comment, the branch name, the commit trailer. A replayer can then find it without
   trusting the journal. This is the *"append `start` first, `end` last"* discipline
   (ADOPTION-VERDICT §4.8): a crash leaves a detectable orphan rather than a false claim of
   completion, which is the whole of the "reported success and did nothing" class
   (`FIELD-NOTES.md` §4.1, §11.4, §12.7).
4. **For a configured process, the journal records a reference, not a copy.** R1-06.3 [189] is
   explicit: use the process's own records, supplement only what is missing. For GSD that is literally
   one line, because GSD publishes a witness anchor of its own (VERIFIED, `.planning/STATE.md`
   frontmatter carries `state_head`, a git sha):
   `{"event":"step.result","process":"gsd","ref":".planning/STATE.md","state_head":"5154f24…","read_at":"…"}`

---

## 4. The run state machine

```
                       ┌──────────────┐
                       │  PREFLIGHT   │  model runs once; proofs of §1.4
                       └──────┬───────┘
                 refused ◀────┤ all required proofs proven
                              ▼
                       ┌──────────────┐
             ┌────────▶│   RUNNING    │◀────────┐
             │         └──┬───┬───┬───┘         │
             │            │   │   │             │
   window reset reached   │   │   │      answer arrives / capacity returns
             │            │   │   │             │
        ┌────┴─────┐      │   │   │        ┌────┴─────┐
        │  PAUSED  │◀─────┘   │   └───────▶│ HOLDING  │
        │ capacity │  soft/hard limit      │ human    │
        └──────────┘                       └──────────┘
                              │
                     queue empty for drain_grace
                              ▼
                       ┌──────────────┐        stop hard / soft / custom
                       │   DRAINING   │◀──────────────────────────┐
                       └──────┬───────┘                           │
                              │ every lane terminal               │
                              ▼                                ┌──┴───────┐
                       ┌──────────────┐                        │ STOPPING │
                       │   CLEANUP    │◀───────────────────────┘          
                       └──────┬───────┘   ledger-driven teardown (§13)
                              ▼
                       ┌──────────────┐          lease expired + lock free
                       │   FINISHED   │          ┌──────────┐
                       └──────────────┘          │   DEAD   │  ← from anywhere
                                                 └──────────┘
```

| State | Meaning | New lanes? | Live lanes | Exit to |
|---|---|---|---|---|
| `PREFLIGHT` | proving §1.4 | no | none | `RUNNING`, or refuse (exit 69) |
| `RUNNING` | normal | yes | yes | any below |
| `PAUSED(capacity)` | a window is exhausted or a threshold crossed; **`resume_at` is known** | no | soft: yes · hard: stopped | `RUNNING` at `resume_at` |
| `HOLDING(human)` | only human-blocked work remains (Д7) | no | none | `RUNNING` on an answer; `DRAINING` if `when_only_human_blocked: finish` |
| `DRAINING` | no ready work; letting live lanes finish (Д3) | no | yes | `CLEANUP` |
| `STOPPING(hard\|soft\|custom)` | a stop verb is in force (§11) | no | per verb | `CLEANUP` |
| `CLEANUP` | ledger-driven teardown | no | none | `FINISHED` |
| `FINISHED` | artifacts written, lock released | — | — | terminal |
| `DEAD` | the lease expired and the lock is free; only an outside observer can assert this | — | unknown | `/orchestrator:resume` |

**`PAUSED(capacity)` exists only when `resume_at` is knowable.** On a `Credit` platform there is
nothing to wait for — the model is money, not time (ADAPTER-CONTRACT §3 E). A credit exhaustion
therefore goes to `HOLDING(human)` with a notification, never to `PAUSED`. A scheduler written
against "pause until `resetAt`" waits for ever on a credit platform; this is the sum type earning
its keep.

**`DEAD` is never self-asserted.** A process cannot write "I am dead". It is a verdict the warden or
a resuming orchestrator reaches from two facts: the lease is older than its TTL **and** `flock -n`
on the run lock succeeds. Both, never one.

---

## 5. The lane state machine

```
QUEUED ──claim won──▶ CLAIMED ──worktree + env proven──▶ SPAWNING ──adapter Handle──▶ WORKING
                          │                                   │
                          │ claim lost / floor now fails      │ launch failed
                          ▼                                   ▼
                      RELEASED                              FAILED

WORKING ──adapter: waitingOnHuman──▶ WAITING ──answer delivered──▶ WORKING
WORKING ──ctx ≥ threshold ×2 fresh──▶ ARMED ──boundary (soft) / now (hard)──▶ COMPACTING
                                                                  │
                          COMPACTING ──rank-1/2 proof──▶ WORKING   │ no proof in verify_timeout
                                                                  ▼
                                                             RESEEDING ──new session──▶ WORKING
                                                                  │ still failing
                                                                  ▼
                                                             HELD (needs a human)

WORKING ──adapter: finished──▶ HARVEST ──engine says done──▶ DONE
                            └─▶ HARVEST ──engine says not done / produced nothing──▶ NEEDS_INPUT
WORKING ──adapter: failed/dead──▶ FAILED ──streak < N──▶ QUEUED   (retry)
                                        └──streak = N──▶ NEEDS_INPUT  (Д5)
WORKING ──stop-hard──▶ STOPPING ──adapter stop("hard")──▶ STOPPED
WORKING ──stop-soft──▶ (finish the step) ──▶ HARVEST
any     ──orchestrator restarted, lane still alive──▶ ADOPTED | ORPHANED   (Д10, §12.6)
```

| State | The one fact it asserts | Who moves it out |
|---|---|---|
| `QUEUED` | a ticket is `ready` and unclaimed | brain, on `capacity_free` |
| `CLAIMED` | this run holds the claim; nobody else may take the ticket | brain |
| `SPAWNING` | a launch is in flight; **the session id may not exist yet** | adapter |
| `WORKING` | the adapter says `working` | adapter / pacer |
| `WAITING` | the adapter says `waitingOnHuman` — never conflated with `working` | brain (answer) or the Д6 channel |
| `ARMED` | two fresh consecutive context readings above threshold | pacer |
| `COMPACTING` | a trigger rung has fired and a watermark is on disk | pacer, on proof |
| `RESEEDING` | compaction is unproven or dead here; a successor session is being opened | adapter |
| `HARVEST` | the session is terminal; the outcome is not yet decided | brain |
| `NEEDS_INPUT` | stopped, waiting on a human, with a `reason` | the Д6 channel |
| `HELD` | the orchestrator has run out of moves | the owner |
| `DONE` / `FAILED` / `STOPPED` / `RELEASED` / `ORPHANED` | terminal | — |

**`SPAWNING` is a real state and not an implementation detail.** On five of the fifteen platforms the
server mints the session id, so there is a crash window between launch and the first durable record
(ADAPTER-CONTRACT §3 B). A lane that crashes inside `SPAWNING` is **recovered by re-dispatch, never
by resume**, and the ticket claim is released first. On Gemini CLI a session with no completed model
turn is deleted and is unresumable, which makes this the only correct behaviour there.

**`HARVEST` is the state the previous generation did not have, and it cost it a phase.** Sortie's
ADR 0020 states the problem better than I can: the handoff transition *"asserts something about a
run's output, and the test applied to it described only the run's exit"* (LANDSCAPE §4). A lane that
exits 0 having produced nothing took the same path as one that did the work, *"silent in every
channel an operator watches"*. So `HARVEST` asks the engine, not the exit code, and has three
answers: done, not done, or undeterminable.

`harvest_evidence`, `DEFAULT-PROPOSED: observed` — withhold `DONE` only on positively *observed*
emptiness; `strict` also withholds an undeterminable verdict; `off` restores exit-code behaviour.
Three values rather than a boolean, because absence of evidence is not evidence of absence. The two
errors are not symmetric: advancing an empty ticket moves work in a system we do not own and puts it
in front of a person; withholding leaves it in a queue we keep watching, with the withholding
recorded.

---

## 6. How work is claimed and released

### 6.1 The five states are roles, not names

R1-04 [153] says board statuses are user-overridable and adapt to the chosen process. So the
orchestrator never learns a status *name*; it learns a mapping to five roles.

| role | meaning | who writes it |
|---|---|---|
| `backlog` | exists, not offered | human |
| `ready` | may be claimed now | human, or the orchestrator on a passing sufficiency check |
| `active` | claimed, being worked | **orchestrator only** |
| `needs-input` | stopped, waiting on a human; carries a `reason` | orchestrator |
| `done` | finished | orchestrator |

The preflight `board` proof requires a mapping for each role the configured process needs, and
**presents the proposed mapping to the owner for confirmation rather than deriving it silently** —
on ClickUp a status literally named `review` was observed typed `done` (C3 §5.2, VERIFIED), so
derivation is a trap. His «людина може перевизначити» [153] stays the authority.

### 6.2 The readiness floor — deterministic, zero model

`state` may become `ready` only if the body carries `## Outcome`, `## Scope`, `## Acceptance
criteria`, at least one `- [ ]` inside the AC fence, no `[NEEDS CLARIFICATION]` marker anywhere, and
every `dependencies` id resolves. Milliseconds, no tokens, and measured to hold across 327 real
tickets. Re-checked on **every** transition including release, not once at creation — that is what
«її притримувався» [146] means operationally.

Deliberately **not** required: tests, a repo, a branch, EARS, Gherkin. N2 [344] forbids assuming any
of them.

### 6.3 Claiming

**Rule:** only the orchestrator moves a ticket to `active`. Executors never claim. It follows from
the single-orchestrator invariant and it is an explicit invariant with a check, not a convention.

**Belt and braces,** because the rule is one crashed-and-restarted orchestrator away from being
violated (Д10 [497]):

| backend | claim primitive | measured |
|---|---|---|
| local files | `mkdir .orchestrator/claims/<id>.d` | 1 winner at 50-way (C3 §5.4, VERIFIED) |
| GitHub | `POST /git/refs {"ref":"refs/heads/claim/<id>"}` | 422 if taken (VERIFIED) |
| ClickUp | **no CAS exists** — assignee + re-read | and the config output must say the guarantee is absent, rather than imply one |

The claim carries `{holder, run_id, epoch, taken_at, heartbeat_at}` and `heartbeat_at` is refreshed
on a tick.

### 6.4 Change detection while a ticket is claimed — three tiers, model last

This is Д8 [466] and it is the single largest cost lever in the design.

- **Tier 0 — did anything change at all?** Free. GitHub: one conditional request per active ticket
  (`If-None-Match`) — **304, zero quota** — or the whole set folded into one 2-point GraphQL poll.
  Local: `stat` + sha256 of the body region. ClickUp: one `date_updated_gt` sweep for the board.
  Nothing changed → **no model is invoked at all**. That is «нічого назад не поверне» achieved
  deterministically rather than by a model deciding to stay quiet.
- **Tier 1 — was it the description, or just a comment or a label?** Still no model. Compare
  `lastEditedAt` / body sha256 against the `source_watermark` taken at claim time.
- **Tier 2 — what changed and does it matter?** Now the scout, on the diff only.

`body_digest` and `source_watermark` live in the run's state, **never on the board** — writing them
into the issue body would itself move `lastEditedAt` and the detector would trigger itself.

Measured cost of the tiering, from real ticket sizes (median body 3,932 bytes) and the bundled
pricing reference: a frontier model reading every body every tick is ~$14 per 8-hour night at three
lanes; the cheapest model is ~$1.42; **tiers 0–1 deterministic with the model only on a real change
is ~$0.01** (C3 §5.3, INFERRED from measured sizes and quoted prices). The owner's instinct was right
by a factor of ten; the tiering makes it several hundred.

### 6.5 Release

Release only if the lane is idle beyond `claim_stale_minutes` (`DEFAULT-PROPOSED: 45`) **and** the
readiness floor still passes; otherwise print `STUCK — needs a human` and leave it. Two fixes the
previous generation needs and this design ships:

- idleness is driven by `heartbeat_at` **in the claim**, never by the ticket's `updatedAt`, which the
  orchestrator's own comments bump;
- the previous state label is **removed** on transition, so a ticket cannot hold `blocked` and `done`
  at once. Seen twice (`FIELD-NOTES.md` §12.6).

### 6.6 Mid-run intake (Д2), with a brake

The owner's decision stands: added work is picked up if ready. His answer does not reach *volume*,
and the previous run's queue grew 236 → 327 in a day and he stopped it by hand. So a setting in his
own vocabulary, `intake`: `open` · `capped` (`DEFAULT-PROPOSED`, cap 20) · `frozen`. Whatever the
mode, **the ready-count delta since start is printed in the status render**, because that is the
signal that made him intervene last time.

---

## 7. Capacity, context and liveness — observing and acting

Three different physics, three different policies, one rule in common: **no signal a session can
author is ever admissible alone.**

### 7.1 Capacity

`Capacity = Window{used_pct, resets_at} | Credit{remaining, unit} | Unknown`. A sum type with a
policy per variant, decided once, centrally (ADAPTER-CONTRACT §6.1).

| Variant | Soft threshold behaviour | Hard threshold behaviour | Exhausted |
|---|---|---|---|
| `Window` | stop dispatching; live lanes finish | `stop(handle,"hard")` on lanes, checkpoint, `PAUSED(capacity)` until `resets_at` + `resume_margin` | `PAUSED`, auto-resume |
| `Credit` | stop dispatching; notify | as `Window` hard, then **`HOLDING(human)`** | notify, **never auto-resume** — the next unit is money |
| `Unknown` | conservative local ledger only | react to `detectLimitHit` in-band, nothing else | `HOLDING(human)` |

**`Unknown` lanes never get the role whose capacity the orchestrator must predict.** They can be
workers; they cannot be the orchestrator or the sentinel.

**How capacity is read, and the three traps that are already verified on this machine (C4 §3.1):**

- The endpoint is undocumented and **has already drifted once under a running system**: the previous
  harness parses a `.limits` array that no longer exists, so every read yields empty, and
  `weekly_all=unreadable%` recurs across many separate days. **Mitigation: enumerate every non-null
  bucket that has a `utilization` and stop on the worst**, never hardcode `five_hour`/`seven_day`;
  and treat a parse that yields nothing as `Unknown`, which is a *refusal to schedule*, not a
  proceed. `limits.on_unreadable`, `DEFAULT-PROPOSED: hold` (the previous generation's default was
  `proceed`, and that is how an unreadable read became invisible).
- **The endpoint throttles brutally.** Measured here: 8 rapid calls → calls 3–8 returned
  `rate_limit_error`; a 15 s-interval probe was still limited at t+167 s. So the reading channel is
  itself scarce: `capacity_ttl`, `DEFAULT-PROPOSED: 3600 s` per account, **one account refreshed per
  tick at most**, jittered, with mandatory exponential backoff on `rate_limit_error`. Whether the
  throttle is per-token or per-IP is UNKNOWN; if it is per-IP, polling several accounts shares one
  budget and rotation buys nothing.
- **An idle account cannot be polled at all** — a profile nobody has used lately has a stale OAuth
  token and returns `authentication_error`. This contradicts a natural reading of R1-07 [199]: you
  can verify *switching*, you cannot verify *headroom*, for an account you are not currently running
  on. The preflight says so in the proof table (`capacity.<account>: unprovable`) rather than
  pretending.

**In-band limit detection** (`detectLimitHit`) is required even where the read is native, because
prediction and reaction fail differently. It matches **by source**: a bounded window of structured
CLI diagnostics — result/error records, assistant API-error messages, relevant system events — and
never ordinary assistant text. A `result` record counts as diagnostic only when it authenticates
itself (`is_error:true`, `terminal_reason:"api_error"`, or a non-zero `api_error_status`); `subtype`
is explicitly not consulted, since a genuine rate-limit result has been observed carrying
`subtype:"success"` (LANDSCAPE §4, ralphex). Transient 529/502/503/504 are a separate retry set.

**Screen-scraping for a limit banner is struck from the design.** It produced two independent
multi-hour false-positive loops (85 minutes and 45 minutes) in the previous generation, one of them
by matching the orchestrator's *own wrapped prose*.

**Capacity readings the operator sees**: in the status render, with their age, and `unknown` printed
as `unknown`.

### 7.2 Context

R1-08 is the strongest thing the owner said in the whole interview: *«повинен бути механізм, який
гарантовано робить цю дію»*. And `FIELD-NOTES.md` §3.3 records that **nothing in the previous plugin
measures context at all** — `grep -E 'compact|ctx=|auto-compact' bin/*.sh` returns nothing.

**Read — never from the screen.** One adapter operation, `readContext(handle) → {used, window, pct,
isEstimated} | unknown`, with `missing ≠ zero` and `isEstimated` mandatory. For Claude Code the
primary is our own `statusLine` command writing `{session_id, used_percentage, total_input_tokens,
context_window_size, at}` to `lanes/<id>/ctx.json` and then `exec`ing whatever status line the owner
already had — event-driven, exact, zero tokens, and the same payload carries `rate_limits` for §7.1.
It edits the owner's `settings.json`, so it needs his explicit yes; the fallback that needs no
permission is tailing the transcript JSONL and summing the last assistant row's
`input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

`percent` is defined once, `percent_raw = 100 − remaining_percentage`, matching `/context`. A
threshold migrated from the old screen-scraped numbers must be **restated, not carried** — the two
scales differ by about 13 points.

**Arm — two consecutive fresh readings.** One reading may be a mid-compaction render. Hysteresis on
the way down, or the loop re-arms for ever.

**Trigger — a ladder, cheapest rung first**, per platform, declared in the adapter's capabilities:

```
rung 0  make it unnecessary   configure the platform's own auto-compact to fire just past our number
rung 1  native call           Codex thread/compact/start · opencode POST /compact
rung 2  peer message          deliver "wrap up and end your turn" over the adapter's send channel
rung 3  keystroke             interactive lane only, all four preconditions of §9.4 checked
rung 4  close-and-reseed      write position → new session → point it at the position
```

**Verify — only a signal the compaction itself produced.** Rank 1: a `PostCompact` hook / a
`thread/compacted` item / a `session.compaction.*` event. Rank 2: a `compact_boundary` record in the
transcript. Rank 3: `context_window.current_usage == null` in the next status payload. Rank 4, last
resort and the one that lies: the percentage dropped below `threshold − hysteresis` on a reading
strictly newer than the watermark plus grace. **Returning success without proof is forbidden**; where
compaction is proof-less the orchestrator records it as *unproven* and says so in the report.

**Failure is a timer, not a guess.** No rank-1/2 signal within `verify_timeout`
(`DEFAULT-PROPOSED: 10 m`; measured 67 % → 0 % in about seven) means the trigger did not execute.
Escalate one rung, log both percentages.

**Three states abort the ladder and go straight to rung 4**, all VERIFIED as real: a session
reporting `autocompact: fixed prefix … — compaction cannot help`; `Autocompact is thrashing: … 3
times in a row`; auto-compact `failure_breaker_open`. Any of them means *compaction is dead in this
session* — no further attempts, open a successor.

**Close-and-reseed is built once, centrally,** because it is the only platform-independent fallback
and four platforms have no external trigger at all. It changes ticket→session from one-to-one to
**one-to-many**, so the ledger holds a *lineage*, not a field. §16.1 prices this.

**Two rules that apply to both paths.** Refresh the position file first and **prove the file moved**
(mtime), never proceed on the instruction having been sent. And **never compact with a deliberate
mutation applied** — gate on `git status --porcelain` clean or on an explicit `unsafe-to-compact`
marker the lane writes; rung 0 cannot honour this, which is the one strong argument for keeping our
threshold below the platform's auto-compact point.

**The soft boundary is "a step", and the step is configurable** (R1-08 [209]).
`context.step`, `DEFAULT-PROPOSED: "the current plan/ticket is committed and its summary written"`.
The lane *emits* a step-boundary marker so the pacer never has to infer one.

**Refill rate, not just level.** `FIELD-NOTES.md` §3.1: one lane put 3,466 of 3,626 Bash calls into
the literal command `echo idle`, ~1,400/hour, adding 445k tokens — 77 % of all context growth in that
window — and reaching 91 %; it stopped within one minute of being told to end its turn. So
`Δpercent/hour` above `ctx_refill_alarm` (`DEFAULT-PROPOSED: 20 %/h`) is a **defect predicate**, not
a compaction predicate: the brain is woken to tell the lane to end its turn, which is a hundred times
cheaper than compacting the consequence.

**Every role has its own thresholds**, because their positions differ in where they live:

| role | default | why |
|---|---|---|
| worker lane | `75 %`, soft, compact in place | its position is already on disk — plans, summaries, engine state |
| scout / sentinel | n/a — `ephemeral` by construction | |
| brain (`resident`) | `66 %`, soft, compact in place **after a verified handoff refresh**; reseed if the refresh cannot be verified | its position is *not* implicitly on disk; the handoff is the only copy |

### 7.3 Liveness and progress — the signal contract

R1-09 delegates the judgement to the orchestrator. It cannot judge well on signals whose failure
modes are unknown, and **every cheap signal's failure mode is already known from this system's own
logs**:

| Signal | What it proves | Documented false positive |
|---|---|---|
| `flock` refused | an orchestrator process exists | none |
| `kill -0 pid` | a process with that number exists | PID reuse; says nothing about wedged |
| pid + `proc_start` + `boot_id` | **that exact process** | none known |
| adapter `status` | the platform's own idle/busy/waiting | invisible under the wrong account env |
| adapter `waitingOnHuman` | blocked on a human | none known |
| heartbeat file age | the last **turn boundary** | six healthy sessions nudged (FN §1.5) |
| transcript mtime | a message was appended | silent for a whole long turn |
| tool-call cadence | tools are being called | 3,466 `echo idle` calls, zero progress (FN §3.1) |
| child-shell count | a command is running | a shell that can never exit reads as work (FN §2.2) |
| git activity | real output landed | silent for planning, research, docs — and N2 says there may be no repo |
| screen scrape | **nothing reliably** | the 85-minute loop; four detector false positives in one day |
| ticket transition | a status was written | the underlying action may have done nothing (FN §4.1) |

**Three rules, and they are the whole of the stall policy:**

- **L1 — no single signal raises or clears a stall.** A verdict needs two *independent* signals —
  independent meaning they cannot both be produced by the same cause. Heartbeat age and transcript
  mtime are **not** independent; a long turn silences both.
- **L2 — anything the session can author is inadmissible alone.** Screen text, self-reported status,
  a log line the session wrote. This rule alone would have prevented the 85-minute loop, the 45-minute
  banner loop and the validator's own quoted warning triggering a full alarm.
- **L3 — observe before acting, and the observation must survive to the next tick.** The 33 nudges
  happened because the first observation was also the action. A verdict requires the same reading on
  two consecutive ticks, which is only true if the intervening observation is journal-appended rather
  than written to a file something else truncates.

**What replaces the nudge: nothing.** The bare Enter is deleted. It never submitted stranded text
(measured twice), it destroyed a recovery attempt, and five instructions were never delivered by the
typing family it belongs to. A lane that needs something is sent something over the adapter's `send`
channel, which returns an `Ack` that is a **state machine, not a boolean** — `accepted ≠ delivered ≠
processed`, and `accepted` may never be reported as `delivered`.

**Probe hygiene, two rules from measured failures.** A probe that can return empty on error **must
distinguish empty from failed** — BSD `find -newermt "-10 minutes"` errors out and, with stderr to
`/dev/null`, returns empty every time, which would have declared every healthy session idle for ever.
And a probe that has never once returned a positive in this run is reported as **unproven**, not as
clean, in the status render and in `NEXT-RUN.md`.

### 7.4 Where the judgement the owner asked for actually lives

R1-09 says the orchestrator decides. In this design the *predicates* are deterministic and the
*decision* is the brain's. The pacer never decides that a session is stalled; it decides that two
independent signals agreed twice, which is a fact. The brain is woken with those facts plus the
lane's transcript tail and decides what to do. The sentinel, every four hours, decides the one thing
neither can: whether the run as a whole is producing anything.

That is the honest split, and it is also the design's weakest point (§17).

---

## 8. Driving the engine without owning it

R1-03 [118] is settled and strict: one existing process (GSD, superpowers, another marketplace's
tooling) **or** a fully custom one. **No mixing.** R1-13 [344] is equally strict: verification belongs
to the process; the orchestrator imposes no checks of its own.

### 8.1 The boundary, stated as one rule

> The orchestrator decides **which ticket, in which place, on which account, and when to stop**.
> The engine decides **what to do with the ticket, and whether it is done**.

Everything else follows. The orchestrator never inspects a diff for quality, never runs a test suite
to form an opinion, never overrides a verification verdict. It does verify **its own** actions — that
a merge moved the branch, that a step it dispatched actually started — and §16.6 records that this
distinction was never put to the owner.

### 8.2 The engine adapter — four operations and a descriptor

```
describe()            → EngineCapabilities   (no network, no tokens)
plan(ticket, lane)    → Step[]               what this engine will do for this ticket
probe(lane)           → EngineState          position, from the engine's own records, zero tokens
signals(lane)         → EngineSignal[]       done · needs-human · failed · produced-nothing
```

`EngineCapabilities` uses a **closed vocabulary per axis**, and distinguishes `undocumented` from
`none` — a missing declaration and a declared absence are different facts. It degrades closed and
says which of the two happened. All three rules are lifted directly from GSD's own
`host-integration.cjs`, which already implements exactly this shape pointed at the host (VERIFIED,
`PROTOCOL_VERSION = 1`, `SAFE_DEFAULTS`, `degradationFor()` *"NEVER throws"*).

An engine capability the run's configuration depends on and that reports `undocumented` **refuses
the run at preflight, naming the axis**. Telling the owner an engine "declares no isolation
primitive" when the *resolver* failed is a lie, and GSD's own docs name that exact mistake.

### 8.3 The GSD adapter — the operability prize

GSD publishes machine-readable surfaces that cost **zero model tokens**, all executed against a real
GSD project (VERIFIED, C9 §3.1):

| call | gives the orchestrator |
|---|---|
| `gsd-tools progress` | `phases[] {number,name,plans,summaries,status}`, `percent` |
| `gsd-tools smart-entry` | `Phase 7 of 7 · 75% · executing` + the recommended next action |
| `gsd-tools state` | the whole resolved config: `branching_strategy`, `auto_advance`, `mode`, `use_worktrees`, `test_command` |
| `gsd-tools worktree base-check` | `shouldDegrade`, `reason`, `headSha`, `forkRef`, `forkSha` |
| `gsd-tools git base-branch` | the base branch |
| `gsd-tools runtime-identity` | `{"packageName":"@opengsd/gsd-core","version":"1.14.0"}` — the version pin for the journal |
| `.planning/STATE.md` frontmatter | `current_phase`, `current_plan`, `status`, `stopped_at`, `state_head` (a git sha) |
| `references/honest-verifier.md` behaviour | the engine's own `human_needed` / `insufficient_spec` escalation — a ready-made `engine_escalation` predicate |

Global flags that matter: `--pick <field>`, `--project-dir <path>`, `--json-errors`, and
**`--exit-contract=v1|v2`** — GSD versions its own exit codes, so the adapter pins the contract
version and records it.

So **`probe()` for GSD is three subprocess calls and no model.** That is the difference between a
supervisor that costs pennies a night and one that costs dollars an hour, and it is why the GSD
adapter is the first one to build.

Two collisions the adapter must resolve at config time, not at 03:00:

- **Worktree ownership.** Д4's default is every task in its own worktree off the main branch; GSD's
  executor worktrees fork from `origin/HEAD` and GSD's own `worktree.baseRef` is not read by the host
  (VERIFIED). Both cannot hold. `worktree_owner`: `orchestrator` (sets GSD `workflow.use_worktrees:
  false`, gets the uniform default, loses intra-phase parallelism) or `engine` (GSD owns it, base is
  `origin/HEAD`). `DEFAULT-PROPOSED: orchestrator`, because Д4 is his stated default and because the
  ledger-driven teardown of §13 can only destroy worktrees this run created.
- **Branch-name drift.** GSD computes a branch name from the roadmap slug and it was observed one
  word off the lane's branch, which left alone would have cut a fresh branch from `origin/master` and
  lost the merged tip (VERIFIED). The adapter reads GSD's computed name and **asserts equality with
  the lane's branch before any execute step**, and holds the lane on a mismatch.

### 8.4 A custom process

A directory under `.orchestrator/processes/<name>/` with one `process.yaml`:

```yaml
schema: 1
name: my-flow
roles: [ready, active, needs-input, done]      # the board roles this process needs
steps:
  - id: build
    run: "npm run build"
    on_fail: "The build failed. Read the output above and fix it before continuing."
  - id: test
    run: "npm test"
    on_fail: "Tests failed. Fix them."
    optional: false
  - id: review
    agent: my-reviewer-skill
completion:
  all_steps_passed: true
```

A step is a command plus **the sentence the agent is told when it fails** — the `backpressure.gates`
shape from Ralph Orchestrator, which makes "independent verification" a config file rather than a
second agent (LANDSCAPE §4). Engine-agnostic, fifteen lines, and it keeps R1-13 intact because the
checks are entirely the user's.

**No mixing, enforced.** `engine: gsd` and a `process:` key in the same resolved config is a
preflight refusal, not a merge. R1-03 [118]: «комбінувати ні, тут або або».

---

## 9. How a platform adapter plugs in

### 9.1 Where it lives

```
plugins/orchestrator/adapters/<id>/        shipped with the plugin
~/.claude/shared/plugins/orchestrator/adapters/<id>/   the owner's own
./.orchestrator/adapters/<id>/             this project's own
```

Later paths win, per the owner's precedence rule. Each directory holds `adapter.json` (the manifest)
and an executable `adapter` that speaks one JSON-per-line protocol on stdin/stdout. Any language; the
orchestrator never imports it.

### 9.2 The manifest declares capabilities before anything runs

```json
{"schema":1,"id":"claude-code","binary":"claude","pin":"2.1.278",
 "home_env":"CLAUDE_CONFIG_DIR",
 "capabilities":{"A":"native","B":"native","C":"native","D":"native","E":"native",
                 "F":"native","G":"native","H":"native","I":"native","J":"native"},
 "quotaModel":"Window","idAssignment":"client","attachable":true,"sandbox":true,
 "ops":["preflight","launchHeadless","launchAttached","resume","stop","status","transcript",
        "readContext","compact","readCapacity","detectLimitHit","selectAccount","send","answer"]}
```

`capabilities()` comes first and must be derivable with no network call and no model token. **The
orchestrator plans the run against this map and asks the owner a question for every `impossible` that
a configured requirement depends on.** An adapter that reports `native` and then degrades at 03:00 is
the single worst failure this contract exists to prevent, and *"never report `native` for a
capability whose only implementation is a regex over English prose"* is a rule, not advice.

### 9.3 The twelve required operations, and the four that carry the design

Required for tier-1: `preflight`, `launchHeadless`, `resume`, `stop`, `status`, `transcript`,
`readContext`, `compact`, `readCapacity`, `detectLimitHit`, `selectAccount`, `send`, `answer`.
Optional: `launchAttached`, `costMeter`.

Four contracts are load-bearing and I restate them because breaking any one of them reintroduces a
recorded failure:

- **`status` distinguishes `waitingOnHuman` from `working`.** Conflating them is how an overnight run
  dies quietly.
- **`compact` returns a `Proof` or `"unsupported"`.** Success without proof is forbidden. If the
  platform mints a successor session id, the adapter remaps ticket→session **atomically** before
  returning.
- **`send` returns an `Ack` state machine**, and must expose stranded or queued text so a `stop` can
  hand it back.
- **`selectAccount` returns environment only** — it never mutates the owner's config, keychain or
  home — and the caller verifies the account **after** launch from the platform's own report.

### 9.4 Ten invariants every adapter honours

Each is a verified silent-failure mode from a named spike, and each becomes a contract test:

1. **Never branch on the exit code.** Aider returns 0 on auth failure, rate limit and success alike;
   pi `--mode json` exits 0 on provider failure; GLM exits 0 on quota exhaustion *with*
   `subtype:"success"`; MiMoCode's exit code is always 0.
2. **Never trust HTTP 200 or a `success` string.**
3. **Always close or own stdin.** Codex hangs all night without `< /dev/null`; Aider exits instantly
   *with* stdin closed and needs a pty instead.
4. **Always impose an external wall-clock timeout.**
5. **Always pin the version and disable auto-update.** Amp shipped five releases in fifteen hours;
   Copilot 835 versions in twelve months. A run that starts on one flag surface and finishes on
   another is indistinguishable from a bug in the orchestrator. The pin is recorded in the journal.
6. **Always pin the model explicitly.** Inheriting the owner's `~/.codex/config.toml` produced a
   100 %-failing run.
7. **Keep stdout and stderr separate.**
8. **Union the roster across accounts.** A roster read under one account shows half the fleet.
9. **Re-attach permission and question handlers on every resume**, not only on create.
10. **Assert teardown by process, not by the command's word.** `cursor-agent worker kill` reports
    success and leaves the process at 100 % CPU — the "reports success and does nothing" class, alive
    in a second platform.

### 9.5 The interactive lane

R1-11 [324] wants per-platform choice of interactive, headless, or hybrid, and the orchestrator
answering a session's own `AskUserQuestion` within configured authority. The field is closing that
door: DeepSeek's Claude Code provider disables `AskUserQuestion`; acpx makes a fixed-choice question
fail with `user-answer-required` *taking precedence over every escape hatch*; OpenClaw's `ask_user`
is main-session-only; Claude Code's `--bg` session cannot be answered at all.

So the design keeps both lanes and is explicit about which is which:

- **headless lane (default)** — for work that can run to completion. A question here is a **terminal
  outcome**: the lane goes to `NEEDS_INPUT`, the question is posted to the Д6 channel with a
  `Fallback`, and other lanes keep working. This is O3 working exactly as the owner described it.
- **interactive lane (opt-in per platform)** — a real terminal for work that must be answerable. It
  costs a multiplexer, it costs the keystroke preconditions, and on Terminal.app it does not work at
  all (`send` and `key` are explicitly refused as undrivable, VERIFIED). Where it is enabled,
  keystrokes are gated on four preconditions, every one checked and none assumed: the adapter says
  `idle`; **zero child shells** counted from `ps`, not read off the screen; the input line is empty
  (because `send` destroys pending text); and the position file's mtime has moved.

`takeover` on a platform with no attachable pane is a **handoff** — stop, relaunch attached, resume —
which costs one restart and must be visible in the run log, never silent.

**Escalation format.** Every escalation carries a `Fallback`: what happens if nobody answers. That is
the one format that demonstrably worked, eleven times out of eleven, in the 34-hour run. And the
`Q-PARITY-01` obligation is a rule: **if the question is settleable by running something inside the
blast radius, run it first and escalate only the residue.**

---

## 10. Configuration across the owner's scopes

### 10.1 The six binding slots are unchanged

The orchestrator is a citizen of his marketplace, so it inherits OWNER-DECISIONS 3.3 and 4.15 whole,
lowest to highest:

```
1  ./.claude/shared/identity.json                  project, general, committed
2  ./.claude/shared/plugins/orchestrator.json      project, this plugin, committed
3  ~/.claude/shared/identity.json                  user, general
4  ~/.claude/shared/plugins/orchestrator.json      user, this plugin
5  ./.claude/shared/identity.local.json            project, general, personal
6  ./.claude/shared/plugins/orchestrator.local.json project, this plugin, personal
```

A person's own files beat the project's committed files; within a person's files, this project beats
home; within either, the plugin file beats the general one. `never` entries accumulate across a
person's own files and hold against everything including his own pick; a committed file's `never`
cannot strike a personal pick. `plugins/orchestrator/config/recommended.json` is **advice with a
`strength` field, never a value**. The read is mandatory on every invocation; if the resolver did not
run, the agent merges from what it has by the same rules.

What goes where, per 3.4's reusability test: **almost everything reusable goes in the general
config.** Concretely, `identity.json` holds the notification channels, the questions channel, the
account/provider inventory and the red-line file path — all of them plainly usable by other plugins.
`orchestrator.json` holds only what nothing else could use: tick cadence, lane caps, context
thresholds, the engine selection, the stop vocabulary.

### 10.2 The run scope is the seventh, and it is `control.yaml`

R1-04, Д7, Д12 and R1-14 all require a **run** scope that outranks everything and is changeable
*during* the run. The owner's marketplace has six slots and no run scope, and LANDSCAPE §5 records
that nobody in the field has three. So:

> **`control.yaml` is the run scope. It is not a seventh config file band — it is a runtime overlay
> that sits above all six, is created at `run` from the resolved six, and is deleted with the run.**

This keeps 3.3 literally intact (no new config path) while giving Д12 the file it needs. The `run`
command writes the resolved six into `control.yaml` as the starting document, with a header comment
naming which slot each value came from — so a hand-edit at 02:00 is an informed one.

`/orchestrator:config --promote` copies a value that proved itself during a run back into the owner's
own file, which is 3.9 and 6.1 in the ordinary way.

### 10.3 How a mid-run change is picked up — the hot/warm/cold table

Sortie has the best reload semantics in the field precisely because it publishes *which keys do not
rebuild on reload*. Every key in `control.yaml` carries exactly one class.

| Class | Applied | Examples |
|---|---|---|
| **hot** | next tick | `stop`, `mode`, `behaviour.*`, `accounts.*` with `change: hard`, `lanes.max` **downward**, `intake`, notification types, context thresholds |
| **warm** | at the next lane boundary | `accounts.*` with `change: soft`, `lanes.max` **upward**, worktree template, the step definition |
| **cold** | **never mid-run** | `engine`, `process`, the board backend, the questions channel, the platform adapter set |

A cold key edited mid-run is **rejected, named in `control.ack.json`, and reported** — not silently
ignored and not silently applied. This is R1-07's soft/hard vocabulary [195] generalised: hard = act
now, soft = at the next safe boundary, and cold is the honest third case the owner did not name,
because some changes genuinely cannot be made to a running process.

**`accounts.*` with `change: hard` deserves its own line**, because R1-07 asks for something no
platform can do: changing a *running* session's account is impossible on all fifteen (VERIFIED). A
hard account change therefore means **stop the lane, relaunch on the new account, re-seed the
context** — paying for the context a second time. The design does it, logs it as a handoff with the
cost, and §16.3 records that the owner should be asked whether that price is acceptable or whether a
hard account change should in fact wait for the step boundary.

---

## 11. The stop verbs

Д12 is the one item the analysis marks **UNRATIFIED** — the session ended before confirmation. The
design implements exactly what he said and flags the status.

| Verb | Written as | Effect | Live lanes | The run |
|---|---|---|---|---|
| `stop-hard` | `stop: hard` | now | `adapter.stop(handle,"hard")` on every lane; stranded text handed back and journaled | → `STOPPING` → `CLEANUP` |
| `stop-soft` | `stop: soft` | at the next boundary | no new dispatch; every lane runs to its `context.step` boundary and harvests | → `STOPPING` → `CLEANUP` |
| `stop-custom <name>` | `stop: <name>` | read `custom_stops.<name>` and do what it says | the brain is woken once with the text and the lane inventory, and executes within the blast radius | → per the text, then `CLEANUP` |

**The mechanism is his:** the command writes into the file the pacer reads every tick, and the change
applies on the next tick. Worst-case latency is `tick_seconds` (30 s by default), which is why the
tick is not slower.

**`stop-custom` is the only stop verb that costs a model token**, and it costs exactly one wake. A
custom stop that cannot be executed inside the blast radius is refused with the reason in
`control.ack.json`, and the run falls back to `stop-soft` — refusing loudly rather than doing
something adjacent.

**The orchestrator-exempt carve-out.** Gas Town's `ESTOP` has the detail worth copying verbatim: the
coordinator is exempt from the stop so it survives to coordinate recovery. Here: `stop-hard` stops
lanes and stops dispatch; it does **not** kill the pacer, which must live to run `CLEANUP`, write the
artifacts, release the claims and release the lock. `/orchestrator:stop --hard --abandon` is the
separate, louder verb that kills the pacer too, and it leaves the run in `DEAD` for `resume` to find.

**What a stop leaves behind is a promise:** every claim released or explicitly marked stranded, every
ledger entry either torn down or listed in the report as *left running, deliberately*, and
`RUN-REPORT.md` written. A stop that leaves no report is a bug.

---

## 12. Crash, and how recovery decides

### 12.1 The primitive

`flock -n` on `run.lock`, held by the pacer for its whole life. Nothing reads it, nothing parses it,
nobody cleans it up. If a process holds it, an orchestrator is alive; if `flock -n` succeeds, none is.
The kernel is the authority and it is never wrong: *"acquisition succeeds after process exit, without
a stale-lock timeout"*. **This is the whole of «відслідковувати і не дозволяти» [301]** — one line of
shell, which is what «надійна річ, дуже проста» [300] asked for.

Where `flock` cannot reach — a stale `lease.json` written by a process on another host or before a
reboot — the identity check is **PID → process start time → argv shape**, failing closed when the
cmdline reader is unavailable. Process start identity catches PID recycling even when the replacement
has the same argv.

### 12.2 What survives a crash

| Survives | Because |
|---|---|
| every fact the journal recorded | append-only, `O_APPEND`, never rewritten, never globbed |
| everything this run created | the ledger, same discipline |
| the position of each lane | `handoff.md`, refreshed on a cadence, not only at a threshold |
| the position of the work | the engine's own records (for GSD: `.planning/`, `STATE.md`, `state_head`) |
| the claims | on the board / in `claims/`, with `heartbeat_at` |
| the retry budget | **durable and charged before dispatch**, so it survives the orchestrator's own death — which is the case where looping forever actually happens |
| the owner's answers | in his channel, which the orchestrator does not own |

| Does **not** survive | Consequence |
|---|---|
| a lane's in-session working memory | re-seeded from `handoff.md`, or the lane is re-dispatched |
| a session in `SPAWNING` on a server-minting platform | re-dispatch, never resume |
| `status.json`'s currency | the render prints `written NNs ago` and exits 2 |
| anything written only to a terminal | which is why nothing is |

### 12.3 The fence

`epoch = max(lease.epoch, max epoch in the journal) + 1` at each claim. Every externally visible act
carries it: a `orchestrator-epoch: 7` trailer on ticket comments and status transitions; session
names shaped `o7-w-T118` so a stale-epoch session is identifiable at a glance in a roster *and in a
terminal title* — which matters, because in the 34-hour run the owner read a terminal title as a
second orchestrator; and an `Orchestrator-Epoch: 7` trailer on commits the orchestrator itself makes.

**The rule the fence buys:** *a step may only be committed by the epoch that opened it; anything
arriving from a lower epoch is recorded and discarded, never applied.* Without it, an orchestrator
that wakes from a rate-limit pause can merge a phase the new one already merged. With it, the second
merge is refusable and, more importantly, **loud**.

Honest trade-off: `flock` alone covers crash and SIGKILL, which is most of reality. The epoch is the
extra 10 % that covers *pause*, and pause is the owner's own named death mode («кредит закінчився»
[266]). Ship `flock` first; epoch trailers are incremental hardening that cost nothing even before
anything checks them.

### 12.4 The recovery decision tree

Entered by a fresh start, a warden callback, or `/orchestrator:resume`.

```
0. ACQUIRE  flock -n run.lock
   ├─ refused → an orchestrator is alive. Append orchestrator.claim.refused with the reason.
   │            EXIT 0. Do not spawn. Do not notify.               ← R1-10 [301], literally
   └─ acquired → continue

1. IDENTIFY THE PREVIOUS HOLDER   (lease.json + the journal tail)
   a. no lease                     → first start → step 3
   b. host ≠ me OR boot_id ≠ mine  → cannot be evaluated here → treat as dead, record the limitation
   c. pid alive AND proc_start matches AND lock was free
                                   → contradiction. Record it, HOLD, notify. Never guess.
   d. otherwise                    → dead; record the verdict AND the evidence in prev{}

2. CRASH-LOOP CHECK
   N orchestrator.claim lines in the last crash_window with no step.result between them
   → stop claiming, write DEAD-RUN, notify, wait for a human.       ← §12.5

3. RECOVER POSITION, in the order the owner configured (R1-10 [293],[307])
   default: state files (journal + ledger + handoffs + the engine's own records)
   then, if allowed: the previous sessions and their transcripts
   then, if allowed: a platform-specific recovery skill the owner wrote himself

4. RECONCILE LANES  (Д10)
   for each lane the journal says was live:
     run its recorded probe
     ├─ alive and the ticket is still claimed by this run → ADOPT: re-attach transcript cursor,
     │                                                       re-attach question handlers, continue
     ├─ alive but the ticket moved on                     → ORPHAN: record, do NOT kill
     │                                                       (killing is a decision, §13 owns it)
     └─ dead                                              → release the claim if the floor still
                                                            passes, else NEEDS_INPUT

5. RECONCILE THE BOARD
   any ticket in `active` whose claim.holder is a dead run of this project → release or NEEDS_INPUT

6. BUMP EPOCH, write lease, append orchestrator.claim, resume the tick.
```

Step 1c is the case everything else gets wrong: a live process that did not hold the lock. It is a
contradiction, and the design's answer is to **hold and tell a human** rather than to pick a story.

### 12.5 The crash-loop budget

Backoff `60 s → 120 s → 240 s`, capped at 15 minutes. Budget: `claim_budget`,
`DEFAULT-PROPOSED: 3 claims in 60 minutes`. On exhaustion: stop claiming, write `DEAD-RUN`, notify
through the configured channel, and wait for a human.

Two honest notes. The number 3 is borrowed from the owner's «Три рази» [442], which he said about *a
task failing the same way three times*, not about orchestrator restarts, and he immediately added «В
який момент не знаю». Reusing it keeps one vocabulary; it is a proposal, not his decision. And the
*shape* is Erlang's — the supervisor terminates and escalates rather than retrying for ever — because
the recorded failure mode is not acting wrongly, it is **acting the same way for ever**.

### 12.6 Restart with executors still alive (Д10)

The owner's decision: the orchestrator analyses what those sessions are and decides to stop or wait,
within its permissions. Implemented as step 4 above, with one addition the lens insists on: **adopt
is cheaper than restart and is therefore the default** where the probe says alive and the claim still
holds. A lane that has been working for two hours is two hours of tokens; killing it because the
supervisor restarted is the most expensive possible reaction to the cheapest possible failure.

---

## 13. How the run ends, and what it cleans up

### 13.1 The terminal condition

Д3 [430]: no ready work left → finish, and stop **what it started** — sessions, docker containers,
services — «щоби не залишати хвостів», without touching anything else.

LANDSCAPE §5 records that this is genuinely unowned: every tool in the survey with a real multi-ticket
queue is an explicitly resident daemon, and all of them return zero hits for
`drainAndExit | exitWhenIdle | shutdownWhenEmpty | queueEmptyExit`. So this is the moat and nobody
will build it for us.

```
drain_check fires when:  zero tickets in `ready` whose dependencies are satisfied
                    AND  zero lanes in a non-terminal state
                    AND  that has held continuously for drain_grace     (DEFAULT-PROPOSED: 5 min)
                    AND  intake has not admitted anything in that window
```

`drain_grace` exists because a board write can be eventually consistent and because a lane can move a
ticket to `ready` as its last act. Five minutes is cheap; a run that ends thirty seconds before its
own last ticket appears is not.

**`HOLDING(human)` is not a terminal condition.** When only human-blocked work remains, Д7's default
is *stay and wait* and the owner may change that **during** the run — so the pacer keeps ticking at a
reduced cadence (`hold_tick_seconds`, `DEFAULT-PROPOSED: 300`) reading `control.yaml` and the Д6
channel, and nothing else. Cost while holding: zero tokens, indefinitely.

### 13.2 Teardown is driven by the ledger and by nothing else

**The rule, stated abstractly as the owner asked [373]:** *the orchestrator may stop only a thing
whose identifier it wrote into the ledger at the moment it created it.*

No pattern matching, ever. No `pkill -f`, no `killall`, no `docker compose down` without an explicit
project name this run created. A lint rule in the test harness fails the build if `pkill`, `killall`
or an unscoped `docker compose down` appears anywhere in plugin source.

Every creation writes a ledger line at the moment of creation:

```json
{"seq":12,"at":"…","epoch":7,"kind":"worktree","id":"/Users/…/<work-project>-p22",
 "created_by":"L1","teardown":{"cmd":["git","worktree","remove","--force","…"],"verify":"path absent"}}
{"seq":13,"kind":"process_group","id":8834,"created_by":"L1",
 "teardown":{"signal":"TERM","then":"KILL","after_s":30,"verify":"kill -0 fails"}}
{"seq":14,"kind":"compose_project","id":"orc-20260919-L1","labels":["orchestrator.run=20260919-201055"],
 "teardown":{"cmd":["docker","compose","-p","orc-20260919-L1","down"],"verify":"docker ps -q --filter label=… empty"}}
{"seq":15,"kind":"session","id":"ac653a10-…","platform":"claude-code",
 "teardown":{"op":"stop","verify":"status == dead"}}
```

`CLEANUP` walks the ledger in reverse and **verifies each teardown by observation, not by the
command's word.** `cursor-agent worker kill` reports success and leaves the process at 100 % CPU
(VERIFIED); a merge printed `Already up to date` and did nothing (VERIFIED). Anything that will not
die is listed in `RUN-REPORT.md` under *left running* with its identifier, which is strictly better
than a silent orphan.

This is why it matters that it is cheap: it costs nothing for the owner to configure, it is entirely
inside the plugin, it is identical on every engine, and it makes the two recorded incidents where his
own parallel work was hit — the `pkill -f 'playwright test'` that killed an unrelated lane because
every lane's own prompt contains that literal string, and the `docker compose down -v` with no
`COMPOSE_PROJECT_NAME` that destroyed his default stack — **structurally impossible**.

What it cannot do, stated plainly: it is about processes, containers and services. It does nothing
about files, and it constrains the orchestrator, not its children — a lane can still run `pkill`
itself. §16.7 is where that gap lives.

### 13.3 What `FINISHED` means

Claims released · ledger drained or listed · lanes terminal · `RUN-REPORT.md`, `NEXT-RUN.md` and
`tuning.patch.yaml` written · a `run.finished` notification **if that type is configured** · the
`current` symlink left pointing at the run · the lock released last.

The lock is released last, after the report is on disk, so that a resume racing a finish cannot
observe a run with no record.

---

## 14. Cost, and the morning artifact

### 14.1 The supervision budget

This is the lens's central claim, so it is stated as arithmetic rather than as an adjective.

| Component | Model? | Invocations in a 34-hour run | Basis |
|---|---|---|---|
| pacer tick | **no** | ~4,080 | 30 s cadence; bash + `jq` |
| liveness probes | **no** | ~4,080 × lanes | `claude agents --json` measured at 0.18 s, 0 tokens |
| context reads | **no** | event-driven | status-line bridge writes a file |
| engine probes (GSD) | **no** | ~4,080 | three `gsd-tools` calls |
| capacity reads | **no** | ~34–68 | one account per tick, TTL 3600 s, jittered |
| change detection tier 0/1 | **no** | ~4,080 × active tickets | 304s and sha256 |
| scout (tier 2) | yes, cheapest | only on a confirmed body change — observed: single digits | Д8 |
| **brain wakes** | yes | bounded by 12/h → ≤ 408; realistically ~60–120 from the observed event counts (19 phases, 13 merges, 11 questions) | §2.2 |
| sentinel | yes, another account | 8–9 | every 4 h |
| **total supervision** | | | **well under $1 at cheap-model pricing, and it is bounded by a budget rather than by luck** |

Compare with what is being replaced: the previous generation's context watch **refilled 9 % → 91 % of
its own context window in about ten hours of ordinary cycling**, purely from watching. Watching cost
more than some of the work.

Three cost rules fall out and they are config, not code:

- **`models.*` is a per-role pin, not a per-lane one** (§6.5 of the adapter contract): orchestrator,
  worker, validator, scout, sentinel each pin a model *and a provider*. Cost asymmetry between
  providers is larger than scheduling asymmetry — Droid's credit multipliers span 150× between its
  cheapest and dearest model.
- **A `Credit` lane carries a hard spend ceiling**, and on Claude Code `--max-budget-usd` is a native
  per-session cap in print mode enforced by the tool rather than by a supervisor's polling — a real
  hard stop, and the previous generation never used it.
- **Concurrency ceilings can be contractual, not technical.** GLM's plan tiers allow 1 / 1–2 / 2+
  concurrent sessions and three violations get the account banned; Kimi pools all devices and API keys
  into one account pool, so two lanes on one Kimi account halve each other rather than doubling
  throughput. `lanes.max` is therefore per-account, not per-run, and the preflight records the
  contractual ceiling it was told.

### 14.2 What the orchestrator refuses to spend tokens on

Named explicitly, because every one of these was a real cost in the previous generation: reading a
ticket body that has not changed; judging whether a healthy session is healthy; rendering status;
deciding to pause on a limit; re-reading its own log; polling for a subagent (`Monitor` or ending the
turn, never `echo idle`); and formatting a notification.

### 14.3 The morning artifact

Three files, written at `FINISHED` (and at every stop), designed to be read in about four minutes.

**`RUN-REPORT.md`** — what happened. Position, never narrative: tickets by final state with the
reason for each non-`done`; the trunk's before/after sha and every merge with its verification
verdict; every escalation with its `Fallback` and whether it was answered; every `PAUSED` window with
its cause and duration; everything **left running** with its identifier; every proof that was
`unprovable` at preflight and whether it bit.

**`NEXT-RUN.md`** — the artifact the brief asks for, and the one the previous generation had no
equivalent of. Four sections, all mechanical:

1. **Detector scorecard.** Every detector: firings, confirmed, false, never-fired. A detector with
   zero confirmed firings is reported as **unproven**, not as clean — because a probe that can never
   succeed also never complains (`find -newermt` returning empty for ever is the recorded case).
2. **Threshold traffic.** Every threshold that tripped, how often, and whether the trip changed
   anything. A context threshold that armed eleven times and compacted once is a badly placed
   threshold, and that fact is only visible here.
3. **Where the time and the tokens went.** Per lane: wall clock, brain wakes attributable to it,
   scout invocations, compactions and reseeds, and the ratio of waiting-on-human to working.
4. **What the owner had to do.** Every `owner.action` line: the questions he answered and how long
   they blocked, the hand-edits to `control.yaml`, the manual interventions. This is the list whose
   shrinking is the actual measure of the product.

**`tuning.patch.yaml`** — a proposed diff against `control.yaml`, derived only from the above, that
`/orchestrator:config --apply-tuning` will apply after he reads it. Nothing is applied automatically;
a system that retunes itself overnight is a system whose behaviour he cannot predict, which is the
opposite of this lens.

---

## 15. The defaults register

Every default I invented, in one place, with what it protects against. None of these is the owner's
decision; each is a `DEFAULT-PROPOSED` he can overturn with one line.

| Key | Default | Protects against |
|---|---|---|
| `tick_seconds` | 30 | a stop verb taking minutes to land; a cadence too fast to be free |
| `hold_tick_seconds` | 300 | burning cycles while holding for a human, indefinitely |
| `warden_seconds` | 120 | a dead orchestrator going unnoticed for an hour |
| `lease_renew_seconds` / `lease_ttl` | 30 / 180 | a slow tick reading as a death |
| `brain_mode` | `resident` | a cold prompt-cache miss on every wake |
| `brain_max_wakes_per_hour` | 12 | the 85-minute self-sustaining loop class; 1,085 identical flags |
| `capacity_ttl` | 3600 s, one account per tick, jittered | the measured 2-call budget and multi-minute recovery on the usage endpoint |
| `limits.on_unreadable` | `hold` | an unreadable quota read degrading to a silent proceed |
| `resume_margin_seconds` | 90 | resuming one second before the window actually resets |
| `context.threshold` worker / brain | 75 % / 66 % raw | the platform choosing the compaction moment mid-mutation |
| `context.mode` | `soft` | compacting in the middle of a deliberate change |
| `context.step` | "plan committed and summary written" | an undefined boundary that never arrives |
| `verify_timeout` | 10 m | believing a compaction that did not happen (measured: ~7 m for 67 %→0 %) |
| `ctx_refill_alarm` | 20 %/h | the `echo idle` class — treating the symptom instead of the defect |
| `lanes.max` | 1, per account | two concurrent image builds OOM-killing the owner's own container; contractual concurrency bans |
| `intake` / `intake_cap` | `capped` / 20 | a queue growing 236 → 327 in a day with nobody noticing |
| `harvest_evidence` | `observed` | a lane that exits 0 having produced nothing taking the done path |
| `failure_streak` | 3 (his number, Д5) | an infinite retry on a deterministic failure |
| `claim_budget` | 3 claims / 60 min | an orchestrator restart loop |
| `claim_stale_minutes` | 45 | releasing a claim from a healthy lane mid-long-turn |
| `drain_grace` | 5 min | finishing thirty seconds before the last ticket appears |
| `notify_max_per_run` / `notify_coalesce_minutes` | 40 / 30 | 1,085 identical alerts |
| `journal_line_bytes` | 4096 | one enormous line making the journal unreadable by `jq` |
| `worktree_owner` | `orchestrator` | the engine cutting a branch from `origin/HEAD` and losing the merged tip |
| `models.scout` | cheapest available | Д8, and a factor of ten in cost |
| `sentinel_hours` | 4 | a live-but-useless run going unnoticed all night |
| `red_line_max_bytes` | 8192 | a prohibitions file too large to re-inject after every compaction |
| `stop` latency | one tick | — |

---

## 16. Where a decision is impossible or uncomfortable as stated

Designed for, not replaced. Each names exactly which part is impossible and what it costs to keep.

### 16.1 R1-08 — «механізм, який гарантовано робить цю дію»

**Impossible part:** *guaranteed* compaction on Amp, Gemini CLI, Cursor and DeepSeek `dsh`, where
there is **no external compaction trigger at all**. On those, hard mode ("stop now, compact,
continue") is not implementable; only soft mode via a threshold set **before** the run and
unchangeable during it — which also breaks the cross-cutting rule that a mid-run change is picked up.

**Cost to keep it:** close-and-reseed, built once and centrally. It works everywhere. It costs the
lane its working memory and one full context re-seed, and it turns ticket→session into a **lineage**
rather than a field, which changes the ledger, the status render and every place that says "the
session for this ticket". That is the price, and it is paid in code, not in the owner's time.

**What is not kept:** on those four platforms, "guaranteed" means "guaranteed to end up with a usable
session", not "guaranteed to compact". The status render and the report say `compaction: unproven`
for those lanes rather than implying otherwise.

### 16.2 R1-06.1 — «дочекатись рестарту ліміту і продовжити»

**Impossible part:** on seven of the fifteen platforms there is **nothing to wait for** — the model is
money, not time. And the soft/hard percentage ladder of R1-06.2 needs a percentage that does not
exist on a credit model.

**Cost to keep it:** `Capacity` becomes a sum type with a policy per variant (§7.1) and the `Credit`
variant substitutes a **money ceiling** for a percentage and **a notification** for an auto-resume.
Concretely, the owner has to state a number he has never stated: a spend ceiling per run. Until he
does, a `Credit` lane runs with `Unknown` policy, which means it is never given a role whose capacity
must be predicted.

### 16.3 R1-07 — a *hard* account change

**Impossible part:** changing a running session's account, on **all fifteen** platforms.

**Cost to keep it:** stop the lane, relaunch on the new account, re-seed the context — paying for that
context a second time, and losing whatever in-session memory the handoff does not carry. The design
does this and logs it as a handoff with its cost. The honest question, which should go to round 2, is
whether he wants that price on a `hard` change or whether a hard account change should in fact wait
for the step boundary — at which point `hard` and `soft` differ only in urgency, not in mechanism.

### 16.4 Д11 vs R1-17 — "no output" vs "prove the channel works"

**The tension:** proving a notification channel works requires **sending one real message** (§1.4),
which is output he did not ask for, in a channel he chose. And a run that cannot reach him is a run he
will not know has stopped.

**Resolution taken:** terminal silence is absolute and non-negotiable. Channel output is not "output"
in Д11's sense — Д11 is about a terminal he is looking at. The one preflight message is sent once, per
channel, per run, and is labelled as a test. `notifications.probe_message: false` turns it off and
downgrades the proof to credentials-only, with the downgrade recorded.

### 16.5 One control file for three jobs

**The tension:** Д12's stop commands, R1-07's account assignments and Д7's behaviour overrides all
land in "the file the orchestrator reads every tick", and the analysis notes nothing says these are
the same file. One file means a hand-edit and a `stop-hard` can race; two files mean two protocols and
two more ways to be out of sync.

**Resolution taken:** one file, because that is what he described three times, with a cross-process
writer lock, a comment-preserving leaf merge, atomic rename, and `control.ack.json` as the reply
channel so no writer is also a reader. The residual risk: an owner editing the file in `vim` while
`/orchestrator:stop --hard` writes it will produce one of the two versions, not a merge. Mitigation:
the stop command re-reads and re-applies after writing, and reports what it observed.

### 16.6 R1-13 — verification belongs to the process

**Kept as stated.** The orchestrator imposes no checks of its own, even though the evidence shown to
him included a merge that reported success and did nothing and a truncated suite read as a pass.

**The distinction that was never put to him**, and should be in round 2: does the same rule cover the
orchestrator's **own** actions? When the orchestrator runs a merge and git reports `Already up to
date` because it merged a branch into itself, no process verified anything — the orchestrator did the
thing. This design assumes the answer is "the orchestrator verifies its own actions" (§8.1, §13.2)
and flags the assumption rather than hiding it.

### 16.7 R1-16 — his parallel work in the same folder

**Kept as stated:** no deterministic isolation, «дуже якісь простий та надійний варіант».

**What the simple version actually covers:** the ownership ledger (§13.2) makes the two recorded
incidents impossible, costs him nothing, and is entirely inside the plugin. Worktrees (Д4's default)
turn "the same folder" into a different folder for most work.

**What remains genuinely unsolved, in this design and in the entire field:** file-level collision
between the orchestrator's work and his own editing in the same checkout. LANDSCAPE §5 confirms it
unanimously — thirteen of eighteen surveyed tools isolate with a worktree, and **not one protects the
human's concurrent edits in the same checkout**. Orca's guards are about the tool deleting the wrong
tree, not about two writers. This has to be invented, and this document does not invent it.

### 16.8 R1-15 — one text file, no enforcement

**Kept as stated.** One file, mandatory reading for every agent, no enforcement machinery.

**One mechanical addition that does not violate it,** and that answers a failure his design does not
anticipate: **re-inject the red-line sections after every compaction.** Compaction deletes the red
lines mid-run, in runs long enough for that to happen repeatedly. The implementation to copy is ~200
lines and depends on nothing: read the file, extract the named H2/H3 sections (fenced-code-block
aware), substitute the real date, bound at a byte cap with UTF-16-safe truncation, prepend with *"the
conversation summary above is a hint, NOT a substitute for your startup sequence"*, and **return null
on every failure path** so a missing or oversized file degrades to no injection rather than to an
error. That is not enforcement; it is making sure the file is actually read, which is all he asked
for.

### 16.9 Д12 is unratified

The stop verbs were the last thing said and the session ended before confirmation. They are
implemented as described. `NEXT-RUN.md` and the round-2 question list both carry the flag.

---

## 17. What this lens makes worse, what it drops, and the weakest point

### 17.1 What it makes worse

- **Judgement is late by design.** A deterministic loop can only wake the brain on a predicate
  someone wrote down in advance. A model watching continuously would notice things nobody predicted —
  and the owner's R1-09 explicitly delegates that noticing to the orchestrator. This design buys
  cheapness with foresight, and the sentinel's four-hourly question is a thin substitute.
- **Predicates are now a maintenance surface.** Twelve of them, each with a failure mode, each needing
  a scorecard to know whether it works. The previous generation had one (stale heartbeat) and it was
  wrong; this one has twelve, and some of them will be wrong in ways the scorecard is designed to
  surface rather than prevent.
- **Silence hides slow failure.** O1 means a run that is quietly producing nothing looks exactly like
  a run that is quietly producing everything, until he asks. The status command, the sentinel and the
  morning artifact are three separate attempts to compensate for a property the design deliberately
  chose.
- **More processes, more ways to be out of sync.** Six process kinds, a launchd agent, a lock, a
  lease, a journal, a ledger and a control file. Each one is simple; the set is not. The previous
  generation had fewer moving parts and lost nights to the ones it had.
- **Cheap models for watch duties cut both ways.** A cheap scout misreading a diff produces a
  confident wrong answer about whether a ticket's scope changed, and the orchestrator will act on it.
  The tiering means it is asked rarely, which reduces exposure without removing it.
- **The pacer cannot explain itself.** When a lane is not being dispatched, the reason is a
  conjunction of six conditions in bash. `--why <lane>` exists in the status command precisely because
  this is worse than a model that could just say.

### 17.2 What it drops

- **Continuous model supervision**, which is the only thing that catches the unanticipated. Dropped
  deliberately; the sentinel is the four-hourly residue.
- **Everything that types into a terminal**, except the opt-in interactive lane. That drops R1-11's
  hybrid mode on platforms where it was the only takeover path, and it makes a lane on Terminal.app
  undrivable rather than partially drivable.
- **Machine-resource awareness.** The owner deferred it explicitly (R1-05 [160]) — and the run that
  produced the field notes OOM-killed his own container. This design does not add it, and does not
  pretend the deferral is free.
- **In-place adaptation of a running lane on most platforms.** Where `send` cannot land mid-turn,
  `stop-soft` degrades to "at the next task boundary" and Д6's *live* answers become *next-boundary*
  answers.
- **Any attempt to protect his files in the shared checkout.** §16.7.
- **A run scope as a seventh config file.** Folded into `control.yaml` to keep his marketplace layout
  literally intact, at the cost of the run scope being a runtime object with different semantics from
  the six.

### 17.3 The single weakest point

**The decision predicates are the whole design, and they are unvalidated prose.**

Everything operable in this document — the token budget, the silence, the bounded loops, the wake
budget, the fact that a 34-hour night costs under a dollar to supervise — rests on the claim that
twelve deterministic predicates can decide *when a model needs to look*. If that claim is wrong, the
failure is not loud. It is a run that ticks 4,080 times, spends almost nothing, breaks no invariant,
raises no alarm, and produces nothing — and the owner finds out in the morning, which is exactly the
outcome the whole system exists to prevent.

The previous generation failed loudly and expensively: false stalls, nudge storms, 85-minute loops.
Those are cheap failures, because you can see them. This design's failure mode is **quiet**, and the
lens that produced it — minimise output, minimise tokens, minimise supervision — is the same lens that
makes a quiet failure hard to notice.

Three things partly cover it, and none of them closes it: the sentinel's four-hourly *"has this run
produced anything"*, which is the only judgement in the system not derived from a predicate;
`harvest_evidence: observed`, which refuses to call an empty lane done; and the detector scorecard in
`NEXT-RUN.md`, which makes a predicate that never fires visible **after** the run rather than during
it. A predicate that is subtly wrong for a whole night is caught by exactly one of those, four hours
late, by a model that gets three inputs and one question.

If one thing in this design deserves an adversarial pass before a line of it is written, it is the
predicate list in §2.2 — specifically, the question *what does this run look like when it is failing
and no predicate fires?*
