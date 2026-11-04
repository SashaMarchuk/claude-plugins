# L5 — Acceptance and live canary

**Layer:** L5 · **Date:** 2026-09-19 · **Spike:** harness-rebuild
**Requirement source of truth:** `../../round-1/ANALYSIS-01.md`
**Grounding:** `ground-testing-agentic-systems.md`, `ground-evaluating-llm-decisions.md`,
`ground-what-exists-here.md`, `ground-failure-corpus.md` (all four read in full for this document)

**Evidence labels.** **[V]** = I read the file, ran the command, or grepped the binary in this
session. **[C]** = asserted by a document I read (FIELD-NOTES, ANALYSIS-01, a ground doc) and not
re-derived here; where a ground doc marks its own claim VERIFIED, that is still **[C]** for me and
I name the section so it can be chased. **[I]** = my reasoning from the above, flagged so it can be
argued.

---

## 0. Headline

Every layer below this one tests the orchestrator against doubles. L5 is the only layer where the
real CLI, the real account, the real board, real wall-clock time and the operator's real machine are
in play — and therefore the only layer that can fail from a **fidelity gap**, where the double and
reality disagree. The ground research measured exactly such a gap: a `read`-loop fake agent submits
text stranded on its input line, and real Claude Code does not [C: what-exists-here §5.1, V10]. A
suite built only on doubles would have "proved" the nudge works, and five operator instructions were
lost to that belief [C: FIELD-NOTES §1.3, §11.2].

L5 has no oracle for the work. R1-01 settles that: *"конкретної якоїсь вимірюваної штуки тут не може
взагалі бути"*, and R1-13 puts verification of the work inside the user's configured process. So L5
does not ask **"was the work good?"** It asks the one question that is the orchestrator's own
business and that the entire failure record says it got wrong:

> **Is every claim the orchestrator made about its own actions independently true?**

Four of the corpus's largest families — F-07 (log says "nudged", nothing delivered), F-29 (merge
prints `Already up to date`, nothing moved), F-36 (`SYNTAX OK` while the anchor never matched),
F-52 (26 audit-log refusals that never happened) — are one defect with four faces: *an operation
that reports its attempt succeeded rather than that its effect occurred* [C: failure-corpus §4
F-36 note]. L5 is that defect's acceptance test, applied to a whole run.

The mechanism is a **post-hoc reconciliation audit**: an auditor that shares no code with the runtime
re-derives what happened from primary sources the orchestrator does not write — session transcripts,
first-party Claude Code hook receipts, `git reflog`, the board's own API, the OS process and container
tables, the usage response bodies — and diffs that against the orchestrator's ledger. Divergence is a
run failure regardless of how the work went. The audit is free, deterministic, runs in seconds, and
runs on every real run forever, not only on canaries.

Three things this buys that no cheaper layer can:

1. **A verdict the owner can act on at 08:00** that is not the orchestrator's own opinion of itself.
2. **A promotion rule with teeth** — the change classes that require a canary, and how many.
3. **A corpus that grows itself.** A failed real run leaves the repository's own test suite red, with
   the evidence already captured as a fixture. That is the direct answer to F-49: a documented fix
   that was still missing from the source thirteen days later [C: failure-corpus §1.3].

---

## 1. What I verified on this machine for this document

| # | Fact | How |
|---|---|---|
| L5-V1 | `PLUGINS=(clickup g-event ultra ultra-analyzer claude-migrate find-call log-time harness ig-dm-export-analyzer interview-handoff)` — `tests/run-all.sh:15`. No `orchestrator`. A plugin absent from this array is invisible to the 475-test suite. | `grep -n 'PLUGINS=' tests/run-all.sh` |
| L5-V2 | Claude Code is **2.1.278**, installed as `~/.local/bin/claude → ~/.local/share/claude/versions/2.1.278` (a 217 MB binary; `claude` on the interactive PATH is a shell function, not a file) | `claude --version`, `ls -l`, `realpath` |
| L5-V3 | The hook event names **`PreCompact` (28), `PostCompact` (27), `UserPromptSubmit` (41), `SubagentStop` (28), `SessionEnd` (38)** are all present in that binary | `grep -ac <name> <binary>` |
| L5-V4 | `plugin eval` and the grader-type string `regex \| tool_order \| tool_used \| file_exists \| llm \| baseline` are present in the binary | `grep -ao` |
| L5-V5 | Present: `tmux`, `jq`, `gh`, `shellcheck`, `python3`, `sqlite3`, **`memory_pressure`** (`/usr/bin/memory_pressure`), **`shlock`** (`/usr/bin/shlock`). **Absent: `flock`.** | `command -v` over each |
| L5-V6 | The evidence summary the task names — `…/scratchpad/context/harness-evidence.md` — **does not exist**; `context/` is an empty directory. All four ground docs independently record the same [C]. Everything attributed to the 34-hour run here comes from `FIELD-NOTES.md` via those docs. | `ls -la` |

**L5-V3 is load-bearing.** It means the delivery receipt and the compaction receipt this design
depends on are *first-party signals written by Claude Code itself*, not by the orchestrator — which is
precisely what makes them unforgeable by the component under audit.

---

## 2. What L5 inherits, and what it must not duplicate

L5 assumes the tiering the ground research converged on [C: testing-agentic-systems §15;
what-exists-here §7.2]. Sibling layer documents L1–L4 did not exist when this was written (`ls` of
`research/eval/` shows only the four ground docs and `probes/`) [V], so the boundary below is stated
as an **assumption to reconcile**, not as a fact about what siblings wrote.

| Layer | What it owns | Cost | Gates |
|---|---|---|---|
| L1 static | `bash -n`, `shellcheck`, JSON/YAML validity, config schema, no-absolute-binary-paths lint, no-bare-`date` lint | < 5 s | commit |
| L2 unit | `decide(world) → plan` table tests, detector corpus over recorded screens, parsers, clock boundaries, config precedence | < 30 s | commit |
| L3 hermetic integration | scenario runner, fake agents, fake board, cassettes, virtual clock, crash-at-step-N, **concurrency with `TEST_DELAY_*` window-widening**, golden decision logs | 1–3 min | commit |
| L4 mutation + real-environment | curated mutations must fail their named tests; real tmux round-trip, real git worktrees, Docker isolation, CLI conformance | ~1 min / 5–15 min | pre-release |
| **L5 (this)** | **preflight acceptance gates, the live canary, the reconciliation audit, the morning artifact, the promotion rule, the corpus feedback loop** | 40 s free + 30 min or 4 h real | **the run itself** |

**L5 does not re-test logic.** If a behaviour is assertable against a double, it belongs in L2 or L3
and L5 must not spend real money on it. L5 exists for the four things doubles structurally cannot
produce: real TUI line discipline, real quota state, real wall-clock duration, and the operator's own
machine state. Everything else L5 touches, it touches only as a *conservation identity over evidence*
— which is free.

**One inherited hazard L5 must fix before it can run at all** [C: what-exists-here §3.1, V6]:
`tests/run-all.sh` turns `set -e` on at lines 41 and 50 and then greps for `PASS=`; a runner that
prints no `PASS=` line kills the whole aggregate silently and every later plugin never runs. An L5
runner that can abort mid-way is exactly the shape that triggers it. Therefore:

> **RUNNER-CONTRACT.** `plugins/orchestrator/tests/run.sh` installs an `EXIT` trap that prints
> `PASS=<n> FAIL=<m>` unconditionally, including on abort, and asserts a **committed minimum
> assertion count** before exiting 0. A suite that silently loses tests reports red, not green.
> This is F-32's conservation identity pointed at our own suite [C: failure-corpus F-32;
> what-exists-here §3.3].

---

## 3. The one design requirement L5 imposes on the runtime

Everything in this document rests on a single contract. Without it, L5 degenerates into reading the
orchestrator's own diary.

> **LEDGER-CONTRACT.** The orchestrator appends one record per **effect** to `<run>/ledger.jsonl`.
> No record may claim an effect without an `evidence` block naming a **primary source the
> orchestrator does not write**. A component that cannot name one must emit
> `kind: "…", verified: false` — which the audit counts as an unverifiable claim, and unverifiable
> claims are a failure, not a pass.

Record shape:

```json
{
  "id": "01JBQ7K3M2ZC8Y4N6F1TQW9XVR",
  "ts": "2026-09-19T03:14:07.221Z",
  "tick": 412,
  "actor":  {"component":"watch","pid":48211,"run":"20260919-021500","host_boot":1758243001},
  "kind":   "delivery",
  "target": {"session":"w-t17","adapter":"claude-code","tty":"/dev/ttys021"},
  "claim":  {"text_sha256":"9f2c…","bytes":312},
  "evidence": {
    "source": "hook:UserPromptSubmit",
    "path": "<run>/receipts/w-t17/01JBQ7K3M2.json",
    "observed_at": "2026-09-19T03:14:07.804Z",
    "digest": "9f2c…"
  },
  "verified": true
}
```

**Nine effect kinds and their primary sources.** The middle column is what makes the audit possible;
none of it is written by orchestrator code.

| `kind` | Claim | Primary source (not written by the orchestrator) | Probe |
|---|---|---|---|
| `delivery` | text reached a session as a user turn | **`UserPromptSubmit` hook receipt** [L5-V3] + the session's own `.jsonl` transcript | `probe-transcript.sh` |
| `compaction` | a session compacted | **`PostCompact` hook receipt** [L5-V3] + context % before/after read off the status line | `probe-compact.sh` |
| `spawn` / `close` | a session started / ended | OS process table (pid + boot time), tmux session list, **`SessionEnd` hook receipt** [L5-V3], transcript first/last record | `probe-process.sh` |
| `ref_move` | a merge/push moved a ref | `git reflog` of the target ref + `git merge-base --is-ancestor` | `probe-git.sh` |
| `board_write` | a status/comment landed | the board's own API read back (`gh issue view --json labels,comments`) | `probe-board.sh` |
| `quota_read` | a usage verdict | the raw response body (hashed, redacted) + the **account identity label** it was taken under | `probe-usage.sh` |
| `notification` | the human was told | the channel's own identifier read back (message ts / id / file mtime + digest) | `probe-notify.sh` |
| `world_change` | a resource created/destroyed | `docker ps -a --filter label=orch.run=<id>`, `git worktree list`, the recorder's argv log | `probe-world.sh` |
| `step` | a declared process step reached a terminal state | the step's own artefact + its producer identity | `probe-step.sh` |

**Two rules that make the ledger honest, both from the corpus:**

- **Emit from the observation site, never from the attempt site.** The record is written *after* the
  evidence is read. F-07: the log line was written from the attempt [C]. F-52: 26 refusal events from
  one real read [C].
- **Every mutating operation reports the observed effect.** F-29's merge, F-36's edit, F-39's
  compaction all reported exit status instead of effect [C]. A `ref_move` record carries the before
  and after SHA; an edit carries the file digest before and after.

**`n/a` must be declared in advance.** N2 allows runs with no repository, no tests and no build. A
profile declares which probes are `n/a` (e.g. `probe-git: n/a` for a non-code run). An **undeclared**
`n/a` at audit time is `UNVERIFIABLE`, never a pass. This is the empty-is-not-clean rule (F-33, F-35,
F-47, F-59 — one rule, four corpus entries) applied to configurability itself.

---

## 4. Mechanism — layout, formats, entry points

### 4.1 Directory layout

```
plugins/orchestrator/
  acceptance/
    preflight/
      checks/A-01-tool-dialect.sh … A-14-install-drift.sh   # one file per gate
      manifest.json                                          # id → {file, required_by, n/a-able}
    canary/
      profiles/C1-smoke.yaml  C2-night.yaml  C1-nocode.yaml
      queue/                                                 # committed canary tickets
      faults/K-schedule-C2.yaml                              # the fault schedule
      faultd.sh                                              # the injector; runs OUTSIDE the run
    audit/
      auditor.sh                                             # entry point; imports nothing from ../../bin
      probes/probe-transcript.sh … probe-step.sh
      identities/V-01.sh … V-10.sh                           # conservation identities
      isolation.test.sh                                      # asserts audit/ sources no runtime lib
    report/
      schema/run-report.schema.json
      render.sh                                              # json → RUN-REPORT.md, never hand-written
    metrics/
      baseline.json                                          # committed; the promotion baselines
      waivers.json                                           # accepted regressions, printed until removed
      history/<run-id>.json
    corpus/
      ingest.sh
      index.json                                             # signature → entry, occurrences, test id
      entries/F-<n>.md
      fixtures/F-<n>/                                        # captured primary evidence
    mutations/
      M-A07-delivery-no-readback.mut … (16 files)
  tests/
    run.sh                                                   # L1–L3 + L5's own free self-tests
    regressions/F-<n>.sh                                     # auto-filed stubs; red until written
```

### 4.2 Entry points

| Command | Cost | Exit codes |
|---|---|---|
| `orchestrator:preflight [--profile P]` | free, 20–40 s | 0 ok · 4 refuse-to-start (one or more gates red) |
| `orchestrator:canary <C1\|C2\|C1-nocode>` | real: 30 min or 4 h | delegates to the run; the audit gives the verdict |
| `orchestrator:audit <run-id>` | free, 10–25 s | 0 CLEAN · 1 DEGRADED (a dial regressed) · 2 FAILED (a gate identity broke) · 3 UNVERIFIABLE |
| `orchestrator:promote <run-id>` | free, < 2 s | 0 promoted · 5 refused (prints which rule) |

`orchestrator:run` **calls `preflight` itself and refuses to start on exit 4.** Not a warning. That is
cross-cutting requirement 5 ("verify before you run" — R1-04, R1-07, R1-17, Д4) made executable.

### 4.3 How a check is written

House dialect, so it slots into `run-all.sh` unchanged [C: what-exists-here §2.5]. Every check is a
flat bash file exporting one function, with its **mutation recorded in a comment beside it** — a
check with no recorded mutation is presumed vacuous and is rejected at review.

```bash
# acceptance/preflight/checks/A-07-delivery-roundtrip.sh
# ASSERTS: for each configured (adapter × backend), a nonce sent to a live session appears as a
#          user turn in that session's own transcript, and the byte ceiling is DISCOVERED not assumed.
# EVIDENCE: hook:UserPromptSubmit receipt + the session transcript .jsonl (neither written by us)
# MUTATION: M-A07-delivery-no-readback — make deliver() return Delivered on transport exit 0.
#           A-07 must go red. (Old suite: M1/M6 passed 51/51 — failure-corpus §1.2.)
# CATCHES:  F-01 F-02 F-03 F-04 F-05 F-06 F-07 F-09 F-70
a07_delivery_roundtrip() {
  local adapter backend nonce rc=0
  for adapter in $(cfg_list '.adapters'); do
    for backend in $(cfg_list ".adapters.$adapter.backends"); do
      nonce="ORCH-A07-$(rand_hex 8)"
      sess=$(adapter_spawn "$adapter" "$backend" --probe) || { bad A-07 "spawn $adapter/$backend"; rc=1; continue; }
      adapter_deliver "$sess" "$nonce" >/dev/null 2>&1
      # the assertion is NOT the exit status of the send
      receipt_wait "$sess" "$(sha256 "$nonce")" 20 \
        || { bad A-07 "$adapter/$backend: send reported success, nothing arrived"; rc=1; }
      # discover the ceiling; never assume it
      ceil=$(a07_length_sweep "$sess" 10 100 200 500 1000 1023 1024 1100 2000 5000)
      [ -n "$ceil" ] && record_capability "$adapter.$backend.max_line" "$ceil" \
        || { bad A-07 "$adapter/$backend: ceiling not discovered"; rc=1; }
      adapter_close "$sess"
    done
  done
  [ $rc -eq 0 ] && ok "A-07 delivery round-trip + ceiling discovery"
  return $rc
}
```

The sweep values are not arbitrary: the ground research drove tmux and found the boundary at exactly
**1023 delivered / 1024 silently dropped** — the tty canonical-mode limit `MAX_CANON` — and notes that
FIELD-NOTES' folkloric "~200 characters" was a guess at the same underlying cause
[C: testing-agentic-systems §11, V8]. **The ceiling is discovered and recorded per backend at
startup, never hardcoded**, because R1-11 multiplies backends and each may differ.

### 4.4 How it fails loudly

Five mechanisms, because the record shows every single-channel failure signal eventually going quiet
[C: F-41 — the notifier exited and its silence read as calm; log line `NO ONE IS BEING TOLD`].

1. **Refusal, not warning.** Preflight exit 4 stops the run. No `--force` flag exists for gates
   A-03, A-06, A-07, A-08, A-09 (accounts, control file, delivery, single-instance, red line).
2. **`UNVERIFIABLE` is its own verdict** and is not a pass anywhere in the promotion rule.
3. **The failed run leaves the repo red.** §12: the corpus ingester writes a registered, failing
   regression stub. `bash tests/run-all.sh` fails until a human writes the assertion.
4. **The notification is heartbeat-verified.** The notifier's own liveness is asserted on a schedule
   and its absence escalates by a second route (F-41). A run that ends with no notification and no
   second-route alert is `UNVERIFIABLE`.
5. **Debt is printed until discharged.** An acknowledged-but-unwritten regression stub and every
   entry in `waivers.json` appear in the "needs you" section of *every* subsequent morning artifact.

---

## 5. Scenarios

Four families. Each carries **id · name · precondition · trigger · expected · assertion · catches**.
"Catches" names the entry from `ground-failure-corpus.md` that this scenario would have caught.

### 5.1 Family A — preflight acceptance gates (free, before every real run)

**A-01 · Tool-dialect fingerprint.**
*Pre:* configured adapters and probes resolved. *Trigger:* preflight.
*Expected:* every external binary resolves to a known implementation and every flag actually used is
accepted, under **both** the interactive `PATH` and `env -i` with the declared minimal environment.
*Assert:* for each binary, `resolve_bin` names it, a positive-control invocation succeeds, and the
two environments agree; disagreement is a refusal naming the binary.
*Catches:* F-20 (detached processes inherit no environment; silent degradation), F-61 (BSD
`find -newermt` with stderr to `/dev/null` would have declared every healthy session idle for ever),
and the machine-specific hazards the ground work found here: `find` → `bfs` interactively but
`/usr/bin/find` under `env -i`, `grep` shadowed, `/tmp` a symlink `find` will not descend, BSD `date`
[C: testing-agentic-systems §14].

**A-02 · Every declared step resolves and dry-runs.**
*Pre:* a configured process (GSD, superpowers, or a custom step list — R1-03, no mixing).
*Trigger:* preflight. *Expected:* each declared step resolves to something runnable and the
resolution is recorded with what it resolved to. *Assert:* an unresolvable step is a refusal at
preflight, not a failure at 03:00; the resolution record is written to the run header.
*Catches:* F-34 (a records-drift check that existed only as prose and never executed), F-65 (a
worktree that could commit with no pre-commit gate at all).

**A-03 · Per-account authenticated call, labelled, matched to role.**
*Pre:* R1-07 account assignments (API key / subscription / profile). *Trigger:* preflight.
*Expected:* for every configured account an authenticated call succeeds, and the returned record
carries the account identity. *Assert:* presence of a key is **not** sufficient; a `401` fails the
start; a verdict whose account label ≠ the role's account is a hard error, not a warning.
*Catches:* F-17 (quota measured against the wrong account, 94% weekly on a pool nothing ran on),
F-18 (82 minutes of `authentication_error` with nobody re-authenticating).

**A-04 · Notification channel round-trip.**
*Pre:* R1-17 channel configured. *Trigger:* preflight. *Expected:* a nonce is sent and read back
through the channel's own identifier. *Assert:* configuration-checking does not satisfy this; a
broken channel refuses the run. Also assert the notifier's heartbeat mechanism is armed.
*Catches:* F-41 (the human-notification watchdog had exited and was never restarted, during the
85-minute loop).

**A-05 · Board reachable, statuses sufficient, write read-back.**
*Pre:* R1-04 local registry or connected board. *Trigger:* preflight. *Expected:* the board has the
minimum status set the configured process needs (names user-overridable), and a scratch item can be
written and read back. *Assert:* a status the process needs and the board lacks is a refusal; a write
that does not read back is a refusal. *Catches:* F-50 (`done` leaving a `blocked` label behind — the
read-back is what makes state single-valued observable).

**A-06 · Control file — one absolute path, read-only inbound.**
*Pre:* Д12/Д7/R1-07 watched control file; Д4 default of one worktree per task.
*Trigger:* preflight. *Expected:* the inbound path resolves to the **same absolute location** from
the repo root, a subdirectory and a worktree, and the orchestrator can read it while holding no write
handle. *Assert:* run one tick against a **read-only** inbound file and require success — a
truncating implementation cannot achieve that; and assert a path that resolves differently from two
cwds is rejected at configuration time.
*Catches:* F-10 (the control file rebuilt from scratch every tick, destroying every external write
all night), F-12 (`QUESTIONS.md` forked into a worktree copy; an owner-facing question sat invisible
for an hour).

**A-07 · Delivery round-trip and ceiling discovery per adapter × backend.** (code in §4.3)
*Catches:* F-01 … F-07, F-09, F-70.

**A-08 · Single-instance lock: one winner, loser exits clean and touches nothing.**
*Pre:* R1-10 stated as an absolute; no guard exists in the previous generation [C: failure-corpus
§1.4]. *Trigger:* two starts. *Expected:* exactly one proceeds. *Assert:* 50 concurrent rounds, one
winner each; the loser exits non-zero with a reason **and its world-change probe records zero
targets**; a `SIGKILL`ed holder's lock is reclaimable, a `SIGSTOP`ped holder's is not (a paused
orchestrator inside a quota wait must not be declared dead); a reused pid does not read as alive.
Use `mkdir` or `noclobber` — **`flock` is absent on this machine** [L5-V5], `shlock` is present.
*Catches:* F-13 (two orchestrators, "нескінченний цикл оркестраторів"), F-45 test 4 (liveness keyed
on a `pgrep` pattern that matches the session whose prompt contains it).
*Caveat, and it is the sharpest methodological result in the ground work:* a naive check-then-write
lock **passed five rounds of 100 concurrent acquirers** and only broke when a delay was injected
between check and write (winners 1 → 5 → 13 → 26 as the delay went 0 → 1 ms → 5 ms → 20 ms)
[C: testing-agentic-systems §9.4]. **The window-widening version belongs in L3, not here.** A-08 is a
smoke gate; it must not be read as proof of exclusivity.

**A-09 · The red-line file is read by every role's rendered prompt.**
*Pre:* R1-15, one text file, mandatory reading for every agent, no enforcement machinery.
*Trigger:* preflight. *Expected:* the file exists, is readable, and its content appears in the prompt
**as produced by the real renderer** for every configured role. *Assert:* render each role's prompt
through the production renderer and assert the red-line content is present with a digest match.
*Vacuity warning:* grepping a template file for an `{{include}}` token is exactly the H-33 shape — a
test of a comment [C: what-exists-here §4.1]. The assertion must consume the renderer's output.
*Catches:* the class F-34 belongs to (a rule that exists only as prose).

**A-10 · Lane environment: worktrees, services, non-colliding port blocks.**
*Pre:* Д4's default recommendation, every task in its own worktree with its environment verified.
*Trigger:* preflight for `max_parallel` lanes. *Expected:* each lane's worktree, env vars and services
are ready, and port blocks do not collide under concurrent allocation.
*Assert:* allocate `max_parallel` lane specs concurrently, assert disjoint port blocks; assert every
identifier in a spawn descriptor (session id, cwd, prompt, branch, log path, ticket id) refers to the
same unit — a pure function, free, no model review.
*Catches:* F-54 (a launcher saying phase 5 while `cd`-ing into the phase-4 worktree), F-55 (a reused
slug into a stale worktree). Preserves P-04 (two lanes with no port or state collision).

**A-11 · Clean slate: orphans from prior runs enumerated.**
*Pre:* Д3; a prior run that died before cleanup, which is how the previous runs actually ended
[C: FIELD-NOTES §10.1, `DEAD-RUN` + `STOPPED`]. *Trigger:* preflight.
*Expected:* resources labelled by any prior run id are enumerated and either reclaimed or explicitly
acknowledged. *Assert:* the enumeration is by **label only**, works from no in-memory state, and
refuses to touch anything unlabelled.
*Catches:* F-48 (~150 orphaned Docker volume pairs from a dead prior run).

**A-12 · Machine headroom, measured with the right meter.**
*Pre:* R1-05 defers machine-resource awareness by the owner's decision. *Trigger:* preflight.
*Expected:* free disk and memory headroom recorded in the run header. *Assert:* pressure is read from
`memory_pressure -Q` [present at `/usr/bin/memory_pressure`, L5-V5], **not** from swap occupancy,
which is not a pressure signal on macOS [C: FIELD-NOTES §5.2]. Detection and attribution only — no
gate, per the owner's deferral.
*Catches:* F-46 (the owner's own container OOM-killed in 31 seconds by two concurrent builds,
detected only by correlating timestamps with `docker inspect` afterwards).

**A-13 · Tree hash recorded; the run refuses to report on a tree that changed under it.**
*Pre:* R1-05 parallelism; the operator working in the same tree (R1-16's second named case).
*Trigger:* preflight records a content hash; audit re-checks. *Expected:* a mid-run change to the
code under test produces `tree-changed`, not a verdict.
*Catches:* F-71 — verified by accident during the corpus work itself: a scratchpad mutation altered
by a sibling agent produced a confident, deterministic, **wrong** result three times running
[C: failure-corpus §1.5]. A reproducible result is not therefore trustworthy.

**A-14 · Installed copy matches the source tree.**
*Pre:* this repository ships plugins that are also installed from a marketplace. *Trigger:* preflight
and session start. *Expected:* every file of the installed plugin matches the source tree.
*Assert:* per-file digest comparison; a mismatch names the files and refuses.
*Catches:* F-49 — a documented ticket-id locking fix that landed only in the installed copy and was
**still missing from the source thirteen days later** [C: failure-corpus §1.3, verified against
`harness-tickets.sh` `l_add()`].

### 5.2 Family K — the canary fault schedule (real run, bounded)

A canary without injected faults tests the happy path, and the record shows the happy path was never
the problem. `faultd.sh` runs **outside** the run's process tree, reads `K-schedule-*.yaml`, performs
each fault at its scheduled offset and writes its own independent log. The audit asserts the expected
observable for each.

**K-01 · Kill the orchestrator mid-tick.** *T+90m.* `kill -9` the loop.
*Expected:* the configured health check revives it within its interval; exactly one orchestrator runs
afterwards; **no ticket is redone** ("start over" means restart the orchestrator, not redo the work —
R1-10); no ticket is left `in-progress` with no live session; every state write was atomic.
*Assert:* ledger shows one `spawn` of a replacement orchestrator and zero duplicate `step` records
for any ticket; the audit's process probe shows one live lock holder at every sampled instant.
*Catches:* F-13, F-15 (restart with executors alive: adopt-and-duplicate or tear-down-and-lose).

**K-02 · Restart while executors are still alive.** *Implied by K-01.* Workers survive the kill.
*Expected:* each surviving session is classified `mine-alive`, `mine-dead` or `not-mine` **before**
any ticket is claimed. *Assert:* a live registered worker's ticket is not re-claimed; a dead one's is
released exactly once; an unregistered process is `not-mine` and untouched.
*Catches:* F-15, and it is Д10 tested at real scale.

**K-03 · Strand text on a session's input line.** *T+20m.* `faultd` types text without Enter into a
worker's pane. *Expected:* the next automated write **refuses** with a distinct "line busy" status,
surfaces the pending text to the control channel, and does not overwrite it.
*Assert:* the ledger carries a `delivery` record with `verified:false, reason:"line-busy"` and the
pending text appears in the control channel; **no** record says delivered.
*Catches:* F-02 (two real operator instructions, `push master` and `carry on with the queue`,
destroyed while the engine logged them as nudged), F-04 (a recovery rung that clears without
submitting).

**K-04 · Blind the usage endpoint for 10 minutes.** *T+60m.* Point the account's resolver at a shim
returning the real captured `authentication_error` body. *Expected:* verdict `UNKNOWN` typed as
`Unauthenticated` (not the generic unreachable branch); N consecutive unknowns escalate through the
configured channel and apply the configured stop semantics; the run never continues silently past the
threshold. *Assert:* the ledger's `quota_read` records carry `verdict:UNKNOWN, error:Unauthenticated`
and exactly one escalation; the run record distinguishes "quota was fine" from "quota was never read".
*Catches:* F-16 (`limits.on_unreadable` defaulting to `proceed`; the mutation the old suite passed
51/51), F-18. The fixture is free: the ground work produced the real auth-error JSON by accident
[C: evaluating-llm-decisions V15].

**K-05 · Mid-run account reassignment.** *T+120m.* Write a new role→account mapping into the control
file with `soft` semantics. *Expected:* already-running sessions keep their **boot** account in the
registry; only new spawns use the new one; the quota series for the old account is **closed** and a
new series begins; no threshold-crossing event is emitted at the switch.
*Assert:* the audit's quota series are keyed by account identity, and the switch instant carries no
crossing event. *Catches:* F-19 (a weekly reading falling 26% → 6% from the account switch alone,
manufacturing a phantom "we have headroom" event).

**K-06 · `stop-soft` then `resume` through the control file.** *T+150m / T+155m.*
*Expected:* `stop-soft` lets the current task finish and starts nothing new; `resume` restarts intake
on the **next** tick, not the current one and not two ticks later; a `stop-hard` written while a
soft stop is pending wins. *Assert:* per-tick decision log shows exactly one transition each; no
spawn occurs between the two marks; the commands are acted on **exactly once** each despite the file
being re-read every tick (idempotence on content hash, not mtime alone).
*Catches:* F-10, F-11 (a reader observing the staging file truncated to zero bytes), F-42 (a finding
re-emitted 1085 times over five days because nothing deduplicated it).

**K-07 · Edit a ticket body mid-flight.** *T+40m.* Change the description of the ticket currently
executing. *Expected:* the configured watcher (a cheap model per Д8) reports what changed; it is
**silent when nothing changed**; a whitespace-only edit produces no report.
*Assert:* the ledger carries one `board_write`-adjacent observation record for the real edit and zero
for a whitespace-only control edit injected at T+45m.
*Catches:* the Д8 failure direction — a watcher that either cries wolf on every diff or absorbs a
reversal silently [C: evaluating-llm-decisions R-4].

**K-08 · Decoys: one unlabelled process, one unlabelled container, running the whole run.**
*Pre:* R1-16's boundary, and Д3's mandatory end-of-run cleanup means the run **will** execute
destructive commands by design. *Expected:* both decoys are alive and untouched at the end; cleanup
enumerates by label, refuses the whole operation if any target lacks the run label, and refuses to
run at all with an implicit scope.
*Assert:* the world probe shows both decoys present with unchanged start times; the recorder's argv
log shows no command targeting them; every destructive invocation carries an explicit scope variable.
*Catches:* F-44 (the owner's default stack destroyed by `docker compose down -v` with no
`COMPOSE_PROJECT_NAME`; the actor was never identified), F-45 (`pkill -f 'playwright test'` killing an
unrelated lane because every lane's prompt contains that literal string).
**This is the single most important canary scenario.** It is the one whose failure is irreversible.

**K-09 · A ticket that fails three times identically.** *Queued from the start.* A canary ticket whose
step is scripted to fail the same way each attempt. *Expected:* Д5 fires **exactly once** on the third
structurally identical failure (normalised: command + error class, timestamps and ids stripped);
three *different* failures do not fire it; the action taken is the configured one.
*Assert:* one escalation record, not three; and a control ticket with three differing failures
produces none. *Catches:* F-26 (a subagent retrying `docker desktop start` for 33 m 31 s and 184k
tokens against a dead daemon, with every liveness signal green).

**K-10 · A ticket blocked on a human question.** *Queued from the start, with a dependent and an
independent sibling.* *Expected:* the independent sibling continues (Д6 — waiting does not block the
queue); the dependent does not start; the question reaches the configured channel and the answer,
written to that channel mid-run, is picked up live.
*Assert:* the ledger shows the sibling's full lifecycle during the block; the dependent has zero
`spawn` records; the question's `notification` record is verified by the channel's own read-back.
*Catches:* F-27 (the orchestrator idle **35+ minutes with eight ready tickets and no lanes** because
a state was in the vocabulary but in no action rule), F-12. Preserves P-01 (eleven questions routed
rather than guessed).

### 5.3 Family V — audit conservation identities (free, every run, forever)

These are the run-level analogue of F-32's arithmetic. Each is a total, mechanically checkable
identity over the ledger and the probes. **A broken identity is verdict `FAILED` regardless of the
dials.**

**V-01 · Ledger veracity.** `count(records claiming an effect AND verified:true AND probe agrees) ==
count(records claiming an effect)`. Any record the auditor cannot corroborate, or that a probe
contradicts, is a divergence. *Catches:* F-07, F-29, F-36, F-52 — the whole "attempt reported as
effect" class, in one identity.
*Mutation:* strip the `evidence` block from any one emit site → V-01 red.

**V-02 · Delivery integrity.** `unconfirmed_deliveries == 0`, and for every `Delivered` there is a
user turn in that session's transcript within the bounded window. For every `Refused`/`Failed`, the
session state is unchanged and nothing was consumed.
*Catches:* F-01 … F-09. This is the `deliver(session, text) -> Delivered | Refused | Failed` contract
asserted at run level and, per instruction **I1**, run identically against every configured adapter.

**V-03 · Blast radius.** `targets_acted_on ⊆ targets_created_by_this_run` (set containment, by label),
and `unlabelled_targets_touched == 0`. Also: every destructive action recorded actor, run id and
target list **before** executing. *Catches:* F-44, F-45, and Д3's "щоби не залишати хвостів" made
checkable.

**V-04 · Step coverage.** For every ticket that reached a terminal state, every step of the
configured process reached a terminal state, and any step that did not run is recorded `skipped` with
a reason. No ticket reaches `done` with a step in state `unknown`. Additionally: an artefact whose
producer identity equals the ticket's executor identity is **flagged non-independent** when the
configured process declares that step independent.
*Catches:* F-30 (GSD's verify stage silently skipped for phases 14–18, each `NN-VERIFICATION.md`
self-attributing `verified_by: the lane that built the phase`; **no automated check caught it —
manual review did**), F-31 (phase 21 reached the trunk before its validator ran).
*Boundary note:* this is bookkeeping about the orchestrator's own actions, never a judgement about the
user's work. The corpus flags this as the one place it departs from R1-13 and asks for it to be
**question one of round 2** [C: failure-corpus §11]. If the owner rejects it, V-04, V-05 and V-06
come out and the run accepts that a silently skipped verification stage can ship five tickets again.

**V-05 · Ref movement.** Every `ref_move` record's post-SHA differs from its pre-SHA and the source
SHA is an ancestor of it. An operation whose ref did not move is a failure, whatever it printed.
*Catches:* F-29 — a merge that printed `Already up to date` and `Everything up-to-date`, exit 0, with
the phase never reaching the trunk; caught in the real run only because someone checked what `master`
actually pointed at. *`n/a`-able for non-code runs, declared in the profile.*

**V-06 · Result conservation.** Wherever the configured process reports counts,
`declared_total == passed + failed + skipped + not_reached`; a process that exited on a signal is
recorded `incomplete`, never as its printed summary; a result of zero units is `suspect` unless zero
is declared expected. *Catches:* F-32 (**346 passed, 0 failed** of a declared 382, caught by
subtraction after host memory pressure killed the runner), F-33 (`No tests found` from an import-time
crash), F-35 (`OK, 0 files compared` from the wrong cwd). *`n/a`-able, declared.*

**V-07 · Escalation reachability.** Every escalation ladder that started reached a terminal rung, and
the terminal rung reaches the human through the R1-17 channel with a verified `notification` record.
No path through the ladder ends in silence. `max_time_to_first_escalation` is reported.
*Catches:* F-28 (the ladder had one rung; observed peaks of 2808 s and **44,791 s — about 12.4
hours** — before a nudge fired), F-41.

**V-08 · Finding deduplication.** `distinct_findings / emitted_finding_records ≈ 1`: the same finding
across N ticks is one record with `count=N`. A finding unresolved past its threshold escalated. A
finding that no available action can resolve was reported as such at first detection, not on a timer.
*Catches:* F-42 (1085 identical re-flags over five days), F-43 (an unwedge process polling
`run is stopped — holding` every 180 s for 32 minutes while doing nothing).

**V-09 · Loop bound and fixed points.** No corrective action fired against the same target with the
same trigger more than N times without a change in the observed state; any action whose post-condition
was "the state changes" and whose state did not change is recorded **ineffective**.
*Catches:* F-40 (an 85-minute self-sustaining Escape/`continue` loop driven by a rate-limit regex
matching the orchestrator's **own wrapped prose**; nothing internal detected it; it ended by external
`SIGTERM`), and its second occurrence, a 45-minute variant in the other run.

**V-10 · Session ownership closure.** Every session spawned has exactly one recorded owner
responsible for closing it; at run end, `sessions_open == 0` or each remaining one is listed with its
owner and reason; a session whose owner died was still reaped.
*Catches:* F-14 (a question-role session registered and idle for **one day and four hours**, logged
`finished-awaiting-close` for hours by a watcher with no remit to close it, closed by hand).
*Must not break P-03:* the reaper closes **finished** sessions and never force-closes a busy one —
three sessions in the real run hit `job still running after timeout — LEAVING SESSION OPEN` and were
later found finished on their own.

### 5.4 Family P — promotion and corpus feedback (free)

**P-01 · Change classification is mandatory and mechanical.**
*Pre:* a change to the plugin. *Trigger:* `orchestrator:promote`. *Expected:* the changed paths map
to a class (`cosmetic` / `logic` / `safety`) by a committed path→class table; an unclassified path
defaults to `safety`, never to `cosmetic`. *Assert:* a change touching an unmapped path is refused
until the table is extended. *Catches:* the drift by which a change to the delivery layer ships as a
docs change.

**P-02 · The required canary class ran, with the matching fault.**
*Expected:* a `safety` change to family X requires the canary's fault schedule to contain the fault of
family X (a lock change requires K-01; a delivery change requires K-03; a cleanup change requires
K-08). *Assert:* promote refuses and names the missing fault. *Catches:* the general shape of F-21/22/23
— a bug fixed twice, badly, because the fix's own failure mode was never exercised.

**P-03 · Two consecutive green canaries, the second on unprepared machine state.**
*Expected:* no pre-warmed caches, no pre-created worktrees, no already-running services; the second
canary's preflight records a different machine fingerprint from the first.
*Assert:* promote refuses on one green canary, or on two with identical machine fingerprints.
*Catches:* F-71, and the environment-dependence class of §14 (`find` resolving differently under
`env -i`, `/tmp` symlink, BSD `date`).

**P-04 · A failed run files itself, and the repo goes red.**
*Pre:* an audit verdict other than `CLEAN`. *Trigger:* `orchestrator:audit`.
*Expected:* each divergence produces a normalised signature; known signatures increment and, at
`occurrences ≥ 2`, mark their existing regression test `INSUFFICIENT`; new signatures write a corpus
entry, a captured-evidence fixture and a **registered, failing** stub in `tests/regressions/`.
*Assert:* `bash tests/run-all.sh` is red until the assertion is written; the debt appears in every
subsequent morning artifact until discharged.
*Catches:* F-49 (a documented fix missing from the source thirteen days later) and the meta-failure
the whole spike exists to fix: a run that failed, was understood, and left nothing behind that could
fail again.

---

## 6. Metrics — three gates and seven dials

**Gates are binary and always block. Dials are compared to a committed baseline and block only on
regression beyond their band.** Every dial is reported **with its baseline beside it**, never as an
absolute — the ground research measured a 62% majority-class base rate on stall judgement and states
the consequence plainly: a suite reporting "83% accurate" while missing every real stall is the
vacuous test reborn as a dashboard [C: evaluating-llm-decisions §2.3].

### 6.1 The three gates

| Gate | Definition | Evidence | Threshold |
|---|---|---|---|
| **G1 ledger veracity** | verified effect-records ÷ effect-records (V-01) | probes | **= 1.000** |
| **G2 delivery integrity** | unconfirmed deliveries (V-02) | `UserPromptSubmit` receipts + transcripts | **= 0** |
| **G3 blast radius** | unlabelled targets acted on (V-03) | world probe + argv recorder | **= 0** |

Any gate red → verdict `FAILED`, no promotion, corpus ingest fires.

### 6.2 The seven dials

| # | Dial | Definition | Primary evidence | Baseline (34-h run) [C] | Band |
|---|---|---|---|---|---|
| **D1** | work landed / hour | tickets reaching a terminal state with a verified effect ÷ elapsed h | ledger + board read-back | **0.38/h** (13 merged in 34 h, FIELD-NOTES §6) | ≥ 0.7× baseline |
| **D2** | quota per unit of work | Δ(utilisation %) ÷ tickets landed, **per account** | `quota_read` series keyed by account | **≈ 2.0 %-weekly / ticket** (26% for 13, §5.3) | ≤ 1.3× |
| **D3** | interventions needed | human actions: writes to the control file, manual fixes, out-of-band kills, entries in the owner-actions log | control-file diff + owner-actions + faultd log (faults excluded) | **≥ 4 in 34 h** (owner pushed master himself; a session closed by hand; `J-SUP-34` fixed by hand; the 85-min loop ended by external `SIGTERM`) | **canary target 0** |
| **D4** | stalls detected vs real | precision = real ÷ raised; recall against the look-ahead-adjudicated set | screen + heartbeat + transcript replay | **precision ≈ 38%** (62% of stale-heartbeat readings were false stalls, adjudicated; 97 `STALLED` raises, 11 self-labelled false) | precision ≥ 0.8, recall ≥ baseline, **majority-class 62% printed beside it** |
| **D5** | false escalations | notifications the audit classifies as not needing the human ÷ notifications; plus dedup ratio (V-08) | notification read-backs | **33 nudges / 34 h ≈ 1 per 62 min, ≥ 6 against healthy sessions**; 1085 identical re-flags over 5 days | ≤ 0.1, dedup ≈ 1.0 |
| **D6** | cleanup completeness | resources reclaimed ÷ resources created, + orphans left, + orphans reclaimed from prior runs | label enumeration | **~150 orphaned volume pairs left by a dead prior run** | **0 residue**, 0 unlabelled touched |
| **D7** | cost per task | money if API-keyed; %-of-window if subscription; **read from the configured process's own accounting where it has one**, supplemented only where it does not (R1-06 part 3) | process records + `quota_read` series | to be established by canary 1 | ≤ 1.3× |

**D7 has no baseline and must not pretend to one.** R1-06 part 3 says to reference the chosen
process's own records and keep our own only where the process has none; for GSD the assumption
"майже нічого не треба робити" is explicitly an assumption to verify. The first canary establishes the
number; the second compares. **INFERRED estimate for planning only:** the 34-h run averaged ~2%
weekly per phase at 1–5 h of worker time per phase; canary tickets are minutes, so C2's six tickets
should land near **0.5–1% of a weekly window** and C1 near **0.2%**. That is an estimate, and the
canary's job is to replace it with a measurement.

**Two dials worth adding that the brief did not name** [I], because the record says they were the
binding constraints:

- **D8 · throughput bottleneck attribution.** Across 34 hours quota was *not* the constraint — the
  dependency graph was; of nineteen phases only two pairs could ever run concurrently
  [C: FIELD-NOTES §5.3]. Report, per run, how much wall time was lost to dependency blocking vs
  quota waits vs stalls vs human waits. A rebuild that optimises quota before dependency scheduling
  is optimising the wrong constraint.
- **D9 · context growth attribution.** Per session, how much context growth came from **repeated
  identical tool calls**. The metric that made the worst context bug diagnosable: 3,466 of 3,626
  Bash calls were the literal string `echo idle`, adding 445k tokens — 77% of all context growth in
  that window against 135k from real work — while every liveness signal stayed green
  [C: FIELD-NOTES §3.1]. Nothing in the previous plugin measured context at all.

---

## 7. The canary

### 7.1 Profiles

| Profile | Queue | Lanes | Accounts | Horizon | Faults | Purpose |
|---|---|---|---|---|---|---|
| **C0 rehearsal** | 2 | 1 | 1 (doubled) | ~3 min | — | the whole entry point through doubles; **free**; must pass before spending anything |
| **C1 smoke** | 2 trivial real tickets | 1 | 1 | ~30 min | K-03 | lifecycle: spawn → deliver → work → step sequence → terminal state → board write → close → cleanup → report |
| **C1-nocode** | 2 (write a file; no repo, no tests, no build) | 1 | 1 | ~20 min | K-03 | N2's explicit case. `probe-git`, V-05 and V-06 declared `n/a` |
| **C2 night** | 5–6, incl. one dependency-blocked, one human-blocked, one scripted to fail 3× | 2 | 2 | ~4 h | K-01 … K-10 | the promotion canary |
| **C3 real** | unrestricted | as configured | as configured | overnight | — (faultd off) | not a canary — what the canary earns; the audit still runs |

**The canary tickets are real and disposable.** They are committed under `acceptance/canary/queue/`
and are shaped so their *work* is trivial and their *lifecycle* is complete. The point is never the
work product; if the ticket's own step fails, that is a canary finding about the process
configuration, not about the orchestrator, and the audit reports it in a separate section.

### 7.2 Fault schedule format

```yaml
# acceptance/canary/faults/K-schedule-C2.yaml
schedule:
  - id: K-03
    at: PT20M
    action: strand_input
    target: {role: worker, lane: 1}
    expect:
      ledger: {kind: delivery, verified: false, reason: line-busy, count: ">=1"}
      ledger_absent: {kind: delivery, verified: true, target_text_sha: "$NONCE_SHA"}
      control_channel_contains: "$NONCE"
  - id: K-08
    at: PT0S
    action: place_decoys
    decoys:
      - {type: process, cmd: "sleep 99999 # playwright test"}   # F-45's exact shape
      - {type: container, name: canary-decoy, labels: {}}       # unlabelled, F-44's shape
    expect_at_end:
      decoys_alive: true
      argv_recorder_targeting_decoys: 0
```

`faultd.sh` writes `faults.jsonl` with what it did and when. **The audit reads `faults.jsonl` as a
primary source** — the orchestrator never sees it, so it cannot anticipate a fault, and the audit can
distinguish an intervention the operator made from one the fault daemon made (which D3 must exclude).

---

## 8. The morning artifact

One machine file and one human file. `run-report.json` is the contract; `RUN-REPORT.md` is rendered
from it by `render.sh` and is **never hand-written** — a hand-edited report is how a run's own record
becomes fiction, which is F-52's shape.

Order is by what the owner reads at 08:00, not by what the system finds interesting.

```
VERDICT: CLEAN | DEGRADED | FAILED | UNVERIFIABLE        ← one line, first line
run 20260919-021500 · 4h 02m · plugin 3a91c7f · tree 8de2… · seed 7714

1. WHAT NEEDS YOU            (the only section allowed to ask; deduplicated; each: what happened,
                              what it blocks, the one action. Empty in a clean run — and empty
                              because it was checked, with the count of checks stated.)
2. WHAT LANDED               (per ticket: terminal state · evidence anchor (sha / digest / board url)
                              · step coverage: every declared step + terminal state, `skipped` with
                              reason — V-04)
3. WHAT IT COST              (D1–D9, each with baseline and delta; quota series per account, with
                              series boundaries at account switches marked — K-05)
4. WHAT IT DID TO THE WORLD  (created / destroyed by label; orphans found and reclaimed; and — the
                              section worth reading — what it DECLINED to touch and why)
5. WHAT IT GOT WRONG ABOUT ITSELF
                             (V-01…V-10 divergences. Empty in a clean run, and the emptiness is
                              verified: "1,284 effect-records checked against 9 probes; 0 divergent")
6. NEW CORPUS ENTRIES        (what was auto-filed; which stubs are now red; outstanding debt)
7. REPRODUCTION FOOTER       (seed · plugin commit · tree hash · config snapshot digest · tool-dialect
                              fingerprint · machine fingerprint · adapter capability matrix incl. the
                              discovered per-backend line ceiling)
```

**Д11 and R1-17 together.** The orchestrator prints nothing during the run. The report is a file. The
notification says one line: `report ready at <path> · verdict: X · N items need you`. Nothing else is
pushed. The `status` command remains the pull channel [Д11: *"оркестратор не повинен нічого виводити
для мене"*].

**Section 5's emptiness must be a measured emptiness.** "No divergences found" and "the auditor never
ran" must be distinguishable in the artifact. That is the empty-is-not-clean rule applied to the
report itself.

**Section 1 is the metric the owner actually cares about.** Its length is D3. A run whose section 1 is
empty is an unattended run; a run with four entries is a run that needed a human four times.

---

## 9. Promotion rule

```
classify(change) → cosmetic | logic | safety          # committed path→class table; unmapped ⇒ safety

cosmetic  : L1–L4 green.                                        no canary
logic     : L1–L4 green + preflight + C0 + C1 + audit CLEAN.    dials within band
safety    : L1–L4 green + preflight + C0 + C2 + audit CLEAN,
            with the fault of the touched family present in the schedule (P-02)

promote(run) requires, for the class:
  - all gates G1 G2 G3 green                        (never waivable)
  - every dial within band, or an entry in waivers.json with a written reason
  - TWO consecutive green canaries of the required class, the second on an
    unprepared machine state with a different machine fingerprint       (P-03)
  - zero outstanding red regression stubs from prior runs, or an explicit
    acknowledgement that then prints in every morning artifact until discharged
```

**A waiver is visible or it does not exist.** `waivers.json` entries print in section 1 of every
subsequent morning artifact until removed. The corpus records the owner's explicit deferral of
machine-resource awareness (R1-05) as an accepted risk with a detection-only obligation; that is
exactly a waiver, and the reason it must stay visible is that the last time such a risk was
implicit, the owner's own container was OOM-killed and nobody noticed for half an hour
[C: F-46].

**Rollback.** A promoted change that produces a non-CLEAN real run within the next three runs is
demoted automatically: the class is raised one level and the promotion requirement re-applies.

---

## 10. How a failed real run feeds the corpus, automatically

`orchestrator:audit` on any non-`CLEAN` verdict invokes `corpus/ingest.sh`. Per divergence:

1. **Signature.** `sha256(kind ∥ component ∥ evidence_source ∥ failure_class)` over **normalised**
   text — timestamps, ids, pids, paths and durations stripped. The normalisation is the same one Д5
   needs (F-26c: three failures differing only in timestamp must be recognised as identical), so it
   is written once and tested once.
2. **Known signature** → increment `occurrences`, append the run id. At `occurrences ≥ 2`, mark the
   entry's existing regression test **`INSUFFICIENT`** and surface it in section 1. *A test exists and
   the bug recurred, therefore the test is vacuous* — this is the house mutation rule run backwards,
   and it is the mechanism that stops a grep-shaped test from standing in for coverage a second time.
3. **New signature** → write:
   - `corpus/entries/F-<n>.md` from the corpus's own template (precondition · trigger · wrong
     behaviour · assertion · substrate · **mutation** · catches), with everything except `assertion`
     and `mutation` pre-filled from captured evidence;
   - `corpus/fixtures/F-<n>/` — the primary-evidence bundle: transcript slice, screen capture, ledger
     slice, the raw usage body (redacted), `git` state, the argv recorder's log, `faults.jsonl` slice;
   - `tests/regressions/F-<n>.sh` — a **registered, failing** stub whose failure message names the
     file to complete and the fixture to assert against.
4. **The repository goes red.** `bash tests/run-all.sh` fails until a human or an agent writes the
   assertion. Discharge requires the assertion **and** its mutation to have been demonstrated red.

**Redact at capture time, never at commit time.** Transcript-derived fixtures are exactly where
credentials leak into git: two local role passwords were printed in clear text into a session
transcript by Playwright `--trace on`, found by manual review, with **no automated secret scan
covering tool output or transcripts** [C: FIELD-NOTES §11.10, F-64]. The ingester runs the credential
scanner over every captured artefact before writing it, and quarantines rather than commits on a hit.
This repository's own CLAUDE.md already requires a credential check before staging; screen captures
and transcripts are a new artefact class that rule does not yet cover.

**The compounding payoff** [I, and it is the strongest argument for the ledger contract]: if every
live verdict is written in a structured envelope, every run auto-generates the next golden dataset,
adjudicated by what happened next. The previous generation produced a free 176-case labelled dataset
*by accident*, because one watcher happened to write structured lines
[C: evaluating-llm-decisions §2.2]. Making that deliberate means the eval problem largely solves
itself from run two onward.

---

## 11. Mutation checks

The house rule, mechanised. `acceptance/mutations/*.mut` declares target, edit, and the scenario ids
that **must** go red. `mutations/run.sh` copies the tree to a tmpdir, applies the edit with a patcher
that `assert`s the old text was found (a silent no-match `sed` is itself a corpus entry — F-36), runs
only the affected checks, and **fails if the named scenarios still pass**.

| # | Mutation to the implementation | Must turn red | Guards against |
|---|---|---|---|
| M-01 | `deliver()` returns `Delivered` on transport exit 0, skipping the receipt read | A-07, V-02, K-03 | the old suite's M1 and M6, which passed 51/51 [C] |
| M-02 | remove the pre-write empty-line check | K-03, V-02 | F-02 |
| M-03 | truncate the discovered line ceiling to a hardcoded 200 | A-07 | F-03; also proves the ceiling is *discovered* |
| M-04 | strip the `evidence` block from one emit site | V-01 | the whole attempt-vs-effect class |
| M-05 | move the `delivery` log line above the confirmation | V-01, V-02 | F-07 |
| M-06 | point the status writer at the inbound control path | A-06, K-06 | F-10 (the read-only tick fails immediately) |
| M-07 | replace the atomic rename with truncate-then-write | A-06, K-06 | F-11 |
| M-08 | resolve the control/question channel path relative to cwd | A-06 | F-12 |
| M-09 | replace the lock check with `pgrep -f orchestrator` | A-08 | F-13 test 4 — and it *will* fire, because the fake session's own prompt contains the word |
| M-10 | make `UNKNOWN` quota return `OK` | K-04 | F-16; **this is the mutation the old suite passed 51/51** |
| M-11 | drop the account label from the quota record | A-03, K-05 | F-17, F-19 |
| M-12 | collapse `401` into the generic unknown branch | A-03, K-04 | F-18 |
| M-13 | let cleanup fall back to the default project when the scope var is unset | K-08, V-03 | F-44 — the irreversible one |
| M-14 | report merge success on exit status 0 | V-05 | F-29 |
| M-15 | accept the process's summary line without the conservation arithmetic | V-06 | F-32 |
| M-16 | remove the repetition counter / the terminal escalation rung | V-07, V-09 | F-40, F-28 |

**Vacuity audit — the checks most at risk, named so they are designed correctly rather than
discovered later.** Three of this layer's assertions could be written in a shape no mutation can
break, which is the H-33 failure exactly: the config-validation feature was deleted, the sentence
survived in a `# TODO`, and the test stayed green [C: what-exists-here §4.1].

- **A-09 (red line in every prompt).** Vacuous if it greps a template for an include token. Correct
  form: consume the **production renderer's output** and digest-match. Mutation: remove the include
  from the renderer, not from the template.
- **A-02 (steps resolve).** Vacuous if it checks that a name is non-empty. Correct form: resolve and
  **dry-run**; record what it resolved to. Mutation: point a step at a non-existent command.
- **V-04 (step coverage).** Vacuous if it reads the orchestrator's own "all steps done" summary.
  Correct form: enumerate the declared steps from config and require a terminal-state record per
  step, from the step probe. Mutation: let a ticket close with a step in state `unknown`.

**One check that needs no mutation, and should be written first.** F-51's concurrency test — N
concurrent ticket adds must produce N distinct ids — **fails against the current source today**: the
id allocator is an unlocked read-then-write and `grep -nE 'lock|flock|LOCK'` over that file returns
only the word `blocked` [C: failure-corpus §1.3, verified against `harness-tickets.sh`]. Writing it
first and watching it fail is the strongest available demonstration that this layer works.

---

## 12. Cost

### 12.1 Wall time

| Pass | Contents | Seconds |
|---|---|---|
| Preflight alone | A-01 … A-14; A-07 dominates (spawn + round-trip + 10-point sweep per adapter × backend) | **20–40 s** for one adapter; **+10–15 s per additional adapter × backend** |
| Audit alone | 9 probes over the ledger and primary sources; transcript scan is the largest term | **10–25 s** for a 4-hour run; ~45 s for a 12-hour run |
| Report render | json → markdown | **< 5 s** |
| Mutation pass | 16 mutations × (copy tree + run affected checks only) | **~3–5 min** |
| C0 rehearsal | full entry point through doubles | **~3 min** |
| **Full free pass** | preflight + C0 + audit + render + mutations | **≈ 8 min, $0, no network beyond the configured board and usage endpoints** |
| **C1 promotion pass** | preflight + C0 + C1 + audit + render | **≈ 35 min wall**, of which ~30 min is the real run |
| **C2 promotion pass** | preflight + C0 + C2 + audit + render | **≈ 4 h 10 m wall** |

Anchors for these estimates: the existing 475-assertion suite runs in **42.15 s** with roughly half of
that being `run-all.sh`'s double execution [C: what-exists-here §2.6]; a mutation copy-and-run of the
current suite takes ~2 s [C: testing-agentic-systems §13].

### 12.2 Money

**Everything free is free.** Preflight, C0, the audit, the report, the mutation pass and the corpus
ingester make **zero model calls**. That is deliberate and it is the property that determines whether
this layer gets run at all [C: what-exists-here §2.6 — "Cost: zero … any new layer that breaks it will
stop being run"].

**The canary costs real sessions.** Two cost models, because R1-06 requires adapting to whatever the
provider's scheme is, including none:

- **Subscription (the owner's case).** C1 ≈ 2 short worker sessions; C2 ≈ 12 short sessions across
  4 hours. Derivation [I]: the 34-h run spent ~2% of a weekly window per phase at 1–5 h of worker
  time; canary tickets are 5–10 min, so ≈ 1/12–1/30 of a phase each → **C1 ≈ 0.1–0.2% of a weekly
  window, C2 ≈ 0.5–1%.** These are estimates. **Canary 1's job is to replace them with D2 and D7
  measurements**, after which the band is enforced rather than guessed.
- **Pay-as-you-go.** Measured per run from the usage series and reported as D7. No estimate offered
  here; there is no basis for one on this machine.

**`claude plugin eval` is deliberately not part of L5.** It exists, it works, and it is real money:
defaults are `runs: 3 × ablation 2 arms = 6 full agent sessions per case` on the operator's own
credential and rate limit, ~$0.07 per case-run, ~$8–10 for a 40-case suite
[C: what-exists-here §6.1; evaluating-llm-decisions V3, §7]. That is the right tool for the
*judgement* rubrics (is this session stalled; should this run stop now) and it belongs in the layer
that owns prompts. L5 is about **whether a run's claims are true**, which is a free, deterministic
question. Mixing them would make the acceptance gate cost money and it would stop being run.

**What the canary is actually buying, stated plainly.** A C2 pass costs about four hours and around
1% of a weekly window. The alternative it is being compared against is the previous generation's
34-hour run, which produced ~60 distinct failures, an 85-minute runaway loop, 12.4 hours of a dead
night, a destroyed default Docker stack and a lost operator instruction — and whose 51-test suite
caught none of it [C].

---

## 13. Honest limits — what this layer cannot catch

Stated so the next layer knows what it inherits, and so the owner does not read a green canary as
more than it is.

1. **Anything that needs longer than the canary's horizon.** The observed peaks that mattered were
   **12.4 hours** before an escalation fired and a condition re-flagged **1085 times over five days**
   [C: F-28, F-42]. A 4-hour canary is structurally blind to both. *Mitigation, not a fix:* the audit
   runs on every real run, so C3 is instrumented too — the canary is the gate, the audit is permanent.
   **Inherited by:** nobody. It can only be caught by running long and auditing afterwards.

2. **Rare non-determinism.** Two green canaries are two samples. The decisive ground result is that a
   categorically broken lock **passed five rounds of 100 concurrent acquirers** and only failed when
   the race window was widened [C: testing-agentic-systems §9.4]. **A green A-08 is not evidence of
   exclusivity.** That proof lives in L3's `TEST_DELAY_*` sweep and L5 must never be cited for it.
   **Inherited by:** L3.

3. **Quality of the work.** By R1-13, deliberately, and this is correct. L5 audits the orchestrator's
   bookkeeping only. V-04/V-05/V-06 sit at the boundary and the corpus flags them as the one place it
   departs from ANALYSIS-01 — **question one of round 2**.

4. **Platforms other than the one the canary ran on.** Every canary is per
   (platform × interactive|headless × account scheme). A green C2 on Claude Code interactive says
   **nothing** about Codex headless, GLM, Gemini or opencode. The corpus is explicit: *no adapter
   other than Claude Code has any evidence behind it*, and the entire delivery family is a property
   of driving a terminal — headless may retire Family 1 and introduce a family nobody has data for
   [C: failure-corpus §11]. Instruction **I1** requires the per-platform feasibility matrix; L5
   provides the *shape* (V-02 as a shared property across adapters) and not the evidence.
   **Inherited by:** a per-platform spike, and it is the largest unknown in this whole design.

5. **Non-code runs.** N2 allows no repository, no tests, no build. `C1-nocode` exists, but roughly a
   third of the corpus assumes git or a test runner and simply does not apply; there is **no evidence
   at all** about a non-code run, and D1's baseline (0.38 landed/h) does not transfer. The first
   non-code real run is unguarded, and the honest move is to say so rather than let a green
   `C1-nocode` imply otherwise.

6. **A shared blind spot between the orchestrator and the auditor.** `audit/isolation.test.sh`
   asserts the auditor sources nothing from the runtime, and every probe reads a source the runtime
   does not write — but if a **primary source itself lies**, both are fooled. The board API returning
   a stale read, a transcript missing a turn the model did produce, a hook that silently did not fire:
   each defeats the audit invisibly. *Partial mitigation:* probes are cross-checked in pairs where two
   independent sources exist (delivery = hook receipt **and** transcript; close = process table
   **and** `SessionEnd`). Where only one source exists, the identity is marked `single-witness` in the
   report and is not treated as confirmation.

7. **Fault fidelity.** A shimmed token revocation is not a real expiry; a `kill -9` is not a Mac going
   to sleep — which is how the previous run actually ended
   [C: FIELD-NOTES §10.1, *"orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may
   sleep)"*]. The faults are the closest cheap analogue, not the thing.

8. **Cost accounting it did not produce.** R1-06 part 3 says to reference the configured process's own
   records. L5 reads them and **cannot validate them**. If GSD's accounting is wrong, D7 is wrong and
   the audit will not know.

9. **Prompt regressions.** The mechanism by which five phases shipped with builder-only verification
   was an orchestrator generalising a narrow warning into "every GSD agent" [C: F-30]. V-04 catches
   the *consequence* on the run that suffers it. Catching the *cause* before a run needs an eval
   suite over prompts — `claude plugin eval` with the seven hard fixtures — which is explicitly not
   this layer. **Inherited by:** the prompt/eval layer.

10. **The canary's own queue is not representative.** Trivial tickets exercise the lifecycle, not the
    load. Worker durations in the real run grew from ~1 h for phases 10–14 to **4–5.5 h** for phases
    19–22 [C: FIELD-NOTES §9.5]; nothing in a 30-minute canary reaches that regime, and the context
    and compaction failures cluster there.

---

## 14. Open questions for the owner

1. **The Family 6 boundary (V-04, V-05, V-06).** R1-13 says the orchestrator imposes no verification
   of its own, and the evidence was put to you and did not change the answer. These three identities
   are written as bookkeeping about the orchestrator's **own** actions — did the step I was configured
   to run actually run; did the merge I reported actually move a ref — never as a judgement about the
   work. The distinction was never put to you in those terms. If you reject it, V-04/V-05/V-06 come
   out and the design accepts that a silently skipped verification stage can ship five tickets again.
2. **Is the `LEDGER-CONTRACT` (§3) acceptable as an architectural constraint?** Everything here rests
   on it, it costs nothing at write time, and it cannot be retrofitted cheaply.
3. **How long should C2 be?** Four hours is a guess balanced against ~1% of a weekly window. The
   failures that hurt most clustered after hour 8.
4. **May the canary run on a separate account, if you configure one**, so a promotion pass does not compete with your own
   work for the same rate limit? R1-07 already allows provider/account restriction by role.
5. **Corpus debt: hard red or acknowledged red?** §4.4 proposes that a failed run leaves
   `run-all.sh` failing until the assertion is written, with a one-line acknowledgement that then
   prints in every morning artifact. Softer than a hard block, harder than a TODO.

---

## 15. What to build first

Ordered by evidence-per-hour [I].

1. **The `LEDGER-CONTRACT` and two probes** — `probe-transcript.sh` (hook receipt + transcript) and
   `probe-git.sh`. With those, V-01, V-02 and V-05 exist, which is G1 and G2 — two of the three gates
   and the largest failure family in the record.
2. **A-06, A-07, A-08** — the control file, delivery round-trip and the lock. The three preflight
   gates whose absence produced the most measured damage.
3. **The audit and `render.sh`**, so that the very first real run produces a morning artifact. The
   artifact is what the owner judges this on.
4. **`corpus/ingest.sh`.** Wire it before the first real run, not after; its whole value is that it
   fires on a run nobody was watching.
5. **The 16 mutations.** Then C1, then C2.

And the demonstration to do before any of it, because it costs ten minutes and settles the question of
whether this layer is real: write F-51's concurrency test — N concurrent adds must yield N distinct
ids — and watch it fail against the source as it stands today.
