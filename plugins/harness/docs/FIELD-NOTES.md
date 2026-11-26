# Field notes — harness 0.6.0 in a 34-hour unattended run

Raw observations from running this plugin against a real project. **Facts only.** No conclusions and
no recommendations: a reader improving the harness should draw their own. Every record carries a
reference that can be opened.

The run these notes come from is `20260911-212252` in
`<work>/<work-project>/.harness/runs/`. It executed nineteen
planned phases of a website build, one GitHub issue per phase, unattended overnight, with a human
reachable only intermittently. The previous run in the same directory, `20260831-184751`, is the
comparison point where one is useful.

Where a path is given without a root it is relative to that project repository.

---

## 0. The shape of the plugin, as read from its own source

Paths here are relative to `plugins/harness/`.

**Scripts.** `hlib.sh` — shared helpers: `cfg`/`cfg_int`, path guards, `atomic_write`, `hlog`,
`git_recent`. `harness-spawn.sh` — spawn, close and list sessions; builds the launcher, applies the
rate gate and the sonnet validation, opens the terminal, verifies boot, writes the registry.
`harness-term.sh` — the only file that talks to a terminal application. `harness-run.sh` — run
lifecycle (`start|stop|status|resume|watch`); owns the watch loop and `caffeinate`.
`harness-state.sh` — markers, heartbeats, decision and owner-action logs. `harness-tickets.sh` — the
queue, either GitHub labels or local files. `harness-limits.sh` — subscription rate-limit snapshot,
verdict and wait. `harness-model.sh` — resolves a model OR-chain such as `fable|mythos|opus`.
`harness-trust.sh` — handles Claude Code's trust-folder dialog. `harness-validate.sh` — a sonnet
"second net" reviewing the launcher, cwd and role before a spawn (exit 65 rejected, 70 infrastructure
error). `harness-gsd.sh` — discovers installed GSD skills and MCP tools at runtime.
`harness-guide.sh` — lists a repository's own lint, test, build and branch guidance files.

**Configuration keys and their defaults**, resolved project → user → default (`hlib.sh:48-58`):
`tickets.source` `local`, `tickets.repo` empty, `tickets.label_prefix` `harness`;
`limits.pause_next_spawn_at` `90`, `limits.weekly_pause_at` `99`, `limits.on_unreadable` `proceed`,
`limits.resume_margin_seconds` `90`, `limits.stop_at` null; `accounts.env_command` empty plus a
per-role override; `session.permissions` `bypass`, `session.boot_grace_seconds` `45`,
`session.close_timeout_seconds` `90`; `models.orchestrator|worker|validator|question` chains;
`guardrails.never_push` `true`, `guardrails.sonnet_validation` `true`,
`guardrails.sonnet_trust_check` `true`; `run.caffeinate` `true`, `run.stall_minutes` `20`,
`run.watch_interval_seconds` `60`; `terminal.app` `auto`, `terminal.fullscreen` `false`;
`guidance.files`, `guidance.notes`.

**Roles** are `orchestrator`, `worker`, `validator`, `question` (`harness-spawn.sh:42-49`).

**A launcher** is a generated bash file: it sanitises `PATH`, exports `HARNESS_PROJECT`, cds into the
worktree, applies the account env command, sets a never-push remote, then loops the model candidates
calling `claude --model … --session-id … <perm-flag> "$(cat prompt)"`, falling back within
`boot_grace_seconds` (`harness-spawn.sh:159-195`).

**The registry** is one JSON file per session at `<run>/state/registry/<name>.json` carrying name,
role, group, tty, pid, session_id, cwd, model_chain, launcher and started_at.

**Markers** are existence-gate files at `<run>/markers/<name>.done`. **Heartbeats** are an append log
at `<run>/heartbeats/<name>` plus a `.epoch` file holding the last beat's unix time; heartbeat-age
prints `never` when the file is absent.

**The watch loop** (`harness-run.sh:222-411`) runs under `nohup`, keeps its pid at `state/watch.pid`,
and binds `caffeinate` to itself. Each tick it reads every registry entry, the last ~25 lines of each
session's screen, each heartbeat age, and recent git activity. Its staleness rule: heartbeat age
exceeds `stall_minutes × 60` **and** there is no recent git activity **and** the screen lacks
`esc to interrupt` → send one Enter, and do not nudge that session again for 3600 seconds. A
rate-limit banner triggers `harness-limits.sh wait`, then Escape and `continue`. An orchestrator dead
with no live session for three ticks triggers a full teardown (`harness-run.sh:348-357`).

**Tickets.** The GitHub backend is labelled issues moving `ready → in-progress → done | blocked |
needs-review`. The local backend is files under `.harness/tickets/` with a `status:` frontmatter and a
lock for id allocation. `require_ready_body` refuses to let a ticket be `ready` unless its body carries
Outcome/Goal/Objective, Acceptance criteria and Scope headers (`harness-tickets.sh:29-36`). Ticket
bodies reach a prompt only through `fence_body`, wrapped in an UNTRUSTED-input sentinel that
neutralises embedded fake sentinels (`43-49`).

**Terminal backends** are iTerm2, Terminal.app and tmux, preferred in that order under `auto`. iTerm2
and tmux support every verb. **Terminal.app supports only spawn, capture and close — `send` and `key`
are explicitly refused as undrivable** (`harness-term.sh:163-181`), which makes it unusable for any
procedure that types into a session.

---

## 1. Session lifecycle — what was observed

### 1.1 A session cannot compact itself

`/compact` is typed into a session's terminal **by another process**. The documented procedure is in
`docs/open/supervisor/WATCHER-PROMPT.md` and is literally
`bash {{HBIN}}/harness-term.sh send <tty> "/compact"` — the context watch types it into the
orchestrator's tty, waits for the percentage to fall, then types a second line telling it what to read
back. A model has no way to put text on its own input line.

Observed: the orchestrator's heartbeat at `2026-09-13T05:51:55Z` reads `resumed after compact;
supervising v-phase-22`, and the context-watch log around that time records the before and after
percentages. Reference: `.harness/runs/20260911-212252/heartbeats/orchestrator`, and
`logs/context-watch.log` (search `compact is holding`).

### 1.2 `/compact` lands only when the target has no shell running

Three attempts on the same session (the context watch, tty `ttys002`) in one day:

| Attempt | Input line | Shells running | Result |
|---|---|---|---|
| 1 | empty | yes | no change; command consumed as an ordinary message |
| 2 | empty | none | 73% → 0% in about 90 seconds |
| 3 | empty | yes (2) | no change over 4.5 minutes; session drifted 91% → 95% and auto-compacted |

An empty input line is not sufficient. The shell count printed in the session's own status bar
(`⏵⏵ bypass permissions on · 1 shell · ← 2 agents`) is the discriminator. Transcripts of all three:
`scratchpad/watch-compact*.log` in the session that performed them; the percentages are also visible
in `logs/context-watch.log` cycle lines as `ctx=NN%`.

### 1.3 Text typed at a session may never arrive

Measured across the run: **five separate instructions typed into sessions were never delivered.** The
mechanism, characterised by the context watch and recorded in `logs/context-watch.log` (cycle 171):

- a bare Enter (`harness-term.sh key <tty> enter`) does **not** submit text already sitting on the line
- `send <tty> "<text>"` types its own text and submits — so it **destroys** whatever was pending
- when a background task re-invokes the session, whatever sits on an idle input line is **discarded**

The one instruction that did arrive was sent to an **empty** line while the session was parked
(`logs/context-watch.log`, cycle 215, `2026-09-13T05:00:00Z`): one word, `continue`, verified landed
three ways — screen, busy check, and the session transcript's last user message.

### 1.4 The engine's nudge does not submit stranded text

`harness-run.sh watch` presses a bare Enter when a heartbeat is stale. Measured twice — on a validator
at `03:26:34Z` and on the orchestrator at `05:21:06Z` — the stranded text was still on the line
afterwards both times. Reference: `.harness/runs/20260911-212252/logs/watch.log` for the nudges,
`state/screens/*-orchestrator.txt` for the before/after screens.

### 1.5 Heartbeat staleness is not a stall

A session heartbeats **between** turns. A validator running a 14-minute suite, or a worker in a long
turn, does not heartbeat at all. The engine's watch loop treats staleness as a stall and nudged six
times in this run — `v-phase-10`, `w-phase-13`, the orchestrator twice, `v-phase-12`, `w-phase-15` —
and every one of those sessions was healthy at the time. Reference: `logs/watch.log`, and the context
watch's own corrections in `logs/context-watch.log` (search `false STALLED`).

### 1.6 A finished session is closed by nobody

`q-screen-orchestrator`, a `question`-role session spawned at `2026-09-11T22:55:31Z`, answered its
question and then stayed registered and idle for **one day and four hours**. The context watch logged
it as `finished-awaiting-close` for hours and has no remit to close it; the orchestrator that spawned
it had moved on. It was closed by hand. Reference: its registry entry under `state/registry/`, and
`logs/context-watch.log` (search `finished-awaiting-close`).

Side effect worth noting: its terminal title read `harness-question-q-screen-orchestrator`, which the
product owner read as a second orchestrator.

---

## 2. The watch loop's own blind spots

### 2.1 `state/attention` is rebuilt from scratch every cycle

`harness-run.sh` line 226 does `: > "$run/state/attention.tmp"` and line 361 does
`mv "$run/state/attention.tmp" "$run/state/attention"`. Anything appended to that file by anyone else
is destroyed within one watch interval.

The context watch had been writing its corrections there all night and only discovered this at
`2026-09-13T06:58Z`, by grepping for a block it had written four minutes earlier and getting nothing
back. Its own account of what was lost — including a measured rebuttal written while the orchestrator
was weighing killing a 378-test suite at test 240 — is in
`.harness/runs/20260911-212252/state/note-to-context-watch.md`, section "My reporting channel was
broken all night".

### 2.2 A shell that cannot exit reads as work

The shell count is the strongest "busy" signal available, and it is forgeable by accident. A lane held
one shell running `until grep … sleep 5` against a file that had finished being written forty-five
minutes earlier: the pattern could never match, the loop could never end, and no check would ever have
called that session parked. Reference: the analysis is in this session's transcript; the pattern is
visible with `ps -axo pid,ppid,command | awk '$2==<session-pid>'`.

A different shape of the same thing: a lane accumulated **58 concurrent child shells**, each a
`sleep 590` poll printing suite progress, spawned roughly every two minutes for two hours. They cost
~75 MB total and 0% CPU — cheap in machine terms, but each one returns output into the session and
consumes its context.

---

## 3. Context exhaustion

### 3.1 A lane spent three quarters of its window on polling

`w-phase-19` waited for its GSD subagents by running `echo idle` in a loop rather than ending its turn.
Measured from its transcript: **3,466 of 3,626 Bash calls were the literal command `echo idle`**, mean
interval 2.54 s, about 1,400 an hour, from `13:50:57Z` to `17:05:52Z`.

Cost, deduped by API response: 445k tokens of context added by the idle responses (77% of all context
growth in that window, against 135k from real work), 274k output tokens, and 1.83 billion cached
tokens re-read. The session reached 91%.

Every other worker lane in the run — phases 1, 2, 10 through 18 — has **zero** `echo idle`. Lanes 1
and 2 waited on 10 and 34 `Agent` calls without polling at all; lane 18 used `Monitor`. The behaviour
was the model's own choice, made after it had loaded `Monitor` via `ToolSearch` and never used it. Its
prompt warns that subagents may hang, which is the likely cause of the defensiveness.

It stopped within one minute of being told to end its turn instead: 18–21 calls per minute through
`17:05`, then zero from `17:06`. Reference: the lane's transcript at
`~/.<switcher>/profiles/<profile>/projects/-<work>-<work-project>/<session-id>.jsonl`.

### 3.2 Refill rates observed

- The context watch refilled from 9% to 91% in about ten hours of ordinary cycling — roughly 8% an
  hour at a ~120-second cycle.
- A worker lane executing a six-plan phase reached 91% in three and a half hours, three quarters of it
  polling.
- The orchestrator reached 64% after 30 hours, and had been compacted once.

### 3.3 Nothing in the plugin measures context

`bin/*.sh` contains no reference to context, percentages, or compaction; a grep for
`compact|ctx=|auto-compact` returns nothing. The thirty-three configuration keys the plugin reads
(`grep -rhoE "'\.[a-zA-Z_][a-zA-Z_.0-9]*'" bin/*.sh`) include `limits.pause_next_spawn_at` and
`limits.weekly_pause_at`, which are **token quota** thresholds, not context-window thresholds.

The context percentage is nevertheless available with no new machinery: it is printed on every
session's own status line, and the watch loop already captures every screen each cycle.

---

## 4. Git and merge behaviour

### 4.1 A merge reported success and did nothing

`git checkout master` aborts when a tracked file is modified, and one always is: GSD rewrites
`.planning/milestone.lock` during every phase and leaves it dirty. The merge command that followed then
ran **on the phase branch against itself** and printed `Already up to date` and `Everything
up-to-date`. Both read like success.

It was caught only because the orchestrator checked what `master` actually pointed at after the push
rather than trusting the exit status. The lock holds a dead session's pid and a timestamp; the churn
was discarded with `git restore` and the merge retaken. Reference:
`.harness/runs/20260911-212252/DECISIONS.md`, entry `2026-09-12T19:18:27Z`.

### 4.2 A phase reached the trunk without its independent validation

`phase-21` went from the lane's `pr-ready` marker straight to the merge at `2fb5301`, because the
orchestrator never spawned the validator. Every other phase in the run went worker → validator →
merge. The orchestrator detected its own error within about a minute and ran the validation against
the surviving branch, with the verdict deciding whether the merge stood. It passed. Reference:
`DECISIONS.md`, entry `2026-09-13T03:26:23Z`.

### 4.3 GSD's computed branch name can differ from the lane's branch

At `2026-09-13T06:35:02Z` a lane recorded that GSD computes
`gsd/phase-23-tooling-the-harness-and-the-pre-commit-checkers` from the roadmap slug, one word off the
lane branch `gsd/phase-23-tooling-the-harness-SCRIPTS-and-the-pre-commit-checkers`, and that left
alone `execute-phase` would cut that name fresh from `origin/master` and lose the merged master tip.
Reference: `DECISIONS.md`, that timestamp.

### 4.4 An external party moving a checked-out branch corrupts the tree silently

`git update-ref refs/heads/master origin/master` moves HEAD and touches neither the index nor the
working tree. With `master` checked out in the main checkout, the tree then silently held older
content and `git status` showed the newest committed content as a **staged deletion**, one `git
commit` away from reverting it. Observed against `docs/open/RUN-NOTES.md`: HEAD had 69 lines, index and
worktree had 65.

---

## 5. Resources

### 5.1 The owner's own container was killed for memory by the run

`<work-project>-app-1`, the product owner's application on port 3000, was `OOMKilled` (`exit 137`) at
`2026-09-13T03:29:01Z` while the `v-phase-21` validator ran two `docker compose up --build` at once.
The run left it stopped, as its brief requires, and logged an owner action. Reference:
`.harness/runs/20260911-212252/state/INCIDENT-owner-app-oom-v-phase-21.md`.

The same file records the avoidance: do not build two images at the same time on this machine while
other stacks are running.

### 5.2 Load and memory figures under two lanes

Two lanes plus the owner's stack, each lane with its own app and postgres container: load average
peaked at 19.4 on 14 cores during an image build (15-minute average 5.5), memory pressure stayed at
48–68% free, swap grew from 3 GB to 6 GB as macOS enlarged the file. Swap **occupancy** is not a
pressure signal on macOS; `memory_pressure -Q` is.

### 5.3 A five-hour token window is not the constraint

Across 34 hours the account the run was metered against reached 26% of its weekly allowance. The dependency graph, not the
quota, bounded throughput: of nineteen phases only two pairs could ever run concurrently.

---

## 6. Timings observed

From `logs/harness.log` spawn and close lines:

- worker session per phase: 58 minutes to 3 hours 20 minutes
- validator session per phase: 15 to 40 minutes
- gap between a validator closing and the next worker spawning: 4 to 12 minutes
- two-lane overlap, phases 12 and 13: about 77 minutes
- whole run: nineteen phases planned, thirteen merged in the first 34 hours

---

## 7. What the parallel-lane machinery required

Recorded in `docs/open/supervisor/ORCHESTRATION.md` under "Two phases at once": a second lane needs its
own git worktree outside the repository directory, its own compose project and its own port block
(one hundred apart), and must not share the running stack. Worktrees observed this run:
`<work-project>-phase-13`, `-22`, `-23`. Phases before 13 ran in the main checkout on GSD's own phase
branch (`branching_strategy: phase` in `.planning/config.json`).

---

## 8. Roles as configured in this project

`.harness/config.json` routes accounts per role. Mid-run the role routing changed, which required
editing `scripts/overnight-supervisor.sh` in the same change, because that script watches a single
config dir by path and would otherwise have watched a config dir nothing ran on. A session already booted keeps the account it booted with; the change reaches the next
spawn.

---

## 9. What demonstrably worked

### 9.1 Sessions refused to guess, and escalated instead

Eleven questions were routed to the project's question channel rather than answered by assumption —
`Q-P9-01`, `Q-T122-01`, `Q-OWN-01` to `-04`, `Q-ORCH-04` to `-07`, `Q-RESTORE-01`, `Q-PARITY-01`,
`Q-T250-01` — each with a recorded `Fallback` and each later marked answered
(`docs/open/QUESTIONS.md:394-603`).

`Q-PARITY-01` is the shape worth studying: the session drove the question empirically **before**
asking — removed a permission check, rebuilt, ran the comparison in 27.4 seconds, found 64 count-pairs
identical across four roles and sixteen collections — and asked only what measurement could not settle
(`QUESTIONS.md:552-583`).

Two sessions corrected themselves in the run log: the context watch's screen-question test firing on a
healthy idle orchestrator (`2026-09-11T22:55:44Z`), and a council-advisor hang warning that had been
widened too far, reversed (`2026-09-12T13:41:00Z`).

### 9.2 Checks caught real defects before they shipped

- `gsd-plan-checker` rejected phase 20's first plan draft; three revision rounds before it passed
  (`DECISIONS.md:86-87`).
- It rejected phase 23 with one blocker and four warnings; the blocker and three warnings were sent
  back after reproduction, and one warning was declined with reasoning (`DECISIONS.md:131-132`).
- Code review on phase 22 found eight warnings plus `IN-03`, all fixed before the merge
  (`DECISIONS.md:125-126`).
- The `og:image` URL-mangling bug was found incidentally during phase 17 and written into
  `17-FOUND.md` rather than folded into that phase's scope (`OWNER-ACTIONS.md:17-20`).
- A process gap was caught and disclosed rather than buried: phases 14 to 18 shipped with
  builder-only verification because of a bad orchestrator instruction; corrected from phase 19 on and
  reported to the owner (`OWNER-ACTIONS.md:22-25`).

### 9.3 Two lanes at once

Phases 12 and 13: one lane in the main checkout on `ttys003`, the other in the worktree
`<work-project>-phase-13` on `ttys005`, spawned eleven seconds apart; ports app `3400`/pg `5444` against
app `3500`/pg `5445` (`state/compose-phase-12-ports.yaml`, `-13-`). Phases 21 and 22: the same
pattern, spawned thirteen seconds apart, ports `4500`/`5455` against `4600`/`5456`.

**No port or state collision in either pair.** Two collisions did occur in the 21/22 window, both of
another kind: the phase-21 validator's stack could not get a Docker subnet from the shared pool and
was manually assigned `10.199.21.0/24` after confirming it unused (`DECISIONS.md:119-120`); and two
parallel image builds OOM-killed the owner's own container (`DECISIONS.md:122-123`).

### 9.4 Recovery paths that worked

Twelve nudge events on stale-but-healthy sessions, all resolved — for example `v-phase-10` nudged at
1232 s of stale heartbeat and closed cleanly one minute forty-seven seconds later
(`logs/harness.log`, `22:49:24`–`22:51:12Z`).

The close-without-force behaviour worked as designed: `w-phase-15`, `-18`, `-19` and `v-phase-22` each
hit `job still running after timeout — LEAVING SESSION OPEN (never force-close, L11)` and were later
found already finished on their own (`logs/harness.log`, e.g. `06:55:33Z` and `06:56:08Z`).

After-the-fact validation: phase 21 was merged before its validator ran; the validator was then run
against the merge commit with its verdict binding on whether the merge stood. It passed
(`DECISIONS.md:116-117`).

### 9.5 Throughput, per phase (spawn to close, from `logs/harness.log`)

| Phase | Worker | Validator | Gap to next |
|---|---|---|---|
| 10 | 1 h 03 m | 22 m | 1 m |
| 11 | 1 h 25 m | 26 m | 2 m |
| 13 (parallel) | 1 h 17 m | 27 m | — |
| 12 (parallel) | 2 h 07 m | 41 m | 2 m |
| 14 | 59 m | 16 m | 8 m |
| 15 | ~1 h 53 m | 40 m | 12 m |
| 16 | 58 m | 19 m | 26 m |
| 17 | 1 h 23 m | 38 m | 4 m |
| 18 | ~1 h 14 m | 50 m | 4 m |
| 19 | ~4 h 50 m | 40 m | 5 m |
| 20 | ~4 h 03 m | 40 m | 5 m |
| 21 (parallel) | 3 h 13 m | 34 m | — |
| 22 (parallel) | 5 h 31 m | 44 m | 3 m |

Inter-phase gaps stayed under 26 minutes throughout and were mostly 2 to 12 minutes. Worker durations
grew sharply from phase 19 on — roughly four to five and a half hours against about one hour for
phases 10 to 14.

---

## 10. History

### 10.1 How the previous run ended

`20260831-184751` started `2026-08-31T18:47:51Z`, orchestrator up twenty-two seconds later, model
chain `opus`. It was preceded by `20260831-173806`. Mid-run the product owner set a soft pause at
11:15 after the ticket queue grew from 236 to 327 in a day (`state/SOFT-PAUSE.md`).

Its `RUN-REPORT.md` — written by the fifth orchestrator of that run — records the trunk moving
`93fdf65 → fc01ef2` across thirteen merges, four full gates, both full-suite gates green at 293
passed / 51 skipped / 0 failed, and zero stranded in-progress tickets at the end.

**It did not end cleanly.** The heartbeat went stale repeatedly and was nudged, then went stale again
at 6457 s, 9924 s and 13578 s, ending with
`[2026-09-07T09:08:21Z] watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may
sleep)`. The directory holds `DEAD-RUN` and `STOPPED` at that timestamp.

### 10.2 Rules the harness grew, and the failure behind each

From `docs/open/JOURNAL.md` and `docs/open/supervisor/`:

- **`J-SUP-34`** — the orchestrator sat idle 35+ minutes with eight ready tickets and no lanes,
  because the context watch logged it as "held" rather than "parked" so the auto-nudge never fired.
  Separately its heartbeat file had not moved since `2026-09-02T06:09:50Z` despite real activity — a
  false stale reading. Fixed by hand.
- **`J-WATCH-01`** (`2026-09-06T16:09Z`) — established the compact-in-place procedure for an
  orchestrator: refresh the handoff, wait for its mtime, send `/compact`, wait for the percentage to
  fall, repoint the session. Measured 67% → 0% in about seven minutes. Reused in the later run at 67%
  (668.6k tokens) → 0% → 8%, noting that `send` works where a bare Enter does not, and that it
  overwrites unsent input.
- **`J-ORCH-37`** — `harness-spawn.sh` refused to spawn a validator because a ticket quoted the
  harness's own `{{HBIN}}` and `{{RUN_DIR}}` template tokens inside its fenced body. A workaround was
  applied and logged as unsafe.
- **`J-ORCH-39`** — the direct consequence: a validator flagged a lane for an "alteration" that was
  actually the orchestrator's own prompt-edit workaround. An attribution error caused by the previous
  item.
- **`J-T169-01`** — ticket-id allocation was not locked. Before the fix, two concurrent adds against a
  272-ticket queue produced two files under one id in five rounds out of five, and a twenty-way add
  produced twenty files under three ids. After the fix, two-, twenty- and fifty-way concurrent adds
  never shared an id. Full diff in `docs/open/HARNESS-TICKET-ID-ALLOCATION.md`.
- **`J-ORCH-45`** — merge-gate scheduling changed from "gate at quiet" to "gate promptly after each
  merge wave", because holding a merge locally does not keep it off the remote when the orchestrator
  is not the only writer. Validators were told to hold suites until `ps` shows zero playwright-test
  processes before gating.

---

## 11. Failure inventory — the wider record

Gathered from both runs' logs, incident files and issues. Each record: what, when, the circumstances,
how it was detected, what was done, and where to read it.

### 11.1 Sessions hanging, and the single escalation that exists

- **`council-advisor` panes hung for about forty minutes and never returned.** `2026-09-02` 06:27 to
  06:54Z, in the records-final lane of the previous run. Detected only by the absence of output. The
  lane was killed and restarted. `runs/20260831-184751/logs/harness.log:520,529`.
- **The stale-heartbeat nudge is the only escalation the engine has.** Observed peaks before a nudge
  fired: 2808 s (47 minutes) in the current run, and 44791 s (about 12.4 hours) in the previous one,
  with a single orchestrator and no lanes. Nothing stronger is triggered at any ceiling.
  `runs/20260911-212252/logs/watch.log:21`; `runs/20260831-184751/logs/watch.log:68`.
- **A subagent retried `docker desktop start` for 33 m 31 s against an unreachable daemon**, spending
  184k tokens, and was indistinguishable from working by heartbeat. `2026-08-31T20:12:26Z`. Found by
  reading the log by hand. `runs/20260831-184751/logs/context-watch.log:50`.
- **Sessions going idle and needing a forced prompt**: `v-drift-loop` three times about thirty minutes
  apart, `v-length-more2` after twenty-seven minutes idle. `2026-09-06/07`.
  `runs/20260831-184751/logs/unwedge.log:39-42`.

### 11.2 Instructions that were typed and never submitted

- A nudge on `v-phase-12` left typed but unsent. `2026-09-12T03:24:48Z`.
  `runs/20260911-212252/logs/harness.log:72-73`.
- **Two real operator instructions — `push master` and `carry on with the queue` — sat unsubmitted in
  two sessions' input boxes while the engine log recorded them as nudged.** `2026-09-01T12:42:58Z`.
  Found by manual review; the engine had no way to know. `runs/20260831-184751/logs/context-watch.log:589`.
- A thirteenth consecutive stranded `continue` on the orchestrator's input line, sitting beside a live
  Playwright run it could have corrupted. `2026-09-12T09:05Z`.
  `runs/20260911-212252/logs/context-watch.log:368`.

### 11.3 Detector false positives, and the attention file

- **`STALLED` raised against demonstrably healthy sessions eight or more times across about seven
  hours**, with the cause recorded as the attention file being rebuilt every cycle so corrections
  never persisted. `2026-09-12T07:27` to `14:07Z`.
  `runs/20260911-212252/logs/context-watch.log:300,320,414-419,421,461-462,591`.
- `state/attention.tmp` found truncated to zero bytes on every pass.
  `runs/20260831-184751/logs/context-watch.log:5587-5698`.
- **A marker detector globbed the wrong directory** (`state/` instead of `markers/`) and silently
  reported zero markers for several cycles. `2026-08-31T22:18:40Z`.
  `runs/20260831-184751/logs/context-watch.log:128`.
- **Four detector false positives fixed in one day**: a non-ASCII space misread as an unsent nudge; a
  validator's own quoted warning text (`harness:council-advisor subagents hang`) triggering a full
  alarm; a dialog's shape alone treated as proof of a captive session; and a whole-screen scan
  matching a dialog quoted inside a session's own report. `2026-09-11T21:28` to `23:00Z`.
  `runs/20260911-212252/logs/context-watch.log:3,34,48,50`.
- **A probe that could never succeed and never complained.** BSD `find -newermt "-10 minutes"` errors
  out, and with stderr routed to `/dev/null` it returns empty every time — which would have declared
  every healthy session idle for ever. Caught by cross-checking against files known to be minutes old;
  switched to `-mmin`. `2026-09-12T01:29:00Z`. `runs/20260911-212252/logs/context-watch.log:120`.
- **A parser that silently substituted a tighter ceiling.** When `timeout 1800s` scrolled off a
  forty-line capture window, the timeout parser fell back to a 900 s default, tightening the stall
  ceiling from 33 to 18 minutes. `2026-09-12T01:42:31Z`.
  `runs/20260911-212252/logs/context-watch.log:128`.

### 11.4 Verification and merges that reported success while doing nothing

- **GSD's verify stage was silently skipped for phases 14 to 18**, each `NN-VERIFICATION.md`
  self-attributing with `verified_by: the lane that built the phase`. The cause was an orchestrator
  generalising a narrow `council-advisor` warning into "every GSD agent". No automated check caught
  it; manual review did. `runs/20260911-212252/OWNER-ACTIONS.md:22-25`, `logs/harness.log:142-143`.
- **Phase 21 merged before its validator ran.** `2026-09-13T03:26:23Z`; validation run after the fact.
  `logs/harness.log:209`.
- **A records-drift check across seven handoff files exists only as prose — nothing runs it.**
  Separately it reports a false clean (`OK, 0 files compared`) when run from a subdirectory, and a
  tracked-tree sweep claimed exit 0 against 1242 bytes of real diff. Issues `#50`, `#325`, `#324`.
- A fourth gate failed on a publish-at merge and was attributed to contention rather than the change;
  no push was made. `2026-09-04T22:04:13Z`. `runs/20260831-184751/logs/harness.log:1157`.

### 11.5 Memory

- **The owner's own container was OOM-killed by two concurrent validator builds** on an 8 GB Docker
  VM. Builds started `03:28:30Z`, the container was dead by `03:29:01Z`, restarted `04:01:35Z`,
  verified healthy about `06:16Z`. Detected only by correlating timestamps with
  `docker inspect OOMKilled=true` — there was no live alert.
  `runs/20260911-212252/state/INCIDENT-owner-app-oom-v-phase-21.md:1-7`, `OWNER-ACTIONS.md:37-50`.
- **A memory-truncated test run reported a clean-looking result.** 346 passed, 0 failed — caught only
  by arithmetic: 346 plus 35 never-reached does not equal the declared 382, and the missing test was
  not even in the never-reached list. It followed host memory pressure (~75 MB free, 2378 M of 3072 M
  swap) that had killed the watcher's own collection task eight minutes earlier. `2026-09-12T09:32Z`.
  `runs/20260911-212252/logs/context-watch.log:375,381`, `logs/harness.log:115`.
- **The owner's default stack was destroyed** by a `docker compose down -v` run with no
  `COMPOSE_PROJECT_NAME` exported, which landed it on the default project instead of a lane project.
  `2026-09-11` about 22:51 to 22:53Z. Detected only afterwards from image and volume timestamps; the
  actor was never identified, and a session had refused that exact action as owner-only two minutes
  earlier. `runs/20260911-212252/state/INCIDENT-default-stack.md:9-84,56-59`.

### 11.6 Self-sustaining loops

- **An 85-minute loop that nothing internal could break.** The deterministic watch matched what looked
  like a usage-cap banner inside the orchestrator's **own wrapped prose**, pressed Escape and sent
  `continue` about every sixty seconds; each zero-second turn left the screen unchanged, so the same
  text matched again, for ever. Two things compounded it: the human-notification watchdog had already
  exited ("run finished") and was never restarted, and `state/attention.tmp` was truncated to zero
  bytes on every pass. `2026-09-06T21:53:15Z` to `23:21:39Z`. **Nothing internal detected it** — it
  ended when an external `SIGTERM` reached the orchestrator, and a fresh session started fourteen
  seconds later. `runs/20260831-184751/logs/context-watch.log:5587-5698`; line 5620 reads
  `NO ONE IS BEING TOLD`.
- A dead run flagged `STOPPED present with no run.complete — treating as an accidental teardown, not a
  finish` every three minutes **for about five days**, 1085 times, unresolved.
  `runs/20260831-184751/logs/overnight-supervisor.log:972-3436`.
- An unwedge process polled `run is stopped — holding` every 180 seconds for about 32 minutes while
  doing nothing. `runs/20260831-184751/logs/unwedge.log:2-37`.

### 11.7 Accounts, tokens and the usage read

- **Usage was measured against the wrong account**: "my limits position was measuring the wrong
  account", with the building account reading 94% weekly on that wrong account. `2026-09-04T15:54:41Z`.
  `runs/20260831-184751/logs/harness.log:1032`.
- `weekly_all=unreadable%` recurred across many separate days — six consecutive ticks on
  `2026-09-06T03:01-03:19Z`, more at 08:36 and 22:48-23:03, single ticks on the 9th, 10th and 11th, and
  once in the current run at `2026-09-12T11:20:36Z`. Grep `unreadable` in either run's
  `overnight-supervisor.log`.
- **The usage endpoint returned `authentication_error` for an extended stretch**, blinding every cap
  read, with nobody re-authenticating. `2026-09-02T13:52-15:14Z`.
  `runs/20260831-184751/logs/context-watch.log:1358-1359,1414,4878`.
- **A three-step regression in the supervisor's pause path.** Its wall-clock fallback, used when the
  quota API is unreadable, was pinned to a fixed past epoch, so an unreadable read resumed a paused run
  immediately (`#65`). The fix put the new epoch lookup between the two pause writes, so a restart
  landing in that window read `STOP` as a manual owner stop and exited instead of resuming (`#73`).
  After the writes were serialised, the `STOP` write is still unconditional on the marker write
  succeeding, so a failed marker write leaves an unattributed `STOP` on disk (`#82`, open).

### 11.8 Worktrees, branch names and over-matching patterns

- GSD computed a branch name one word off the real lane branch — it dropped `SCRIPTS` — and left alone
  would have cut a fresh branch from `origin/master` and lost the merged master tip.
  `2026-09-13T06:35:02Z`. `runs/20260911-212252/logs/harness.log:237`.
- The spawn validator caught `w-phase-5.sh` mislabelled: its session id, log and prompt all said phase
  5 while the script cd'd into the **phase-4** worktree. Rejected twice before a correct spawn.
  `2026-09-01T17:49:38Z`. `runs/20260831-184751/logs/harness.log:213,215`.
- A lane slug reused from an earlier wave spawned a worker into a stale worktree with a stale prompt.
  `2026-09-06T14:15:39Z`. `runs/20260831-184751/logs/harness.log:2287`.
- **`pkill -f 'playwright test'` killed an unrelated lane**, because every lane's own prompt text
  contains that literal string, so `pgrep`/`pkill` over-match sessions rather than suites.
  `2026-09-05T12:11:51Z`; the killed worker was respawned 83 seconds later.
  `runs/20260831-184751/state/incident-reading-measure-pkill.md:8-55`.

### 11.9 Commit gates that could not fail loudly

All from the project's issue tracker; each was found by mutation rather than by the gate failing.

- **The magic-value and credential checker self-tests assert the checker as it sits on disk, not the
  version being committed.** A stage-then-restore commits a dead rule at exit 0, and
  `git rm --cached` on either checker commits its own deletion at exit 0 with no self-test run at all.
  `#290`, `#298`.
- Three separate mutation-discovered ways to disable a checker mechanism while `--self-test` stays
  green. `#72`, `#69`, `#75`.
- The credential checker silently ignores a bare path argument, so a sweep run without `--scan` reads
  clean over files it never opened; refuses files larger than 32 MB as "unreadable" and leaves them
  silently unscanned; and scans the wrong file when a staged file is literally named `0:<path>`.
  `#293`, `#258`, `#261`.
- Gates 4 and 5 swallow a failed `docker inspect` or `docker ps` and then release the network or mark
  the run finished on the swallowed error. Gate 5's six-hour rule reads a UTC timestamp as local time
  and never fires on this machine. `#167`, `#168`, `#160`.
- **A lane worktree can commit with no pre-commit gate at all** — `npm ci --ignore-scripts` skips husky
  entirely. `#122`.

### 11.10 Secrets that reached a place nobody scans

- **Two local role passwords printed in clear text into a session transcript** by Playwright's
  `--trace on` while diagnosing a timeout. Found by manual review afterwards; **no automated secret
  scan covers tool output or transcripts.** Trace files were deleted, nothing was committed or pushed,
  and the owner was asked to rotate the credentials.
  `runs/20260911-212252/OWNER-ACTIONS.md:27-30`, `logs/harness.log:174`.
- A Sentry breadcrumb recorded the address of every outgoing request, and one such address was a Slack
  webhook secret. `#83`.

### 11.11 Smaller items, recorded but not expanded here

About 150 orphaned Docker volume pairs left by a dead prior run; a ticket-filing id race (`#273`,
`#276`); a spawn-guard and prompt-template collision that produced a false validator finding
(`OWNER-ACTIONS.md:622-630`); retry-budget against clock mismatches in end-to-end hooks (`#322`,
`#289`, `#54`, `#55`, `#77`); and repeated watchdog and supervisor self-restarts.

---

## 12. Second pass — what a separate sweep found that the first did not

### 12.1 Typing into a session: three more ways it fails

- **A 149-minute stall in the previous run** because `harness-term.sh send`'s Enter never landed on the
  `p3-tidy` pane. The lane had actually finished seventy minutes earlier. **Nothing detected it** — the
  owner eventually pushed master himself. `runs/20260831-184751/DECISIONS.md:191`.
- **`send` fails silently above roughly 200 characters.** In the previous run an ~1100-character
  message produced no error and never appeared; a ~450-character version of the same message landed.
  `docs/open/supervisor/ORCH-HANDOFF.md:203`; `runs/20260831-184751/DECISIONS.md:359`.
- **A recovery attempt destroyed the instruction it was recovering.** `key enter` did nothing, then
  `send " "` cleared the line without submitting — the pending text ("fix WATCHER-PROMPT.md…") was
  confirmed absent from the transcript afterwards.
  `runs/20260911-212252/logs/context-watch.log:49`.

### 12.2 Detectors reading the wrong thing

- **A status-line regex missed decimal model versions.** `Opus 4.8` did not match, so the watch fell
  back to a broken capture window for three validators without saying so.
  `runs/20260831-184751/logs/context-watch.log:1263,1294`.
- **A merge-equivalence gate false-failed** by diffing the wrong pair of trees — 554 unrelated files —
  instead of comparing merge-introduced against branch-changed paths.
  `runs/20260831-184751/DECISIONS.md:194`.
- **A self-patch script reported `SYNTAX OK` while its `sed` anchor never matched and nothing was
  written.** Recorded as the third such case that day.
  `runs/20260831-184751/logs/context-watch.log:1376`.
- **A Playwright spec importing `src/instrumentation.ts` crashes at collection and reports
  `No tests found`** — which reads as zero tests rather than as a failure.
  `runs/20260911-212252/DECISIONS.md:39`.

### 12.3 The watch's own collector died repeatedly

`context-watch`'s cycle-collection task was **OOM-killed twenty-six or more times in this run**, with
host swap down to about 63 MB free. Fixed around cycle 380 by moving the collection into the
foreground. `runs/20260911-212252/logs/context-watch.log:16,24,432,2266,2287`.

The staleness nudge count for the run, counted over the same logs: **33 nudges between
`2026-09-11T22:49Z` and `2026-09-13T06:29Z`**, across phases 10 to 22.

### 12.4 Environment that detached processes do not inherit

- **`harness-limits.sh verdict` returns `UNKNOWN` unless it is called with `HARNESS_ROLE=<role>`
  prefixed**, because a session's environment deliberately withholds the usage token.
  `ORCHESTRATION.md:279-291`.
- **Three detached scripts must export the `gh` account themselves** — `overnight-supervisor.sh`,
  `harness-watchdog.sh` and `harness-unwedge.sh` — because launchd and `nohup` start with no
  environment and `gh`'s default configuration does not resolve this repository.
  `ORCHESTRATION.md:229-232`.
- **A weekly-usage figure can move without any usage changing.** When the supervisor was repointed to
  a different config dir mid-run, the weekly reading dropped sharply **from the repointing alone**. `runs/20260911-212252/logs/overnight-supervisor.log:658`.

### 12.5 Two more loops, and a channel that forked

- A **45-minute false-positive rate-limit-banner loop** on a healthy orchestrator in the previous run,
  re-detecting and re-issuing resume kicks about every 66 seconds.
  `runs/20260831-184751/logs/harness.log:2630-2769`.
- **`QUESTIONS.md` and `JOURNAL.md` forked into a worktree's own copy**, and a real owner-facing
  question sat there invisibly for an hour. `ORCHESTRATION.md:489-494`.

### 12.6 A fix that lives only in the installed copy

The ticket-id allocator had no locking, so concurrent `add` calls could land on the same id and both be
told they succeeded. **The fix landed only in the installed plugin copy and not in the source
repository, so it reverts on the next sync.** `runs/20260831-184751/OWNER-ACTIONS.md:598-620`;
issues `#37`, `#169`.

Related and still live: `harness-tickets.sh done` leaves a previously blocked issue holding two state
labels, because `blocked` is never removed. Seen twice.
`runs/20260911-212252/DECISIONS.md:30`.

### 12.7 An audit log that recorded events that never happened

A security review of a single API read found **26 refusal events in the audit log that never
occurred**. `runs/20260831-184751/OWNER-ACTIONS.md:333-345`.
