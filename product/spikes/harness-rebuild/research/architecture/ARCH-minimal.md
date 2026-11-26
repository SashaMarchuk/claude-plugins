# ARCH-minimal — the orchestrator designed through one lens: the simplest thing that can work

**Date:** 2026-09-19 · **Lens:** least mechanism that satisfies the requirements.
**Authority:** `round-1/ANALYSIS-01.md` is the source of truth for what the owner wants; item codes
(`R1-06`, `Д7`, `[171]`) are its codes and the transcript's row anchors.
**Evidence tags:** **VERIFIED** (read in source, or executed on this machine today) · **CLAIMED** (a
document asserts it and I did not run it) · **INFERRED** (my reasoning from verified parts).
**Defaults:** every value the owner did not state is marked **DEFAULT-PROPOSED** and says what it
protects against. Nothing marked that way is a decision; it is a proposal with a reason.

The lens is his, not mine. Four separate times, in four different items, he asked for the least
machinery that works: «тут нічого надприроднього не потрібно вигадувати» [171] · «це має бути дуже
простий процес» [189] · «це має бути надійна річ, дуже проста» [300] · «я не хочу якихось
детерміністського варіанту … він буде дуже складний оверінжиринг, але дуже якісь простий та надійний
варіант» [370]. `extract/outside-list.md` §12.1 records that only the last of the four reached the
analysis. This document treats all four as a binding constraint on the whole build.

---

## 0. The one idea, and what dies without each part

### 0.1 The split that makes everything else small

Every requirement in round 1 falls into exactly one of two kinds:

- **Bookkeeping** — claim a ticket, record what was started, read a number, notice a file changed,
  count to three, stop what you started, decide the queue is empty. Deterministic, cheap, and the
  place the previous generation failed hardest: a model wrote 26 refusal events that never happened
  (FIELD-NOTES §12.7, VERIFIED), a merge printed `Already up to date` and moved nothing (§4.1), an
  attention file was truncated every cycle (§2.1), a status command spends a model turn to read a
  JSON file that bash already wrote (`commands/status.md`, VERIFIED).
- **Judgement** — is this session making progress (R1-09), stop or wait on an orphan executor (Д10),
  does this ticket edit contradict finished work (Д9), may this question be answered (R1-11). The
  owner deliberately refused rules here: «Агент сам повинен це вирішувати» [231], «оркестратор, для
  цього є щоби вирішувати ці питання» [234/236], «він повинен вирішити» [497].

So: **one bash supervisor owns all state and does all bookkeeping; a model is invoked, one question
at a time, only when a tick has something no rule answers.** The supervisor never judges. The judge
never holds state. That single line removes the context-watcher session, the validator session, the
question session, the typing-into-terminals machinery, the heartbeat files, the nudge, the
`/compact`-into-a-tty procedure, and the entire problem of compacting the orchestrator — because
the orchestrator, as a long-lived model session, no longer exists.

### 0.2 Every component, and the requirement that dies without it

| Component | Lines, est. | The requirement that dies without it |
|---|---|---|
| `orch-lock.py` (18 lines, flock holder) | 18 | R1-10 [300]/[301] — «не може бути такого, що вже якісь існуючі оркестратор і спускається наступний … Це треба відслідковувати і **не дозволяти**». Without a real OS lock, the invariant is a heuristic. |
| `orch-run.sh` — the tick loop (the supervisor) | ~350 | Everything. It is the only resident process. |
| `orch-lane.sh` — one wrapper process per ticket | ~120 | R1-09 liveness, Д3 teardown, Д4 worktrees, R1-16 "stop only what you started". Without it, liveness is screen-scraping again. |
| `orch-judge.sh` — render fact sheet, one model call, parse one JSON verdict | ~80 | R1-09, Д9, Д10, R1-14 — every place he said the orchestrator decides. |
| `orch-ctl.sh` — write one entry into the control file | ~60 | Д12 stop verbs, Д7 mid-run override, R1-07 account reassignment. |
| `orch-status.sh` — print `status.json` | ~40 | Д11 [508] pull-only status, at zero model cost. |
| `orch-preflight.sh` | ~120 | R1-07 [199], R1-17 [395], R1-04 [153], Д4 [433] — "prove it works before the run starts", all in one place. |
| `orch-doctor.sh` | ~40 | R1-10 [246] the health check on a separate account, if the user configures one. Optional. |
| `adapters/<id>/*.sh` (6 scripts) | ~60 each | R1-06 part 4 / I1 — one platform's quirks never reach the core. |
| `capacity/<provider>.sh` | ~30 each | R1-06 [007]/[171] — the quota read, per provider, with its own shape. |
| `probe/<engine>.sh` | ~10 each | R1-03 [118] — drive GSD/superpowers/custom without owning it. |

Roughly **1,100 lines of bash, 18 lines of Python, no daemon besides the tick loop, no database, no
event bus, no framework, and one npm dependency only if the owner chooses it** (see §7.4). For
comparison: the previous generation is 1,879 lines of bash (VERIFIED, `wc -l plugins/harness/bin/*.sh`)
and does less.

### 0.3 What was deliberately not built

No tmux/AppleScript control, no `send`, no `key`, no nudge, no heartbeat file, no attention file, no
screen capture, no registry-of-sessions-by-tty, no second orchestrator, no context-watcher session,
no validator role, no council, no sandbox, no permission wrapper, no DAG, no YAML schema beyond an
array, no SQLite, no HTTP server, no webhooks. Each of those exists in the previous generation or in
the field; §15 says what is lost with each.

---

## 1. Processes — what exists and who starts them

**Four kinds of process. Only one is resident.**

1. **The supervisor.** One per project. Started by `/orchestrator:run`, which execs:
   `python3 orch-lock.py <lockfile> -- nohup bash orch-run.sh <run-dir>` under `caffeinate -i`.
   It holds an exclusive `flock` for its whole life and releases it by dying. It loops:
   `tick; sleep <interval>`. It spends **zero model tokens on a tick where nothing is open**.
   VERIFIED on this machine today: `flock(1)` is **not installed** (`command -v flock` → nothing);
   `/usr/bin/shlock` exists but is PID-based and PID-recyclable; `python3` 3.9.6 and `node` 22.18.0
   are present. The 18-line Python holder was written and executed here: it acquires the lock, writes
   `pid epoch argv` into the lock file, sets the fd inheritable, `execvp`s the real command, and a
   second attempt while the first holds prints `LOCK HELD: 7648 1789826089 sleep 5` and exits **69**.
   After the holder exits the next attempt acquires immediately — **no TTL, no stale-lock timeout, no
   heartbeat** (this is the property `deepseek-harness`'s `flock-contract.md` documents and
   `ADOPTION-VERDICT.md` §4 item 7 recommends taking as a rule rather than as code).

2. **A lane.** One process per claimed ticket, `orch-lane.sh`, started detached by the supervisor.
   It prepares the worktree, execs the platform command in its own foreground with stdin from
   `/dev/null` under an external wall-clock `timeout`, tees the platform's structured output to a
   file, and on exit writes `result.json` and tears down exactly what it recorded creating. It is a
   real process the supervisor started, whose pid and start time are on disk. **Liveness is this
   process, not a screen** — which retires FIELD-NOTES §1.3–§1.6, §2.2, §11.1, §12.1 as a class.

3. **The judge.** Not resident. A one-shot `-p` model invocation the supervisor makes at most once
   per tick, with a rendered fact sheet on stdin and a fixed JSON schema expected on stdout, under a
   timeout. It dies with the call. **There is no orchestrator session with a context window**, so
   R1-08's hardest case — compacting the orchestrator, which FIELD-NOTES §1.1 proves is impossible
   from inside and C5-A3/A5 prove is unresolvable against the single-orchestrator invariant — does
   not arise. §15 states what this costs.

4. **The doctor.** Optional, not resident, one-shot. A `launchd` `StartInterval` job (or `cron`) on a
   different account, running `orch-doctor.sh`. Its whole health check is: *try to take the lock*
   (§10.3).

Nothing else runs. In particular there is **no per-session daemon, no HTTP server, no file watcher**
— change detection is `stat` on a tick, which is the cheapest correct thing and is what the owner
himself guessed at [195] («Можливо, там, наприклад, по даті, перевіряти, коли він був змінний»;
`extract/corrections.md` correctly flags that ANALYSIS-01 hardened his hedge into a named mechanism —
here it is chosen on its own merits, and hardened by a content hash, see §2.4).

---

## 2. The control plane — exact paths, formats, protocol

### 2.1 Everything lives outside the work tree

**The single most consequential layout decision in this design.** Д4 [433] makes *every task in its
own worktree* the default. A git worktree is a separate checkout, so anything the run keeps inside
the repository forks per lane and the copies diverge. This is not theoretical: FIELD-NOTES §12.5
records `QUESTIONS.md` and `JOURNAL.md` forking into a worktree's own copy with a real owner-facing
question invisible for an hour (VERIFIED); C3-A2 measured 327 tracked ticket files, every status write
dirtying one, and FIELD-NOTES §4.1 records that one dirty tracked file is exactly what made a merge
print success and do nothing.

So: **run state lives under `$HOME`, never in the repository.** Only three human-facing artefacts live
in the project, and the orchestrator reads them from the **main checkout** (resolved with
`git rev-parse --git-common-dir`, VERIFIED here on git 2.33.0: from inside a worktree it returns the
main repo's `.git`, whose parent is the project root), never from a worktree copy.

```
~/.orchestrator/
  locks/<sha1(project-root)>.lock        # flock target. Keyed on the PROJECT, not the run (§10.4)
  runs/index.tsv                         # run-id \t project-root \t run-dir \t created_at \t state
  runs/<run-id>/
    config.resolved.json                 # snf slots 1–6 merged, snapshot at start
    config.run.json                      # run-scope overrides captured from --set
    config.sources.json                  # the six source paths + (mtime,size) at last read
    control.json                         # THE watched control file (Д12, Д7, R1-07)
    control.lock
    control.applied.ndjson               # every entry after it was applied, stamped
    journal.ndjson                       # append-only; one line per tick and per state change
    status.json                          # rewritten atomically each tick — the pull surface (Д11)
    decisions.ndjson                     # every judge verdict + the sha1 of the fact sheet it saw
    answers.ndjson                       # every answer the orchestrator gave a session (R1-11)
    owned.ndjson                         # resource ledger, append-only (Д3, R1-16)
    capacity/<account>.json              # cached capacity reading + read_at + provenance
    lanes/<lane-id>/                     # the directory IS the claim (§4)
      start.json  events.ndjson  events.norm.ndjson  sessions.ndjson
      stdout.log  stderr.log  result.json            # result.json is written LAST
    lanes.done/<lane-id>/
    report.md                            # written once, at finish
```

```
<project>/.orchestrator/RULES.md         # R1-15 red lines. Committed. Read from the MAIN checkout only
<project>/.orchestrator/tickets/*.md     # local registry, only when tickets.source = local
<project>/QUESTIONS.md  (or wherever)    # Д6 channel, path from config, may be anywhere
```

**`run-id`** = `<project-slug>-<YYYYMMDD-HHMMSS>Z`. **`lane-id`** = the ticket id, slugified
(`[a-z0-9-]`), because one ticket is one lane and reusing the id makes every path predictable.

### 2.2 `control.json` — the one file the tick reads

The owner named exactly one such file [195]/[520] and this design adds no second one (the Д6
questions channel is his second, and it is his to place). Format:

```json
{
  "version": 1,
  "entries": [
    { "id": "c-0007", "at": "2026-09-19T23:40:11Z", "by": "orchestrator:stop-soft",
      "verb": "stop", "scope": "run", "apply": "boundary" },
    { "id": "c-0008", "at": "2026-09-19T23:41:02Z", "by": "hand",
      "verb": "set", "scope": "run", "apply": "boundary",
      "key": "accounts.executor", "value": "<profile-B>" }
  ]
}
```

- **`verb`** ∈ `stop | pause | resume | set | custom`.
- **`scope`** ∈ `run | lane:<lane-id> | ticket:<ticket-id>`.
- **`apply`** ∈ `now | boundary | custom`.

**The soft/hard collision is removed here, deliberately.** C4-A10 and C5-A7 show that the owner used
«хард»/«софт» in three items with three granularities and two opposite post-conditions — `[171]`
stop-the-task-and-the-run-stops, `[195]` apply-a-change-now, `[204]` interrupt-and-continue — and that
he wants one file to carry all of them. A single field named `hard` in that file is unimplementable
without guessing which meaning he wrote. So the file carries `verb` + `scope` + `apply` as three
orthogonal fields, and **his command names are preserved unchanged**: `stop-hard` writes
`{stop, run, now}`, `stop-soft` writes `{stop, run, boundary}`. The vocabulary he speaks is the CLI;
the file is explicit. This is recorded as a tension in §14.

**Write protocol** (every writer, including `orch-ctl.sh` and the owner's own editor via the command):
take `orch-lock.py control.lock`, re-read the file under the lock, append the entry, write a sibling
temp file in the same directory, `rename()` over the destination, release. A reader is never blocked
and never sees half a file. (This is `dsh`'s `settings-file` protocol, which `ADOPTION-VERDICT.md` §4
item 9 recommends taking as a design; it is four lines of bash here.)

**Read protocol:** each tick, `stat` the file; if `(mtime,size)` changed, read and parse it.
- Parse failure → **keep the last good entries, apply nothing new, set `status.json.control_error`**
  with the parse error and the file's mtime. It never takes the run down. (`dsh`: *boot fails loud,
  reload keeps last good*.)
- Every entry applied is appended to `control.applied.ndjson` with `applied_at` and removed from
  `control.json`'s `entries`. **An entry is applied exactly once**, by id. This is what stops the
  re-fire class that produced the 85-minute loop (FIELD-NOTES §11.6, VERIFIED) and that C5-A10
  identifies as making a session permanently uncompactable.

### 2.3 `status.json` — what the owner reads, and what it cannot say

Rewritten every tick by bash + jq, atomically. It contains **only facts the supervisor can prove**:

```json
{ "run_id":"<work-project>-20260919-224100Z", "project":"/Users/…/<work-project>",
  "supervisor":{"pid":40311,"started_at":"…","ticks":812,"last_tick":"…","interval_s":60},
  "mode":"controlled", "phase":"running",
  "lanes":[{"id":"t-118","ticket":"118","state":"working","pid":40977,"pid_started":"…",
            "platform":"claude","account":"<profile-B>","worktree":"…",
            "events_last_grew":"2026-09-20T02:14:03Z","context":{"pct":41,"prov":"measured","age_s":22},
            "engine":{"state":"running","detail":"phase 12 plan 3","age_s":22}}],
  "queue":{"ready":6,"blocked_by_deps":2,"blocked_on_human":1,"done_this_run":13},
  "capacity":[{"account":"<profile-B>","kind":"window","bucket":"seven_day","used_pct":62,
               "reset_at":"…","read_at":"…","age_s":430,"prov":"measured"}],
  "blocked_on":[], "control_error":null, "board_sync":"ok",
  "completion_oracle":"engine_probe:gsd", "last_judge":{"at":"…","verdict":"wait","lane":"t-118"} }
```

There is **no `healthy` field**. C9-A4 shows precisely why: the previous generation computed
`healthy=false` from an attention file that its own watch loop truncated every cycle, so it would
have printed `healthy: true` for all 85 minutes of the loop in which `NO ONE IS BEING TOLD` was
written to the log (VERIFIED). A status surface that cannot express health cannot lie about it;
`blocked_on` is a list of named facts, and the owner reads the list.

Every number carries `age_s` and `prov` (`measured | estimated | unknown`). `missing ≠ zero` — an
absent capacity reading is `kind:"unknown"` with a reason, never `used_pct: 0`
(`agent-deck`'s rule, *"a wrong token number is worse than no token number"*, LANDSCAPE §4).

### 2.4 Change detection, and not firing on your own writes

Every watched surface — `control.json`, the six config files, `RULES.md`, the Д6 questions file, and
a ticket body — is checked by `(mtime, size)` first (one `stat`, free) and only then by `sha1` of the
content. **The supervisor records the sha1 of anything it writes**, and a change whose hash it
produced is ignored. This is the one-line fix for C3-A1, where the orchestrator's own status comment
[149] fires its own change detector [466] and Д9 then reacts to it, forever — the same topology as
the 85-minute loop. (`dsh` calls this *self-write suppression by content*.)

---

## 3. State machines

### 3.1 The run

```
                 preflight FAIL ──► refused (exit 70, nothing created)
  starting ──► running ──► draining ──► finishing ──► finished
      │           │  ▲         │             │
      │           │  └─paused──┘             └──► stopped   (control stop / doctor)
      │           └─────────────► stopped
      └───────────► refused (lock held, exit 69)
```

| State | Entered when | Tick does | Leaves when |
|---|---|---|---|
| `starting` | `/orchestrator:run` acquires the lock | preflight (§11.1); write run dir; register in `index.tsv` | preflight passes → `running`; fails → `refused` |
| `running` | — | full tick (§3.3) | control `{stop,boundary}` or quota soft threshold → `draining`; `{stop,now}` → `stopped`; no claimable work and no live lanes → `draining` |
| `paused` | quota window exhausted, or control `{pause}` | reap + observe only; **dispatch nothing**; recheck the wake condition | `resume_at` reached, or control `{resume}` → `running` |
| `draining` | soft stop, or work exhausted | reap + observe; dispatch nothing | all lanes ended → `finishing` |
| `finishing` | — | teardown from `owned.ndjson` (§12); write `report.md`; deregister | teardown reported → `finished` |
| `stopped` | hard stop | teardown, same path as `finishing`, but lanes were killed rather than ended | — |
| `refused` | lock held, or preflight failed | nothing was created | — |

`paused` and `draining` are the only two non-obvious ones and both come straight from R1-06 [171]:
hard = stop the task now (→ `stopped`), soft = let the current task finish and start nothing new
(→ `draining`), and the intermediate "save state, close the session, resume later" is `paused` +
per-lane `reseed` (§6.3) — the variant the owner explicitly left **OPEN** [171] («Не знаю»), here
given the minimum shape that makes the other two implementable, and flagged in §14.

### 3.2 A lane

```
  claimed ──► preparing ──► working ──┬──► done
      │           │            │      ├──► failed
      │           │            ├──────┼──► blocked_on_human
      │           │            ├─reseeding─┘ (back to working, new session id)
      │           └──► failed (setup)
      └──► released (claim withdrawn before launch)
```

| State | Marker on disk | Transition out |
|---|---|---|
| `claimed` | `lanes/<id>/` exists, no `start.json` | `start.json` written → `preparing`; abandoned → `released` (dir removed) |
| `preparing` | `start.json` exists, no pid recorded | worktree + env verified → `working`; any setup step fails → `failed` (exit 70) |
| `working` | `start.json.pid` alive **and** `ps -o lstart= -p <pid>` equals `start.json.pid_started` | see below |
| `blocked_on_human` | last normalized event is `waiting_on_human`, or the lane exited 5 | an answer appears in the Д6 channel → back to `working` via reseed, or the ticket is released |
| `reseeding` | a new line in `sessions.ndjson`, predecessor `result.json` says `stopped_for:"reseed"` | successor launched → `working` |
| `done` / `failed` | `result.json` written, dir moved to `lanes.done/` | terminal |

**Outcome is never decided by the exit code alone.** ADAPTER-CONTRACT §2.4 invariant 1 records four
platforms that exit 0 on failure (Aider on auth failure and rate limit; pi `--mode json` on provider
failure; GLM on quota exhaustion *with* `subtype:"success"`; MiMoCode always) — VERIFIED in those
spikes. So the wrapper computes: `outcome = f(exit_code, terminal_event_in_events.norm.ndjson)`.
If the two disagree, outcome is `unknown`, the lane goes to `failed` with `reason:"contradictory"`,
and the fact is on the judge's next fact sheet. Silence is never success.

### 3.3 One tick, in order

Cheap and deterministic first; the model last and only if something is still open.

1. **control** — `stat`; if changed, parse, apply matching `apply:now` entries, queue `boundary` ones.
2. **config** — `stat` the six slot files (§8); if changed, re-resolve and diff; apply
   boundary-safe keys, report the rest.
3. **reap** — for each lane: pid alive? start time matches? `result.json` present? Update state.
4. **observe** (zero tokens) — per live lane: event-file size and mtime; tail the last `N` normalized
   events; read `context.pct` from the last event that carries one; run the engine probe (§6.2).
5. **rules** — anything with a configured answer, applied without a model: quota threshold crossed,
   context threshold crossed, three identical failures (Д5), a `blocked_on_human` lane whose answer
   has arrived, a finished lane to release.
6. **judge** — if and only if something is still open, render **one** fact sheet with **all** open
   items and make **one** model call (§5.4). Otherwise skip entirely.
7. **dispatch** — while `live_lanes < concurrency` and capacity allows and a ready ticket exists:
   claim, launch.
8. **write** — append to `journal.ndjson`; rewrite `status.json`.
9. **terminal check** — §12.1.

DEFAULT-PROPOSED `tick.interval_seconds: 60`. It protects against two things at once: a tick cheap
enough to run all night with no model in it (the previous generation's watch ran at 60 s and its
context watch at 120 s — FIELD-NOTES §0, §3.2, VERIFIED), and a worst-case latency of one minute
between the owner typing `stop-hard` and anything happening, which the command prints out loud.

---

## 4. Claiming and releasing work

**The claim is `mkdir`.** `mkdir lanes/<lane-id>` is atomic on POSIX and succeeds exactly once. There
is no lock file, no read-then-write, no compare-and-swap, and no ticket-id allocator. C3's research
measured the read-then-write shape at **27 winners out of 50**, and FIELD-NOTES §10.2 (`J-T169-01`)
records two concurrent adds producing two files under one id in **five rounds out of five** — both
VERIFIED. `mkdir` is one syscall and cannot do that.

Order, and it is the whole recovery story:

1. `mkdir lanes/<id>` — the claim. Fails → someone has it, move on.
2. write `start.json` — **before the platform is launched**. Carries `ticket`, `ticket_sha1`,
   `platform`, `account`, `worktree`, `base_sha`, `compose_project`, `session_id` (when the platform
   lets the client name it), `cmd`, `started_at`. ADAPTER-CONTRACT §3 B records the crash window on
   platforms where the server mints the id; `sessions.ndjson` is appended the moment an id is known.
3. launch; append every created resource to `owned.ndjson` as it is created.
4. on exit, write `result.json` — **last**. Then `mv lanes/<id> lanes.done/<id>`.

A crash therefore leaves a **detectable orphan** — a lane dir with `start.json` and no `result.json`
— rather than a false claim of completion. (*Append `start` first, `end` last*: `dsh`'s compaction
doc, recommended verbatim by `ADOPTION-VERDICT.md` §4 item 8 as the fix for the whole
"reported success and did nothing" class: FIELD-NOTES §4.1, §11.4, §12.7.)

**The board is a mirror, not the source of truth.** The local claim is authoritative; the board write
follows and is allowed to fail. C3-A9 shows the alternative failing at 03:00 on a read-scoped token,
with three lanes' real work invisible and a second run re-claiming it. Here a board write failure
sets `status.json.board_sync:"degraded"`, notifies once, and changes nothing about execution. This
inverts the owner's framing of the board as the orchestrator's working surface [149] — recorded in
§14.

**The orchestrator never writes into a work item's own body.** On the local registry, status lives in
the run dir and the ticket file is read-only; on a remote board, status transitions and comments are
API writes that touch no file. This one rule removes C3-A1 (the tool's own log inside the description
firing the change detector), C3-A10 (no defined body region; the readiness grep reading the tool's
own echo) and C3-A2's 327 dirty tracked files — at the cost of the local registry no longer being a
"working surface" (§14).

**Readiness** — the structure he asked someone to design [145]/[146], at grep size:

> A ticket is ready iff (a) its state is the configured ready state — frontmatter `status: ready`
> locally, or the configured label/status on a board — **and** (b) its body, with frontmatter
> stripped, contains every heading in `tickets.ready_requires` **and** (c) every id in its
> `depends_on:` list is done.

DEFAULT-PROPOSED `tickets.ready_requires: ["Outcome", "Acceptance", "Scope"]` — the previous
generation's three headings (VERIFIED, `harness-tickets.sh:29-36`), which C3's research measured
holding across **327 tickets, 288 done, 15 of 15 ready tickets passing, zero violations**. It protects
against a one-line ticket eating four hours of a night (C3-A6's worked case).

`Д2` (work added mid-run) needs no mechanism at all: the dispatch step re-reads the queue every tick,
so a ticket that becomes ready is picked up on the next tick. DEFAULT-PROPOSED
`tickets.max_claims_per_run: 0` (unbounded, his behaviour) **and** `tickets.notify_on_queue_growth:
50` — one notification when the ready queue grows by 50 during a run, because the only recorded
instance of this is FIELD-NOTES §10.1, where the queue went 236 → 327 in a day and a human had to set
a soft pause by hand (C3-A5). A notification is not a brake; it is the signal he acted on last time.

---

## 5. Quota, context and liveness

### 5.1 Quota — three shapes, one type

`capacity/<provider>.sh <account>` prints exactly one line and exits 0:

```
kind=window  bucket=seven_day used_pct=62 reset_epoch=1789923599 prov=measured
kind=credit  remaining=41.20 unit=USD prov=measured
kind=unknown reason=http_429
```

`Capacity = Window | Credit | Unknown` is a first-class type with a policy per variant, because
ADAPTER-CONTRACT §3 E and §6.1 establish that three incompatible models coexist and that "wait for
the reset" **waits forever** on a credit platform — the owner's own [007] admits it
(«можливо це буде взагалі pay-as-you-go»), and C4-A4 shows that all three of his stop modes are
expressed in a percentage that does not exist there.

| Variant | Policy | Default |
|---|---|---|
| `Window` | `soft_pct` → `draining`; `hard_pct` → `stopped`; exhausted → `paused` until `reset_epoch + margin`, then auto-resume | DEFAULT-PROPOSED `soft_pct: 80`, `hard_pct: 95`, `margin_s: 90` |
| `Credit` | a spend ceiling per run; on breach → `draining`, notify, **no auto-resume** (there is nothing to wait for) | DEFAULT-PROPOSED `ceiling: null` = **refuse to dispatch to a credit lane until a ceiling is set** |
| `Unknown` | `on_unknown` | DEFAULT-PROPOSED `hold_dispatch` |

Three defaults need their reasons said out loud:

- **`soft_pct: 80`** is his own worked number [171] («хардстопи … 80% тижневого»), and `hard_pct: 95`
  sits above it because he used 80 as an example for *both* soft and hard in the same breath (C4-A2),
  which cannot both hold. Thresholds are **per account, per named bucket** — never per run — because
  C4-A2 shows "80% of the weekly" has no referent once roles sit on different accounts.
- **`on_unknown: hold_dispatch`** (finish what is running, start nothing new, notify once) is the
  deliberate inversion of the shipped `"on_unreadable": "proceed"` (VERIFIED,
  `templates/user-config.example.json`), which C4-A6 and FIELD-NOTES §11.7 show made the entire limiter
  inert for days while reporting nothing wrong. It protects against spending a weekly window blind.
  Its cost is real: a flaky endpoint idles the machine. Mitigation:
  DEFAULT-PROPOSED `capacity.unknown_grace_minutes: 30`, after which it notifies rather than sitting
  silent.
- **`capacity.cache_seconds: 900`, one read per account per tick maximum, and only for accounts a
  live-or-about-to-launch lane uses.** C4-A3 is a VERIFIED measurement: a *single* well-formed call to
  the Anthropic OAuth usage endpoint returned `rate_limit_error` because another process on this
  machine had polled a minute earlier, and the owner's own global `CLAUDE.md` instructs *every*
  Claude Code session to poll that endpoint. The cache protects the reader from the run's own fleet.

A threshold naming a bucket the provider stopped reporting is a **configuration error**, surfaced in
preflight and again on the first tick that cannot find it — never a silent no-op. C4-A5 is the
VERIFIED case: across 7,379 Codex `rate_limits` records on this machine, `primary` is the 5-hour
window in 471 records and the weekly window in 1,098 within the same plan, and on his current
`prolite` plan the 5-hour window is absent from **3,030 of 3,030** records. A threshold on a bucket
that no longer exists must be loud, because it is indistinguishable from a bucket at 0 %.

**The meter must measure what the lane spends.** `start.json` records `(platform, base_url, account)`
and the capacity reader is chosen by that triple, not by the binary's name. C4-A11 is VERIFIED twice
on this machine: the canonical keychain entry matches none of the profile switcher's profiles, and
`~/.config/claude-mimo/env` points `ANTHROPIC_BASE_URL` at a MiMo host while the previous
generation's `token()` never consults it — so the gate meters an account the session never touches.
Preflight prints the triple per lane so the owner sees it before the night starts.

**Unasked, and left unasked.** `questions.md` R1-06 contained «Чи можна витрачати ліміт до нуля, чи
треба лишати запас на твою власну роботу?» and the interviewer dropped it
(`extract/corrections.md` §F, `meta.md` G3 — VERIFIED). DEFAULT-PROPOSED `capacity.reserve_pct: 0`,
**and preflight prints one line naming this as an open question with the exact wording to put to
him.** I will not invent a reserve for an account he also works in.

### 5.2 Context — measured from the stream, never from a screen

The lane's normalized event stream carries `context.used_pct` where the platform emits it (Claude
Code's `-p --output-format stream-json --verbose`, Codex, Kimi, Copilot, Droid, Qwen, MiMoCode, pi —
ADAPTER-CONTRACT Table 1 axis D, marked native for each). The supervisor reads it from
`events.norm.ndjson`. No status line, no screen capture, no `/context` call, no token spend.

Two consequences from C5, both accepted rather than argued with:

- **C5-A2 (VERIFIED):** two different percentages exist on his machine, ~13 points apart — his GSD
  status line normalises away the auto-compact buffer (`gsd-statusline.js`, its own comment names
  *"inflates the context monitor warning messages by ~13 points (#2451)"*). So the config key is
  named for what it measures: `context.raw_pct_threshold`, the platform's own raw number, and
  `status.json` prints both the raw number and the platform's auto-compact reserve so the owner can
  see which one he is setting. DEFAULT-PROPOSED `context.raw_pct_threshold: 75`, chosen below every
  platform auto-compact reserve observed so that the orchestrator acts first rather than being
  pre-empted.
- **C5-A11 (VERIFIED):** refill rates differ by an order of magnitude across roles — 8 %/h for the
  watch, 26 %/h for a worker, 2 %/h for the orchestrator. So the threshold is per **role**
  (`roles.<role>.context.raw_pct_threshold`), which is exactly the shape his own [204] describes
  («для кожного з них можу вказати, який буде поріг компакту»), and `status.json` prints
  `Δpct/hour` per lane so the number is tunable from evidence rather than guessed.

### 5.3 Compaction — two mechanisms, one of which always works

- **Soft** — a threshold set on the platform **at launch** (`--autocompact`, `compressionThreshold`,
  `thresholdRatio`). Cheap, no intervention, and it is the *only* thing available on Amp, Gemini CLI,
  Cursor and `dsh`, where ADAPTER-CONTRACT §3 D records no external trigger exists at all.
- **Hard — close-and-reseed, and it is the universal path.** Stop the lane at `apply:now`; write
  `handoff.md` from the lane's own last normalized events plus the ticket body plus `RULES.md`;
  launch a successor on the same ticket with the handoff prepended; append the new session to
  `sessions.ndjson`. Ticket → session is a **lineage, not a field**.

`compact.sh` in an adapter may implement a native external compaction where one exists; when it is
absent, reseed is used. Either way the **proof is structural**: after a reseed there is a new line in
`sessions.ndjson` and a predecessor `result.json` with `stopped_for:"reseed"`. There is no
"did the percentage drop" check anywhere, because C5-A10 shows that check is known to return false
negatives *during* the very operation it verifies (`gsd-context-monitor.js`'s own watermark comment,
VERIFIED) and that three false negatives in a row trip Claude Code's `failure_breaker_open` and make
the session permanently uncompactable.

R1-08's strongest words — «повинен бути механізм, який гарантовано робить цю дію» [204] — are
satisfied **only by reseed**, and §14 says so plainly.

### 5.4 Liveness, and the fact sheet

Three signals, all free, all from processes and files the supervisor owns:

1. **Process identity.** `kill -0 <pid>` **and** `ps -o lstart= -p <pid>` matching `start.json`.
   Two checks, because a pid alone is recyclable — OpenClaw's `gateway-lock.ts` names exactly this
   trap (*"process start identity catches PID recycling even when the replacement process has the same
   argv shape"*, CLAIMED, recommended by `ADOPTION-VERDICT.md` §4 item 4).
2. **Event-file growth.** `events.ndjson` size at this tick versus the last. It moves **during** a
   turn, which is the specific thing a heartbeat cannot do: FIELD-NOTES §1.5 records that a session
   heartbeats *between* turns, that a validator running a 14-minute suite does not heartbeat at all,
   and that the watch therefore nudged six healthy sessions (33 nudges in the run, §12.3).
3. **The engine probe** (§6.2) — one line, zero tokens.

**Silence** is defined as: alive, event file has not grown for `silence_minutes`, and the last
normalized event is not `waiting_on_human`. DEFAULT-PROPOSED `silence_minutes: 20` — the previous
`run.stall_minutes` (VERIFIED) — with the difference that **nothing is nudged.** A silent lane
becomes an item on the judge's fact sheet.

**The fact sheet** is a rendered block of about forty lines, per open item, containing only facts with
provenance:

```
ITEM lane-silent  lane=t-118 ticket=118
  process: alive pid=40977 start=Fri Sep 19 22:41:03 2026 (matches)
  events:  last grew 00:24:11 ago; 1,412 events; last 5 normalized:
           tool_call(Bash) ×4 "echo idle"   turn_started   tool_call(Bash) "echo idle"
  context: 41% raw (measured, 22s old); +26 pct/hour over the last 3 ticks
  engine:  state=running detail="phase 12 plan 3" (22s old, gsd probe)
  history: 0 prior reseeds; 0 prior failures on this ticket; claimed 02:11 ago
  rules consulted: liveness.silence(20m) matched; no configured rule resolves this
  allowed verdicts: wait | reseed | stop | escalate
```

One model call per tick at most, all open items batched, and it is skipped entirely on a tick where
nothing is open — which is most ticks. Output is one JSON object per item:
`{"item":"lane-silent","lane":"t-118","verdict":"wait","reason":"…","confidence_not_used":true}`.
An unparseable or timed-out response is `defer` — do nothing this tick. **Waiting is the fail-safe
everywhere**, because C6-A4 shows the alternative building a loop for itself: a validator restarted at
minute 12 of a 14-minute suite stalls again at minute 12, and FIELD-NOTES §11.6 establishes that
nothing internal breaks such a loop.

DEFAULT-PROPOSED `judge.model` = the `watcher` role pin (his cheap-model instinct, Д8 [466]);
`judge.timeout_s: 120`; `judge.max_calls_per_tick: 1`; `judge.max_calls_per_hour: 30` — a hard
ceiling so that a judge in a disagreement loop cannot spend the night, which is Д11's
«мінімальну кількість аутпуту і **стокінгів**» [512] made mechanical.

---

## 6. Driving an engine without owning it

### 6.1 Two kinds of process, and no mixing

`process.kind` ∈ `engine | steps`. Setting both is a config error refused at preflight. That is
R1-03's «комбінувати ні, тут або або» [118] as a one-line check.

```json
"process": {
  "kind": "engine",
  "engine": {
    "id": "gsd",
    "start": "claude -p --verbose --output-format stream-json --session-id {{session_id}} '/gsd:execute-phase {{ticket.ref}}'",
    "probe": "probe/gsd.sh {{worktree}}"
  }
}
```

```json
"process": {
  "kind": "steps",
  "steps": [
    {"name":"plan",   "cmd":"claude -p … '/my-plan {{ticket.ref}}'"},
    {"name":"build",  "cmd":"claude -p … '/my-build'"},
    {"name":"check",  "cmd":"npm test", "on_fail":"Tests failed. Fix them before proceeding."}
  ]
}
```

A `steps` process is an **ordered array of commands**, run in order by the lane wrapper, stopping at
the first non-zero exit. No DAG, no conditionals, no expression language. That is the whole of
«які дії будуть, за якими, коли перевірка, **чи буде перевірка**» [118] — a check is a step, and a
process with no check is an array with no check, which he explicitly wants to be legal. `on_fail` is
the sentence handed back to the agent, borrowed from Ralph Orchestrator's `backpressure.gates`
(LANDSCAPE §4) because it makes "independent verification" a config file rather than a second agent.

### 6.2 The probe — the completion oracle, named out loud

C9-A1 is a blocker in the requirements, not in the implementation: R1-13 [344] gives verification to
the process, R1-03 [118] makes "no verification at all" a legal process, and **nothing anywhere says
how the orchestrator learns that work finished** as distinct from the session ending.

The minimum that closes it without imposing a check: a `probe` command that prints **one line** and
exits 0.

```
state=running  detail=phase 12 plan 3
state=blocked  detail=awaiting user approval
state=done     detail=phase 12 verified
state=failed   detail=plan 3 rejected
```

`probe/gsd.sh` is about five lines. VERIFIED on this machine today against the real `<work-project>`
project: `node ~/.claude/gsd-core/bin/gsd-tools.cjs state --project-dir <p>` exits 0 and prints JSON
whose `state_raw` carries `status:`, `current_phase:`, `current_plan:`, `stopped_at:`, `last_updated:`
and `state_head:` (a git SHA). Zero model tokens, no side effects, and it is GSD's own record — which
is exactly R1-06 part 3's rule: reference the chosen process's accounting, keep your own only where
there is none [171]/[189].

When there is no probe, the completion oracle is the lane process exiting, and **`status.json` says
so**: `"completion_oracle": "process_exit"`. The owner sees which one he got. That is the honest
answer to a gap he created deliberately, and it adds no check of the orchestrator's own — C7-A2 and
C9-A1 both show that a silent default here is how a design discussion gets merged as an
implementation.

One warning that belongs in the GSD probe's own file (VERIFIED in C9-A2): under a host-created
worktree GSD returns `dispatch-isolation: harness-worktree` and runs no git of its own, and
`worktree base-check` on a real project returns `{"shouldDegrade": true, "reason":
"head-diverged-from-fork"}`. So a lane whose worktree is cut from a base GSD does not expect will
either silently serialise or fork its sub-worktrees from `origin/HEAD`. The probe prints that
condition as `detail=`, preflight refuses to start a GSD lane whose `base_ref` disagrees with GSD's,
and §14 records that Д4's «з цим треба поєднювати» is a task he assigned, not a decision he made.

---

## 7. How a platform adapter plugs in

### 7.1 An adapter is a directory of six small scripts

No interface, no registry, no language. `adapters/<id>/`:

| Script | Input | Output | Contract |
|---|---|---|---|
| `caps.sh` | — | `compact=native\|none quota=window\|credit\|none answer=native\|none attach=yes\|no id=client\|server` | Static. No network, no tokens. Never claims `native` for something whose only implementation is a regex over English prose. |
| `preflight.sh` | `<account>` | `ok version=<v> account=<identity>` | Must prove **which account** a spawn would use. Read-only, ≤10 s, zero tokens. Exit 70 on failure. |
| `launch.sh` | `<lane-dir>` | execs the CLI in the foreground; stdout is the platform's structured stream | stdin from `/dev/null`; model pinned; version pinned; auto-update disabled. |
| `normalize.sh` | ndjson on stdin | one JSON per line | Maps to the fixed vocabulary: `turn_started, tool_call, waiting_on_human, context, compacted, turn_completed, failed`. |
| `capacity.sh` | `<account>` | the one line of §5.1 | Cached by the supervisor; never called per session. |
| `compact.sh` | `<lane-dir>` | exit 0 with proof, or exit 3 `unsupported` | Optional. Absent ⇒ reseed. |

That is the whole extension point. The core never contains a platform's name; a new platform is a new
directory, and a user's own platform is a directory they write. It also satisfies the owner's own
extension instinct at [312] («людина це може налаштовувати, може написати свої власні скіли»).

### 7.2 Preflight refuses what caps forbid

If a lane's configured requirement needs a capability `caps.sh` says is absent, **preflight fails
loudly with the exact sentence**, before the run starts — it does not degrade at 03:00.
ADAPTER-CONTRACT §2.0 states the reason precisely: *"an adapter that reports `native` and then
degrades at 03:00 is the single worst failure this contract exists to prevent."* Concretely:
`context.mode: hard` on a platform with `compact=none` is refused unless `context.fallback: reseed`
is set; `questions.answer: always` on `answer=none` is refused; a `Window` threshold on `quota=none`
is refused.

### 7.3 Provider is not platform

`Lane = Platform × Provider × Account × Role`, from ADAPTER-CONTRACT §0. A provider is
`{base_url, auth_env_ref, model, small_model, context_window, capacity_kind}` and is applied as
**environment only** at launch. GLM, DeepSeek, Kimi-as-endpoint and MiMo-as-endpoint are provider
rows behind an existing platform adapter, not adapters — which is the highest value-per-hour move in
the whole scan and is *a configuration change, not a feature* (ADAPTER-CONTRACT §5.3).

### 7.4 acpx is a value, not the architecture

`ADOPTION-VERDICT.md` §5 Change 1 recommends adopting `acpx@0.17.0` pinned as the session layer.
Under this lens it is **one legal value of `launch.sh`'s command**, not a structural dependency:
`adapters/acpx-claude/` is a directory whose `launch.sh` calls `acpx` and whose exit codes map
straight onto the wrapper's outcome table (`3` → timeout, `5` → `blocked_on_human`, `130` →
interrupted). This keeps the recommendation available and keeps a project with **40 `### Breaking`
sections in 44 releases** off the critical path. Its exit-5 refusal is a *feature* here: it converts
a question into a terminal outcome the wrapper records, which is exactly the state this design wants.

---

## 8. Configuration across his three scopes, and mid-run change

### 8.1 Obey snf, and say where it does not reach

Д1 [416] defers this wholesale to his own marketplace, and `<baseline-marketplace>` answers it:
six slots, two binding levels plus an advisory one, deep-merge except `use`, `never` accumulating,
**personal beats committed**, resolution is mandatory on every invocation, and the resolver never
writes (`docs/config-levels.md`, `requirements/OWNER-DECISIONS.md` 3.3, 4.10, 4.15, 5.1 — VERIFIED).
Plugin name `orchestrator`, so the per-plugin files are `<root>/shared/plugins/orchestrator.json`,
`./.claude/shared/plugins/orchestrator.json`, and their `.local` counterparts.

`recommended.json` ships the connector catalogue (board, notification channel, questions channel) and
**supplies no value to any resolved config** (OWNER-DECISIONS 3.8). Nothing in this design reads it at
run time.

**Where snf does not reach: the run scope.** He requires three scopes including *this run*
[331]/[075]; snf states that its three levels are the whole set (OWNER-DECISIONS 3.6). The minimal
reconciliation, and it changes nothing in snf: **the run scope is not configuration.** It is
per-invocation state — `--set key=value` arguments captured into `run/config.run.json`, layered on
top of the resolver's output by the orchestrator itself, never written to any config file, and gone
when the run ends. Recorded as a tension in §14.

### 8.2 Mid-run pickup, cheaply

Each tick, `stat` the six source files plus `config.run.json` (seven `stat` calls, no resolver run,
no model). On a change: re-resolve, diff against `config.resolved.json`, and split the diff three
ways.

| Class | Examples | When it applies |
|---|---|---|
| **Live** | `concurrency`, thresholds, `judge.*`, `notify.*`, `when_only_blocked`, `questions.*` | next tick |
| **Boundary** | `roles.*.account`, `roles.*.model`, `process.*`, `context.*`, `red_lines.*` | next lane launch; a live lane keeps what it booted with |
| **Frozen** | `project root`, `process.kind`, `tickets.source`, run id | **reported, never applied**; the run must end first |

The Boundary row is not a design preference, it is a platform fact: ADAPTER-CONTRACT §3 F records
that **changing a running session's account is impossible on all fifteen platforms**, and FIELD-NOTES
§8 records the same thing measured — *"A session already booted keeps the account it booted with; the
change reaches the next spawn."* An `apply:now` account change is therefore a **stop + relaunch +
reseed**, which pays for the context a second time; the command says so before it writes the entry.

The Frozen row is the one piece of machinery borrowed from Sortie, which is the only project in the
field with a documented list of keys that deliberately do *not* rebuild on reload (LANDSCAPE §3C) —
and the alternative is worse: a live rebuild of the run's identity mid-night.

Д7's live override [455]/[458] is Live by construction: it is one key, read every tick, and it beats
both the run's initial choice and the stored default because `config.run.json` is only consulted
where the control file has not set the key.

---

## 9. Stops

Three commands, exactly as he named them [520]/[524]. Each writes **one entry** into `control.json`
and exits. **None of them signals a process**, which is the whole point of his mechanism: the file is
the actuation channel and the tick is the clock.

| Command | Entry written | Effect | Applied within |
|---|---|---|---|
| `orchestrator:stop-hard` | `{stop, run, now}` | Each lane wrapper gets `SIGTERM`; its trap tears down what `owned.ndjson` lists for it, writes `result.json` with `stopped_by:"control"`; then the run tears down and the supervisor exits, releasing the lock | one tick |
| `orchestrator:stop-soft` | `{stop, run, boundary}` | `running` → `draining`. Dispatch stops. Lanes run to completion | one tick |
| `orchestrator:stop-custom <ref>` | `{custom, run, custom, ref}` | §9.1 | one tick |

Each command prints, on success: `written to control.json (c-0012); applied within 60s`. That is the
latency promise made explicit, because Д6 [449] records that what he wants to feel is *"це скоро
потрапить в оркестратор"* — an acknowledgement, not a guarantee of instantaneity.

**The supervisor is exempt from its own stop until teardown completes.** Gas Town's ESTOP carve-out —
*"The Mayor is exempt from E-stop so it can coordinate recovery"* (LANDSCAPE §4, `ADOPTION-VERDICT.md`
§4 item 13) — is the one line that keeps a hard stop from orphaning everything it was supposed to
clean.

### 9.1 `stop-custom`, which he defined as user-written text **or commands**

«Там можуть бути текстописні правила чи команди» [524]. Two execution models under one name, so:

- If `ref` resolves to an **executable file**, run it with the run dir as cwd, `ORCH_RUN` exported,
  under `custom.timeout_s` (DEFAULT-PROPOSED 120). Its exit code and output are journalled. It may
  itself write control entries — that is how a user composes a custom stop from the vocabulary.
- If `ref` resolves to **text**, the supervisor hands it to the judge with the current fact sheet and
  one instruction: *translate this into zero or more control entries from the allowed vocabulary;
  anything you cannot translate, report and do nothing about.* Untranslatable text produces a journal
  line, a notification and **no action** — never a guess.

This is the minimum for a verb whose meaning is user-written, and it is fail-closed.

### 9.2 Pause is not stop

`{pause, run, now}` → `paused`: dispatch nothing, keep observing, keep lanes alive. The quota
exhaustion path uses the same state, with `resume_at` set from `reset_epoch + margin`. So "wait for
the reset and continue" [007] is one state and one comparison, not a subsystem.

---

## 10. What survives a crash, and how recovery decides

### 10.1 The three things on disk that make recovery deterministic

1. `lanes/<id>/start.json` written **before** launch, carrying pid, pid start time, worktree, account,
   compose project and session ids.
2. `owned.ndjson`, append-only, one line per created resource.
3. `journal.ndjson`, append-only, never rewritten. (FIELD-NOTES §2.1 and §11.3: the previous
   generation's `state/attention` was `: >`-truncated **every cycle**, destroying a whole night of a
   second process's corrections, discovered by accident at 06:58Z. No file in this design is ever
   rewritten in place except `status.json`, which is a derived view and is replaced atomically.)

### 10.2 Restart (Д10)

`/orchestrator:run` on a project with an existing run dir and a free lock:

1. Acquire the lock. If held → exit **69**, print the holder, do nothing. (This is R1-10's
   «переконуєш що воно не спрацювало, а після того запускаєш новий» [300] as a syscall: the lock
   *being acquirable* **is** the proof that the previous supervisor is gone. C6-A2's "third verdict"
   problem — the probe errored — cannot arise, because there is no probe.)
2. For every dir in `lanes/`: adopt if `pid` is alive **and** its start time matches; otherwise mark
   the lane `orphaned`.
3. **Adopted lanes keep running.** An orphaned lane's ticket is not re-dispatched automatically: the
   lane goes onto the judge's fact sheet with its last events, its worktree's `git status --porcelain`
   and its resource list, and the verdicts are `resume | reseed | release | escalate`.
4. Anything alive in the project that is **not** in `lanes/` is never touched, in any state. That is
   R1-16 case 2 [370] and it is free here, because the ledger is the identity — the orchestrator acts
   only on a pid it recorded starting whose start time still matches. FIELD-NOTES §11.8's
   `pkill -f 'playwright test'` killing an unrelated lane (VERIFIED) is unreachable: nothing in this
   design matches processes by pattern, ever.

The one honest gap: a lane that died in the window between `mkdir` and `start.json` leaves a dir with
neither pid nor session. It is `released` — the claim is withdrawn and the ticket returns to ready.
That is safe because nothing had been launched yet.

### 10.3 The doctor — the whole health check is "try to take the lock"

`orch-doctor.sh` runs on a schedule (`launchd`, DEFAULT-PROPOSED every 2 hours) under a **different
account**, as R1-10 [246] requires. It does exactly three things:

1. **Try the lock.** Acquired ⇒ the supervisor is dead, provably, with no timeout and no heuristic ⇒
   relaunch the run (`orch-run.sh` resumes per §10.2) and notify. Exit 10. Refused ⇒ alive. Exit 0,
   silent.
2. If alive: compare `journal.ndjson`'s size to the value it recorded last visit. Not grown ⇒ the
   supervisor is looping without ticking ⇒ write `{stop, run, now}` and notify. Exit 12.
3. If alive and journalling: compare `status.json.queue.done_this_run` across two visits. No change
   ⇒ **notify only, never kill.** Slow and stuck are not distinguishable from outside.

This is a ~40-line script that reads no quota, probes no roster, and needs no access to the
orchestrator's account — which dissolves C6-A1 (the checker on a separate account is structurally
blind to the orchestrator's account; VERIFIED that two `CLAUDE_CONFIG_DIR` profiles return completely
disjoint session rosters) and C6-A9's "who checks the checker" (a doctor that never runs simply means
a dead run stays dead until morning, which is the same outcome as having no doctor — it cannot cause
a second orchestrator).

It cannot run while the Mac sleeps, and C6-A5 is right that sleep is how the last run actually ended
(FIELD-NOTES §10.1, VERIFIED). Two cheap mitigations, both defaults: `caffeinate -i` bound to the
**supervisor's own pid**, not to a watcher's (the previous generation bound it to the watch loop, so
when the watch died the machine slept — INFERRED from C6's reading of the plugin structure); and the
supervisor stamps `boot_epoch` from `sysctl -n kern.boottime` plus `last_tick`, so a gap longer than
`3 × interval` between ticks is journalled as `sleep_gap` and every liveness verdict computed across
it is discarded rather than trusted.

### 10.4 The lock is keyed on the project, not the run

One consequence, stated because it is a real restriction: **two runs against one project are refused**
(exit 69, naming the holder). Two runs against two projects are fine. C6-A12 shows the alternative —
two runs on one board, both claiming, both merging, with FIELD-NOTES §4.4's silent tree corruption as
the ending. The cost is that he cannot run two milestones of one repository concurrently. §14.

---

## 11. Verify before you run, and finishing without tails

### 11.1 Preflight — one script, zero tokens, refuses loudly

Five separate items of his collapse into one gate: account switching proven before the run [199],
the notification channel proven [395], the board's minimum statuses proven [153], the worktree's env
and stack proven [433], and the platform proven present today (ADAPTER-CONTRACT §3 J). Preflight
refuses to start on any of:

- the lock is held (exit 69);
- `adapters/<p>/preflight.sh <account>` fails for any configured lane account — and it must print
  *which* account, because C4-A1 applies: two config dirs may resolve to the **same account**
  and quota pool, so "the switch worked" and "these roles are on different quota pools" are different claims and only the second one
  matters. Preflight prints the resolved `(platform, base_url, account-identity)` per role and
  **refuses when two roles that the config separates resolve to one identity**, unless
  `--allow-shared-account`;
- a threshold names a bucket the account's `capacity.sh` does not report;
- `caps.sh` denies a configured requirement (§7.2);
- the notification channel does not deliver a real message (a `getMe`-shaped check is refused as
  proof — C9-A5 records that Telegram's `getMe` passes for a bot that was kicked from the chat);
- the board proves **write**, not read — it posts and removes a probe comment. Read-only access is
  reported and requires `--allow-readonly-board`;
- `RULES.md` is unreadable (R1-15 says reading it is «в обов'язковому порядку»; C8-A5 notes the
  failure branch is undefined — here the branch is *refuse*, which is the fail-closed side);
- the worktree base ref does not exist, or a required env var / stack named in `lane.requires` is
  absent;
- the engine's `probe` command is missing while `process.kind = engine`.

DEFAULT-PROPOSED `session.permissions: inherit` — **the orchestrator passes no permission flag at
all** and the platform uses the user's own settings. This is R1-15 [357] taken literally («технічні
обмеження середовища користувач за потреби налаштовує сам»), and it is the direct correction of
C8-A4, which is VERIFIED in the shipped source: `harness-spawn.sh:32-39` defaults to
`--dangerously-skip-permissions` **and falls back to it for an unrecognised value**. Here an
unrecognised value is a config error. Preflight prints the *effective* posture it detected from the
platform's own report, so the owner sees what he is running with rather than what the plugin chose.

### 11.2 The end of the run (Д3)

Terminal condition, checked every tick: **no live lanes** AND **no claimable ready ticket** AND
(no human-blocked items OR `when_only_blocked: finish`). LANDSCAPE §5 records that this — *"run a
queue unattended for hours, stop cleanly when it empties, and kill only what you started"* — is
**still unowned in the whole field**: every multi-ticket tool surveyed returns zero hits for
`drainAndExit | exitWhenIdle | shutdownWhenEmpty | queueEmptyExit`. It is nine lines here because the
queue and the lane set are both directories.

DEFAULT-PROPOSED `when_only_blocked: wait` (his own stated recommendation, Д7 [455]) with
`wait_max_minutes: 0` (forever, also his) — **and one notification on entering that state**, because
otherwise a run that is behaving exactly as configured is indistinguishable from a dead one.

**Teardown** walks `owned.ndjson` in reverse and stops each entry, then **asserts** it:

| kind | stop | assert |
|---|---|---|
| `process` | `SIGTERM`, then `SIGKILL` after `grace_s` | `kill -0` fails |
| `compose` | `docker compose -p <recorded name> down` | `docker ps -q -f label=com.docker.compose.project=<name>` empty |
| `worktree` | `git worktree remove` (or leave, per config) | path gone |
| `session` | adapter `stop` | adapter reports gone |

Two rules, both from the record. First: **the compose project name is read from `owned.ndjson`, never
from the environment.** FIELD-NOTES §11.5 (VERIFIED) records the owner's default stack destroyed by a
`docker compose down -v` with no `COMPOSE_PROJECT_NAME` exported, actor never identified, two minutes
after a different session had refused the same action as owner-only; and §12.4 records that detached
scripts inherit no environment at all. C8-A2's sharpest point is that teardown is the step most
likely to be run by a detached or restarted process — so the identifier must be on disk.
Second: **assert by observation, not by the command's word.** ADAPTER-CONTRACT §2.4 invariant 10
records `cursor-agent worker kill` reporting success and leaving the process at 100 % CPU.

Anything that fails to stop is listed in `report.md` and in `status.json`, never swallowed.

**Residue from a previous run** (C8-A1: Д3 and R1-16 together define a set nobody may clean, and the
observed output was *about 150 orphaned Docker volume pairs*, FIELD-NOTES §11.11) is **not touched**.
Preflight lists it as `orphans_from: <run-id>` and prints one exact command per item for the owner to
run. That is the honest minimum: the rules forbid reclaiming, so make the residue visible rather than
guess.

---

## 12. What the owner sees, when, and only when he asks

Д11 [508], corrected by him at [511]/[512] from «нічого не виводити» to «мінімальна кількість
аутпуту і стокінгів»:

- **During the run: nothing.** No terminal output, no push, no summary. `nohup` to `/dev/null`.
- **`orchestrator:status`** — a **bash script**, not a skill, not a command that invokes a skill.
  It reads `status.json` and prints about twelve lines. **Zero model turns.** This is the direct fix
  for C9-A11, which is VERIFIED in the shipped product: `commands/status.md` routes status through a
  skill while `harness-run.sh do_status --json` underneath it is pure bash + jq whose own comment says
  it needs no terminal and no network. Ten status checks in a night currently cost ten model turns.
- **Run addressing** (C9-A10): `--run <id>`, else `$ORCH_RUN`, else resolve the project root from cwd
  with `git rev-parse --git-common-dir` and look it up in `index.tsv`. **VERIFIED on git 2.33.0
  today**: from inside a worktree that returns the main repo's `.git`, so running `status` from a lane
  worktree — the natural place to stand at 04:00 — resolves to the right run. More than one match →
  list them and exit 2. No match → exit 4.
- **Notifications** are the only push, they are opt-in, and the channel is proven in preflight
  (§11.1). DEFAULT-PROPOSED `notify.events: ["run_stopped", "quota_hard", "capacity_unknown_grace",
  "repeated_failure", "only_blocked_work_left", "board_sync_degraded", "doctor_relaunched"]` — seven
  events, all of them things that end or stall a night. R1-17's substantive half — *what is worth
  waking him for* — was never answered (`extract/by-item.md` R1-17 final row, VERIFIED), so this list
  is proposed, not decided, and preflight prints it with a one-line invitation to cut it.
  DEFAULT-PROPOSED `notify.channel: none` is **not** used: with no channel, Д7's default (wait
  forever) plus Д11's silence is a run that can block indefinitely with nobody told — C9-A6's exact
  collision. Instead the default is `terminal` (a line appended to `journal.ndjson` and
  `status.json.blocked_on`), and preflight prints one line when no real channel is configured while
  `when_only_blocked: wait` is set.
- **`report.md`**, written once at finish: what was claimed, what completed, what each lane's outcome
  and completion oracle were, every judge verdict with its reason, every resource torn down and every
  one that resisted, the quota position at start and end, and the open questions still in the channel.

---

## 13. Every default this design proposes

None of these is a decision. Each says what it protects against.

| Key | DEFAULT-PROPOSED | Protects against |
|---|---|---|
| `tick.interval_seconds` | 60 | A tick loop cheap enough to run all night with no model in it; one-minute worst-case stop latency |
| `run.mode` | `controlled` | He named three values [075] and no default. `ask` cannot be the default: a 04:00 restart has nobody to ask (C1-A5) |
| `concurrency.max_lanes` | 2 | FIELD-NOTES §9.3: two lanes ran cleanly; §5.1: two concurrent image builds OOM-killed his own container. Machine-resource awareness is deferred by him [160] |
| `tickets.ready_requires` | `["Outcome","Acceptance","Scope"]` | A one-line ticket eating four hours (C3-A6). Measured clean over 327 tickets |
| `tickets.notify_on_queue_growth` | 50 | The 236→327 overnight queue growth that needed a human to brake it (FIELD-NOTES §10.1) |
| `capacity.soft_pct` / `hard_pct` | 80 / 95 | 80 is his own number [171]; 95 above it because he used 80 for both soft and hard (C4-A2) |
| `capacity.on_unknown` | `hold_dispatch` | The shipped `proceed`, which made the limiter inert for days (C4-A6, FIELD-NOTES §11.7) |
| `capacity.unknown_grace_minutes` | 30 | `hold_dispatch` silently idling a whole night on a 429 |
| `capacity.cache_seconds` | 900 | A measured one-call `rate_limit_error` on the usage endpoint with four standing pollers on this machine (C4-A3) |
| `capacity.reserve_pct` | 0, **flagged** | Inventing a reserve for an account he also works in. The question was never put to him (meta.md G3) |
| `context.raw_pct_threshold` | 75, per role | Two percentages ~13 points apart on his machine (C5-A2); refill rates differing 13× by role (C5-A11) |
| `context.mode` | `soft`; `fallback: reseed` | Hard mode is not implementable on four platforms (ADAPTER-CONTRACT §3 D) |
| `liveness.silence_minutes` | 20 | The previous `stall_minutes`; long enough not to fire on a 14-minute suite |
| `judge.max_calls_per_tick` / `_per_hour` | 1 / 30 | A judge in a disagreement loop spending the night (Д11's token concern made mechanical) |
| `judge.on_unparseable` | `defer` | A malformed verdict acting. Waiting is always the fail-safe |
| `failures.repeat_threshold` | 3 | His number, exactly [442] |
| `failures.action` | `notify_and_stop` | He offered notify+stop or just stop [442]; the noisier one is safer at 03:00 |
| `worktree.enabled` / `base_ref` | `true` / the repo's default branch | Д4's «абсолютно все» [433] |
| `worktree.remove_on_done` | `false` | Removing a tree with uncommitted work. Preflight lists leftovers instead |
| `session.permissions` | `inherit` | The shipped `bypass` default and its bypass-on-unknown fallback (C8-A4) |
| `red_lines.path` | `<project>/.orchestrator/RULES.md`, read from the **main checkout** | The worktree fork that hid an owner-facing question for an hour (FIELD-NOTES §12.5, C8-A5) |
| `red_lines.apply` | `next_launch` | A mid-run edit reaching a running lane requires a reseed; quiet by default, with `now` available |
| `questions.answer` | `when_native` | Answering by keystroke with no acknowledgement (C7-A9); the field is split and refusing is the cheap side |
| `questions.channel` | unset → preflight asks once | Д6 [449] says the configurator should ask |
| `when_only_blocked` | `wait`, `wait_max_minutes: 0` | His own recommendation [455] |
| `notify.channel` | `terminal` | `none` plus wait-forever plus silence = an indefinite block nobody is told about (C9-A6) |
| `notify.events` | the seven in §12 | R1-17's substantive half was never answered; the list is printed for him to cut |
| `board.writeback` | `true` for a board source; **`false` for the local registry** | The tool's own log inside the ticket body firing its own change detector (C3-A1, C3-A10) |
| `doctor.enabled` / `interval_hours` | `false` / 2 | Off by default because it needs a separate account, if the user configures one; 2 h because a 4 h window swallows an 85-minute loop whole (C6-A10) |
| `trunk.policy` | `pr_only` | On his own repos no machine source states the rule: `gh api …/rulesets` → `[]` and `…/branches/main/protection` → 404, while `CLAUDE.md` says PR-only (C9-A3, VERIFIED) |
| `stacked_prs` | `false` | `--update-refs` needs git ≥ 2.38; this machine has **2.33.0** (VERIFIED). Enabling it here silently re-applies superseded commits (C9-A9) |

---

## 14. Tensions with his decisions — designed for, not replaced

Each of these is a decision of his that this design implements while something about it stays
uncomfortable. None is quietly substituted.

1. **«Оркестратор» is bash, not an agent.** He pictured three windows — context watcher,
   orchestrator, executor — as sessions [036], [195], [204], and `extract/outside-list.md` §12.2
   records that the three-role model never reached the analysis at all. Here the roles survive
   **as model+account pins** (`roles.orchestrator` = the judge; `roles.watcher` = the cheap model for
   change checks; `roles.executor` = the lanes), which is what he assigned accounts and thresholds
   *for*, but two of the three are no longer sessions. **Tension:** he cannot open the orchestrator's
   window and read what it is thinking; he reads `status.json`, `journal.ndjson` and
   `decisions.ndjson` instead. **What it buys:** the orchestrator has no context window, so R1-08's
   hardest case and C5-A3/A5's deadlock (the fresh-orchestrator option versus the
   single-orchestrator invariant) do not exist.

2. **«Хард»/«софт» keep their command names and lose their file field.** §2.2. He wants one file
   [195] and one vocabulary; three of his items give that vocabulary three meanings. The commands he
   named are unchanged; the file is explicit. **Tension:** if he hand-edits `control.json` he must
   write three fields, not one. The commands exist so he does not have to.

3. **R1-08 «гарантовано» holds only via reseed.** On Amp, Gemini CLI, Cursor and `dsh` there is no
   external compaction trigger at all (ADAPTER-CONTRACT §3 D), so on those platforms "stop now,
   compact, continue" is **not implementable as stated**. What it costs to keep the guarantee:
   close-and-reseed — one session restart, the context paid for a second time, and ticket→session
   becoming a lineage rather than a field. That is the price, and it is the whole price.

4. **R1-07's hard account change is a stop-and-relaunch, always.** Changing a live session's account
   is impossible on all fifteen platforms (ADAPTER-CONTRACT §3 F) and FIELD-NOTES §8 measured the
   same. The design does it as stop + relaunch + reseed and says so in the command's output before
   writing the entry.

5. **R1-15's one text file is honoured, and it is the only policy surface.** No hooks, no permission
   wrapper, no deny list, no sandbox — `session.permissions: inherit` is the plugin abstaining. What
   the design adds is **not enforcement, it is bookkeeping**: a recorded resource ledger and a
   teardown that only touches it. That bounds the blast radius of the *cleanup* path — the path that
   actually destroyed his stack — without adding a procedure he refused. **Tension, stated:** C8-A9's
   two failures stand. A flat prose file has no field separating an absolute from a preference, and
   C8-A10 is right that no line writable in it would have prevented Playwright's `--trace on`
   printing two passwords into a transcript (FIELD-NOTES §11.10). The file cannot cover that class,
   and the design does not pretend it can.

6. **The board becomes a mirror.** [149] frames the board as the orchestrator's «помічник» — a
   working surface. Here the run directory is the working surface and the board is a best-effort
   projection, because the alternative loses real work to a 403 at 03:00. On the **local** registry it
   goes further: the orchestrator never writes into a ticket body at all.

7. **A fourth scope exists, and it is not a config file.** §8.1. snf says three levels are the whole
   set; he requires a per-run scope. Resolved by declaring the run scope to be per-invocation state.

8. **Two runs on one project are refused.** §10.4.

9. **Controlled vs autonomous: a proposal for I2, not a decision.** He deliberately left the
   definitions open [082] and asked the collector to bring him options. The proposal this design is
   built on is: **a run mode is a policy over one observable event — the orchestrator is about to act
   and no configured rule supplies the answer.** `controlled` files that moment in the Д6 channel and
   holds the *ticket* (other tickets continue, per Д6 [449]); `autonomous` lets the judge decide and
   appends the decision with the fact sheet it saw. **Why it is offered:** C1-A1 shows his own
   trigger — «сумніви», «не впевнений на сто» — is a self-report no second party can check, and that
   the previous generation shipped exactly that predicate ("<70% sure", VERIFIED in
   `templates/prompts/orchestrator.md:19-21`). **What it costs:** the mechanical trigger is strictly
   narrower. A session that is confidently wrong never reaches it, and no measurable property of the
   finished run distinguishes "no doubts arose" from "every doubt was suppressed" — which is the
   collision with his own R1-01 [062]. It is his to accept or reject.

10. **Д4's «з цим треба поєднювати» is an assignment, not a decision.** GSD under a host-created
    worktree runs no git of its own and can degrade to sequential when HEAD diverges from the fork
    point (VERIFIED, C9-A2). This design makes the base ref explicit per lane and refuses a GSD lane
    whose base disagrees. Reconciling the two worktree owners properly is still owed.

11. **The learning loop survives only as a file.** «якщо це не підходить, то треба вчити» [062] is
    the only place in the whole session where feedback changes future behaviour, and
    `extract/outside-list.md` records it is absent from the analysis entirely. Here:
    `decisions.ndjson` records every verdict with its fact sheet, and a hand-maintained
    `<project>/.orchestrator/CORRECTIONS.md` is read into the decision basis. **The system does not
    learn by itself, and the deciding party is never allowed to write to the basis it decides on** —
    which is A6's worse variant, the actor writing its own precedent.

---

## 15. What this lens makes worse, what it drops, and the weakest point

### 15.1 Worse

- **Interactive terminals are demoted to an exception.** R1-11 asks for interactive / headless /
  hybrid / mostly-interactive **per platform** [324]. This design is headless-first: `attach: true`
  exists per platform and uses tmux, but takeover of a running headless lane is a **handoff** (stop →
  relaunch attached → reseed), costing one restart. He can no longer walk up to a lane and type into
  it without paying that. This is the largest single deviation from a decision he confirmed ([328]).
- **The judge has no memory.** Every decision is made from a fact sheet composed by bash. Anything
  the supervisor does not render does not exist. Cross-ticket pattern recognition ("this is the third
  time this week") exists only where the renderer includes it — and it includes a fixed, small slice:
  prior reseeds and failures on *this* ticket, and the last N decisions.
- **The board can be stale.** Best-effort write-back means a human reading the board at 09:00 may see
  a state the run has moved past, with `board_sync: degraded` visible only in `status.json`.
- **Concurrency is a number, not a scheduler.** Machine resources are deferred by him [160], so two
  heavy lanes can still OOM his own container exactly as they did (FIELD-NOTES §5.1). The only
  mitigations are the cap and an optional `pre_dispatch` hook command.
- **`on_unknown: hold_dispatch` can idle a good night.** A rate-limited quota endpoint — which C4-A3
  measured on one call — stops new dispatch for `unknown_grace_minutes` and then only notifies.
  Safer than the shipped `proceed`, and more expensive.
- **A reseed loses the in-flight turn.** Hard-mode context handling and hard account changes both
  discard whatever the current turn had not written, and C5-A6 is right that on this project a
  compaction landing mid-mutation can leave deliberately-broken bytes with nothing left that knows to
  undo them. The mitigation is one line in the handoff (`git status --porcelain` at stop time) and it
  is weaker than the problem.

### 15.2 Dropped

- The context-watcher session, the validator role, the question-role session, the council advisor —
  four session kinds down to one.
- All screen scraping, all typing into sessions, tmux by default, `send`, `key`, the nudge, the
  heartbeat file, the attention file. With them go the six FIELD-NOTES failure records they produced
  — and also the *capability* they provided: nothing in this design can talk to a session that is
  already running, except through the adapter's own protocol channel.
- "Guaranteed compaction" in its strong form on four platforms.
- Mid-run **mode-flip semantics for decisions already taken** (C1-A10): a flip applies forward only,
  and the command says so. Re-opening past decisions is not built.
- A ladder of escalation for silence (R1-09 asked for one and he declined to give one): there is
  exactly one rung — render the facts, ask once, default to waiting.
- PR stacking, off by default, because the machine's git is 2.33.0.
- The intermediate stop mode's richer form. He floated "save state, maybe save the session, close it,
  resume later" with «Не знаю» [171]; here it is `paused` plus reseed, which is the minimum that makes
  the other two modes coherent and is less than he imagined.

### 15.3 The single weakest point

**The fact sheet.** Everything this design removes from the model, it moves into bash — and
everything bash cannot see, the model is never shown. R1-09 is the whole requirement
(«він дивиться, перевіряє ті сесії … які в них прогрес, що вони там зробили»), and the three signals
the supervisor can render for free are *process alive*, *event file growing*, and *engine probe line*.

Put the run's worst recorded lane against those three. `w-phase-19` (FIELD-NOTES §3.1, VERIFIED)
issued **3,466 of its 3,626 Bash calls as the literal command `echo idle`**, at about 1,400 an hour
for three and a quarter hours, adding **445k tokens — 77 % of all context growth in that window** —
and reaching 91 %. Against this design's fact sheet it reads: process alive, event file growing
briskly, engine probe `state=running`, context rising. Every fact is true and every fact says
healthy. The one signal that would have caught it — that the same tool call repeated thousands of
times — is cheap to add as a fourth line (`top repeated tool call in the last N events`), and I would
add it; but that is the point. **The design's coverage is exactly the list of things someone thought
to render, and that list is short by construction because the lens is minimality.** The previous
generation caught this lane only because a human read a transcript and told it to end its turn, and
it stopped within one minute of being told.

A second candidate, named because it is close: the judge's verdict is unaudited. It is recorded with
the fact sheet's sha1, so a wrong verdict is *reconstructible* afterwards — but nothing contradicts it
in flight, and R1-13 [344] forbids the orchestrator adding checks of its own. That is his decision,
taken under the evidence [342], and this design honours it. The cost lands here.
