# Ground failure corpus — the regression suite the orchestrator rebuild has to pass

Built 2026-09-19 from the previous generation's real history. Every entry is a test-case
specification, not a recommendation: precondition, trigger, the observable wrong behaviour, and the
assertion that would have caught it. Ranked by how likely each is to recur in the rebuild described
in `../../round-1/ANALYSIS-01.md`.

**Sources actually read for this document**

| Source | Status |
|---|---|
| `plugins/harness/docs/FIELD-NOTES.md` (705 lines, whole file) | VERIFIED — read here |
| `product/spikes/harness-rebuild/round-1/ANALYSIS-01.md` (295 lines) | VERIFIED — read here |
| `plugins/harness/bin/*.sh`, `plugins/harness/tests/run.sh` | VERIFIED — read and executed here |
| `…/scratchpad/context/harness-evidence.md` (validated summary) | **MISSING** — the directory exists and is empty |
| `…/scratchpad/context/orchestrator-landscape.md` (failure-mode section) | **MISSING** — never created |

The two scratchpad files named in the task do not exist on this machine:
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/context/`
is present and contains zero files. A `find` across the whole scratchpad tree and the repository for
both basenames returned nothing. Everything below therefore rests on FIELD-NOTES.md plus what was
verified directly against the code. Where FIELD-NOTES.md is the only witness, the entry is marked
CLAIMED; where the behaviour was confirmed against source or by running something here, it is
VERIFIED. Nothing in this corpus is INFERRED without saying so.

---

## 1. What was verified on this machine

### 1.1 The old suite is 51 tests, all green, and it is mostly text-matching

VERIFIED. `bash plugins/harness/tests/run.sh` → `harness tests: PASS=51 FAIL=0`, reproduced four
times. Its own header line reads `static assertions, no source mutation, no network, no terminals`.
Of the 51 tests, **9 execute any plugin code** (H-29, H-39, H-40, H-41, H-42, H-43, H-44, H-45,
H-46 — the pure helpers in `hlib.sh` and the local ticket file backend). The other **42 are `grep`
over source text and prose**; the file contains 83 `grep` invocations.

### 1.2 Six of seven deliberate defects survive the whole suite

VERIFIED by mutation, each on an isolated copy under the scratchpad, never on the repository. Each
mutant was confirmed to parse (`bash -n`) and to differ from the original in exactly one file.

| # | Mutation — a real defect, deliberately introduced | Suite result |
|---|---|---|
| M1 | Stall nudge disabled: `harness-run.sh` no longer sends Enter to a stale session | **PASS=51 FAIL=0** |
| M2 | Ready-floor disabled: `require_ready_body()` returns 0, so any garbage body becomes a `ready` ticket | **PASS=51 FAIL=0** |
| M3 | Quota fails **open**: an unreadable usage API returns `VERDICT=OK SESSION=0 WEEKLY=0` instead of `UNKNOWN` | **PASS=51 FAIL=0** |
| M4 | `guardrails.never_push` renamed to a key nothing reads — the never-push belt is gone | **PASS=51 FAIL=0** |
| M5 | Spawn validator replaced with `exit 0` — every spawn approved unreviewed | **PASS=51 FAIL=0** |
| M6 | Terminal.app's `send/key` refusal replaced with `exit 0` — the engine silently believes it typed | **PASS=51 FAIL=0** |
| M7 | Ticket fence/sentinel neutraliser gutted (prompt injection via ticket body) | **PASS=50 FAIL=1** (H-44) |

The one mutation caught, M7, is caught by the one test in that area that **executes**
`harness-tickets.sh render` and inspects its output. M1 is the sharpest illustration: the test named
for that exact behaviour, `H-50 stall nudge git cross-check + blocked skip`, is three `grep`s for
string literals in `harness-run.sh` —

```
grep -q 'git_recent "$cwd"' "$ROOT/bin/harness-run.sh" || f="no git_recent in watch"
grep -q 'esc to interrupt'  "$ROOT/bin/harness-run.sh" || f="no esc-to-interrupt skip"
grep -q 'blocked.done'      "$ROOT/bin/harness-run.sh" || f="no .blocked skip"
```

— so it stays green while the nudge it is named for does nothing. **The rule that follows is the
whole reason this corpus exists: a test that does not execute the thing it is named for is not
evidence about that thing.** Every entry below therefore carries a `Mutation:` line — the specific
defect that must turn that test red. A test admitted to the rebuild's suite without a demonstrated
red is not admitted.

### 1.3 A documented fix is absent from the source, still

VERIFIED. FIELD-NOTES §12.6 records that the ticket-id allocator's lock "landed only in the
installed plugin copy and not in the source repository, so it reverts on the next sync". In
`plugins/harness/bin/harness-tickets.sh` today, `l_add()` allocates ids as:

```
n=$(( $(find "$TDIR" -maxdepth 1 -name '[0-9]*-*.md' | sed 's|.*/||; s|-.*||' | sort -n | tail -1 | sed 's/^$/0/') + 1 ))
```

read-then-write with no lock of any kind. `grep -nE 'lock|flock|LOCK'` over that file returns only
the word `blocked`. The fix described in `HARNESS-TICKET-ID-ALLOCATION.md` and issues `#37`/`#169`
is **still missing from the repository**, thirteen days after the field notes recorded it missing.
This is entry F-49 below and it is not hypothetical.

### 1.4 Three further structural claims confirmed against source

- **No single-orchestrator guard exists.** VERIFIED: `grep -rniE 'already running|pidfile|singleton|another orchestrator|one orchestrator' bin/*.sh` returns nothing. The invariant the owner states as non-negotiable (R1-10, "якщо раптом одночасно два якісь оркестратори працюють, то це не окей") has no implementation to inherit.
- **Nothing measures context.** VERIFIED: grepping `bin/*.sh` for `compact|ctx=|context.?window|percent` returns only `harness-limits.sh` **token-quota** percentages. Context fullness — a first-class requirement in R1-08 — has no code at all.
- **The control file is destroyed every tick.** VERIFIED: `harness-run.sh:226` `: > "$run/state/attention.tmp"` and `:361` `mv … attention.tmp … attention`. Anything another process appends is gone within one interval, exactly as FIELD-NOTES §2.1 records.

### 1.5 One experiment was contaminated, and it is worth recording why

The first run of M3 reported `FAIL H-39`, a test unrelated to the mutation. Investigation showed the
copy's `hlib.sh` had been altered by something other than my mutation — `cfg_int`'s
`''|*[!0-9]*)` guard had been narrowed to `'')`. The scratchpad is shared with sibling agents in
this workflow. The experiment was redone in a `mktemp -d` directory with a verified-clean baseline,
and M3 then passed all 51. **Recorded because it is itself a corpus-relevant failure mode**: a test
run whose working tree was modified by a concurrent actor produced a confident, wrong,
deterministic-looking result, reproducible three times in a row. See F-71.

---

## 2. The substrate this corpus requires

Most entries below cannot be tested by grepping and must not cost a paid API call. They need four
deterministic doubles, all local, all free. Naming them once here keeps each entry short.

- **`SESSION-DOUBLE`** — a fake agent session: a process with a tty (a `tmux` pane or a pty via `script`), a scriptable screen buffer, a controllable "shell count" and "esc to interrupt" status line, a transcript file, and a recorded inbox of everything actually submitted to it. It runs no model. It is the single highest-value piece of test infrastructure in this document: it converts roughly thirty of the entries below from untestable to a sub-second unit test.
- **`CLOCK-DOUBLE`** — injectable now/epoch, so every timeout, reset, staleness and six-hour-rule entry is testable without waiting. Requires the production code to take time from one seam, never from a bare `date` call.
- **`PROVIDER-DOUBLE`** — a local HTTP stub for each platform's usage/quota endpoint that can return valid JSON, malformed JSON, `401`, a hang, and a reset timestamp. Replaces every live quota call in the suite.
- **`WORLD-DOUBLE`** — a scratch git repo, a fake container runtime (a script that records `docker`-shaped invocations), and a process table the tests can populate. Blast-radius entries assert against what the recorder saw, never against real containers.

A fifth, optional tier — **`LIVE-SMOKE`** — runs a handful of entries against one real session on one
real account, gated behind an explicit flag, never in `tests/run-all.sh`. Justified only for the
entries marked `Substrate: LIVE` below, which are the ones where the failure is a property of a real
vendor CLI and a double would only test the double.

**Cost rule applied throughout:** no entry in Tiers 1–3 requires a paid API call. The `LIVE` marks
number four, all optional, all opt-in.

---

## 3. How the ranking works

Rank is the probability the failure **recurs in the rebuild**, given what ANALYSIS-01 says the
rebuild will be. It is not severity. The driver is whether the rebuild keeps the mechanism that
produced the failure.

- **Rank A — near-certain.** The requirement document preserves the exact mechanism, and often makes it load-bearing where it used to be incidental. Nine of the Rank A entries are failures of mechanisms the owner has now made mandatory.
- **Rank B — likely.** The mechanism returns in a new form; the specific bug depends on implementation choices not yet made.
- **Rank C — conditional.** Recurs only under a configuration the user may or may not choose (a board backend, worktrees, docker, a particular platform).

A cross-reference to the requirement each entry threatens is given as `→ R1-nn` / `→ Дn`.

---

## 4. Rank A — near-certain recurrence

### Family 1 — Delivery: the orchestrator believes it spoke, and it did not

This family is the single largest in the record and the most dangerous in the rebuild, because
R1-08 raises it from an annoyance to a guarantee: *"повинен бути механізм, який гарантовано робить
цю дію"*. The previous generation's only channel into a running session was typing at a tty, and
FIELD-NOTES records **five separate instructions that were never delivered** (§1.3), plus three more
delivery failures found in a second sweep (§12.1). Every entry here is about the gap between *sent*
and *arrived*.

---

**F-01 · A bare Enter does not submit text already on the input line**
`→ R1-08, R1-09, Д12` · CLAIMED (FIELD-NOTES §1.3, §1.4; measured twice at `03:26:34Z` and
`05:21:06Z`) · Rank **A**

- **Precondition.** A session has text sitting on its input line, unsent — put there by a previous `send`, by a background task, or by a human.
- **Trigger.** The watch loop decides the session is stale and issues its escalation: `key <tty> enter`.
- **Wrong behaviour.** The text is still on the line afterwards. The engine logs `watch: nudged <name>` and treats the session as poked. Nothing was submitted; the session's transcript gains no user message.
- **Why it escaped.** The engine has no read-back. Success was the exit status of the terminal driver, which reports whether the keystroke was *sent*, not whether the session *received a turn*.
- **Assertion.** Given a `SESSION-DOUBLE` whose input line is pre-loaded with `XYZ`, after the nudge path runs: the double's **submitted-inbox must contain exactly one new entry**, and the input line must be empty. A nudge that leaves the inbox unchanged must raise a delivery failure, not log success.
- **Substrate.** `SESSION-DOUBLE`.
- **Mutation that must fail it.** Replace the delivery primitive with a no-op that returns 0. The test must go red. (This is exactly M1 above, which the old suite passed.)

---

**F-02 · `send` destroys whatever was pending on the line**
`→ R1-08, Д12` · CLAIMED (§1.3) · Rank **A**

- **Precondition.** Unsent text on the input line — in the worst recorded case, a human operator's own instruction.
- **Trigger.** Any automated `send <tty> "<text>"`.
- **Wrong behaviour.** `send` types its own text over the pending text and submits; the pending instruction is destroyed with no record that it ever existed. FIELD-NOTES §11.2 records two real operator instructions — `push master` and `carry on with the queue` — sitting unsubmitted while the engine logged them as nudged.
- **Assertion.** Before any write to a session, the delivery layer must **read the input line and refuse to write when it is non-empty**, surfacing the pending text to the control channel instead. Test: pre-load `PENDING`, call `send "NEW"`, assert the call returns a distinct "line busy" status, the double's inbox is unchanged, and `PENDING` is still on the line and reported.
- **Substrate.** `SESSION-DOUBLE`.
- **Mutation.** Remove the pre-write emptiness check. Red.

---

**F-03 · `send` fails silently above roughly 200 characters**
`→ R1-08, R1-09` · CLAIMED (§12.1; an ~1100-char message vanished with no error, a ~450-char version
of the same message landed) · Rank **A**

- **Precondition.** An instruction longer than the terminal driver's undocumented ceiling.
- **Trigger.** `send` with a long payload — precisely the shape of a post-compact re-orientation prompt, which R1-08 makes mandatory ("чи відправляється якийсь промпт одразу після компакту").
- **Wrong behaviour.** Exit 0, nothing appears, nothing logged. Note the two data points disagree about where the ceiling is (200 vs 450 landed); the ceiling is unknown, which is itself the finding.
- **Assertion.** Two tests. (a) A **round-trip length sweep** at 10/100/200/500/1000/2000/5000 characters against each terminal backend, asserting every payload arrives byte-identical in the double's inbox, and that any backend-imposed limit is **discovered and recorded at startup**, not assumed. (b) Any payload exceeding the discovered limit must be chunked or rejected loudly — never truncated silently.
- **Substrate.** `SESSION-DOUBLE` for the contract; `LIVE` (optional) for the real per-backend ceiling.
- **Mutation.** Make the transport drop anything over N bytes and return 0. Red.

---

**F-04 · A recovery attempt destroys the instruction it is recovering**
`→ R1-08` · CLAIMED (§12.1; `key enter` did nothing, then `send " "` cleared the line without
submitting, and the pending text was confirmed absent from the transcript) · Rank **A**

- **Precondition.** A delivery is known to have failed and an automated recovery runs.
- **Trigger.** The recovery ladder tries a second primitive.
- **Wrong behaviour.** Each rung damages the state the previous rung left. Net effect: the instruction is gone and both rungs reported success.
- **Assertion.** The recovery ladder must be **transactional against a captured copy**: capture the pending line, then attempt recovery, then assert the captured text is either in the inbox or still on the line. A ladder that can end with the text in neither place must fail the test.
- **Substrate.** `SESSION-DOUBLE`.
- **Mutation.** Insert a rung that clears without submitting. Red.

---

**F-05 · A background task re-invoking a session discards text on the idle line**
`→ R1-09, R1-11` · CLAIMED (§1.3) · Rank **A**

- **Precondition.** Text on an idle input line; a background job in that session completes and re-enters the session.
- **Trigger.** The re-invocation.
- **Wrong behaviour.** The pending text is discarded by the client itself — no actor in the orchestrator did it, so no log anywhere records it.
- **Assertion.** Delivery must be **confirmed from the session's own transcript**, not from the screen. Test: write to a double, then have the double simulate a background re-invocation, then assert the delivery-confirmation step reports failure (because the transcript has no matching user message) rather than success-by-screen.
- **Substrate.** `SESSION-DOUBLE` with a transcript file.
- **Mutation.** Confirm delivery from the screen instead of the transcript. Red.

---

**F-06 · Enter never lands on the target pane; nothing detects it for 149 minutes**
`→ R1-09, R1-10` · CLAIMED (§12.1; the lane had finished 70 minutes before the stall was noticed, and
the owner eventually pushed master himself) · Rank **A**

- **Precondition.** A pane whose addressing has drifted — window renumbered, tab moved, tty reused.
- **Trigger.** Any delivery to that pane.
- **Wrong behaviour.** A 149-minute stall with no detection. The orchestrator's model of which pane is which was wrong and nothing checked.
- **Assertion.** Every session must carry an **identity token the orchestrator can read back off the pane** (a marker printed at boot, or the session id echoed into the prompt). Before any delivery: read the token, and refuse the delivery if it does not match the registry. Test: re-point the double's tty to a different session and assert the delivery is refused with an identity-mismatch error, not performed.
- **Substrate.** `SESSION-DOUBLE`.
- **Mutation.** Skip the identity read-back. Red.

---

**F-07 · The log records "nudged" for a delivery that did not happen**
`→ Д11, R1-10` · CLAIMED (§1.4, §11.2) · Rank **A**

- **Precondition.** Any of F-01 to F-06.
- **Trigger.** The engine writes its log line from the *attempt*, not the *outcome*.
- **Wrong behaviour.** The run's own audit trail is false. This is the mechanism that makes every other delivery bug invisible in post-mortem — and R1-06 part 2 makes the state record load-bearing for resume ("в нас в реєстрі має записуватись кожен стан"). A lying record poisons recovery.
- **Assertion.** No log line may claim an action until the action is confirmed by an independent read. Test the log text directly: run the nudge path against a double rigged to swallow input, and assert the emitted record says `delivery-failed`, and that **no** record says `nudged`/`sent`/`delivered`.
- **Substrate.** `SESSION-DOUBLE`.
- **Mutation.** Move the log line above the confirmation. Red.
- **Note.** This generalises to F-52 (an audit log holding 26 refusal events that never occurred) and is the same defect class as F-29/F-36: *reporting success from an attempt rather than an effect*.

---

**F-08 · Compact only lands when the target has no shell running**
`→ R1-08` · CLAIMED (§1.2; three attempts on one session in one day — with shells running the command
was consumed as an ordinary message and the session drifted 91%→95% and auto-compacted) · Rank **A**

- **Precondition.** The target session has one or more child shells running.
- **Trigger.** The context watch types `/compact`.
- **Wrong behaviour.** The command is swallowed as ordinary text. No error. The session keeps filling. An empty input line is **not** sufficient — the discriminator is the shell count in the session's own status bar.
- **Assertion.** The compact procedure must **gate on the shell count read from the status line**, and must verify the outcome by re-reading the context percentage. Test: double reports `1 shell`, assert compact is deferred and reported as deferred; double reports `0 shells`, assert compact is attempted and that a post-condition read of the percentage is performed. A compact path that reports success without a percentage re-read fails.
- **Substrate.** `SESSION-DOUBLE` with a scriptable status line.
- **Mutation.** Remove the shell-count gate. Red.
- **Design note.** R1-08 also allows a **custom skill** or a full orchestrator relaunch instead of `/compact`, and allows per-provider variation. The gate is a property of *this* mechanism; the test that generalises is F-09.

---

**F-09 · No delivery receipt exists at all — the general case**
`→ R1-08 ("гарантовано"), R1-09, Д12` · VERIFIED by absence (no confirmation step exists anywhere in
`bin/*.sh`; every delivery path ends at the terminal driver's exit status) · Rank **A**

- **Precondition.** Any instruction to any session on any platform.
- **Trigger.** Normal operation.
- **Wrong behaviour.** "Sent" and "arrived" are the same variable. Eight distinct bugs above are all instances of this one missing abstraction.
- **Assertion — the contract test the rebuild should write first.** Define one operation, `deliver(session, text) -> Delivered | Refused(reason) | Failed(reason)`, and assert **as a property, across every configured platform adapter and every terminal backend**: after `Delivered`, the text appears in that session's transcript as a user turn within a bounded time; after `Refused` or `Failed`, the session state is unchanged and nothing was consumed. Run this same property table against every adapter — it is the platform-feasibility check the owner ordered as instruction **I1**.
- **Substrate.** `SESSION-DOUBLE` per adapter; `LIVE` (optional) once per adapter per release.
- **Mutation.** Any adapter that returns `Delivered` without a transcript read must fail the shared property test.

---

### Family 2 — The control file: the channel the rebuild depends on most

ANALYSIS-01 makes a watched file the backbone of three separate requirements — account reassignment
(R1-07), stop commands (Д12: `stop-hard`/`stop-soft`/`stop-custom` "записує у файл, який оркестратор
читає кожен тік"), and mid-run behaviour overrides (Д7). The previous generation had exactly this
shape and it silently ate every write.

---

**F-10 · The control file is rebuilt from scratch every tick, destroying external writes**
`→ Д12, Д7, R1-07, Д6` · **VERIFIED in source** (`harness-run.sh:226` truncate, `:361` `mv` over the
live file) and CLAIMED in operation (§2.1: the context watch wrote corrections there all night and
discovered the loss only by grepping for a block it had written four minutes earlier) · Rank **A**

- **Precondition.** Any second process — a supervisor, a status command, the user's own `stop-soft`, a question-channel writer — appends to the file the orchestrator watches.
- **Trigger.** The next tick.
- **Wrong behaviour.** The write is gone within one interval. **Nothing errors.** The writer believes it delivered; the reader never saw it. FIELD-NOTES records a measured rebuttal, written while the orchestrator was weighing killing a 378-test suite at test 240, destroyed this way.
- **Assertion.** Separate the two directions. (a) **Inbound** (user/other → orchestrator) must be append-only or an atomically-replaced file the orchestrator **only reads**, never writes. Test: append a command, run N ticks, assert the command is still readable and was acted on exactly once. (b) **Outbound** (orchestrator status) must be a different path the orchestrator owns. Test: assert the tick loop never opens the inbound path for writing — assert it by **running the tick against a read-only inbound file** and requiring success, which a truncating implementation cannot achieve.
- **Substrate.** Filesystem only. Cheap, fast, and it is the highest-leverage test in the corpus.
- **Mutation.** Point the status writer at the inbound path. Red (the read-only test fails immediately).

---

**F-11 · The staging file is found truncated to zero bytes on every pass**
`→ Д12` · CLAIMED (§11.3, §11.6 — this was one of the two factors that compounded the 85-minute
runaway loop) · Rank **A**

- **Precondition.** A reader samples the file while the writer is between truncate and `mv`.
- **Trigger.** Any concurrent read, which for a watched file is continuous.
- **Wrong behaviour.** A reader legitimately observes an empty control file and concludes "nothing to do" — indistinguishable from a real empty state.
- **Assertion.** Readers must never observe a partial state: write to a temp path and `rename()` into place, and assert **atomicity under concurrency** — spawn a reader looping for the duration of 100 writes and assert it observed only complete, well-formed documents and never a zero-byte or truncated one.
- **Substrate.** Filesystem + a concurrent reader.
- **Mutation.** Replace the atomic rename with truncate-then-write. Red within a few iterations.
- **Design note.** "Empty" and "absent" must also be distinguishable from "unreadable". FIELD-NOTES §11.3's marker detector globbed the wrong directory and reported **zero markers** for several cycles — a false empty read, not an error (F-59).

---

**F-12 · Two copies of one channel fork, and a real question goes unseen**
`→ Д6, Д4` · CLAIMED (§12.5: `QUESTIONS.md` and `JOURNAL.md` forked into a worktree's own copy and an
owner-facing question sat invisibly for an hour) · Rank **A**

- **Precondition.** The default recommendation of Д4 — every task in its own worktree — plus Д6's question channel living as a file **inside the project**.
- **Trigger.** A session in a worktree writes to the channel by relative path.
- **Wrong behaviour.** It writes to *its worktree's copy*. The orchestrator watches the main checkout's copy. The question is invisible; the run waits on an answer nobody was asked for.
- **Assertion.** The channel path must resolve to **one absolute location independent of the writer's cwd**, and every writer must be tested from inside a worktree. Test: create a repo with two worktrees, have a simulated session in each write a question, assert the orchestrator's single channel reader sees both. Additionally assert that a channel path that resolves differently from two cwds is **rejected at configuration time**, which is the R1-04/R1-17 "verify before you run" rule applied here.
- **Substrate.** `WORLD-DOUBLE` (scratch git repo with worktrees).
- **Mutation.** Resolve the channel path relative to cwd. Red.

---

### Family 3 — Identity and lifecycle: two orchestrators, and sessions nobody owns

---

**F-13 · Two orchestrators alive at once**
`→ R1-10 (stated as an absolute), Д10` · **VERIFIED absent**: no guard of any kind exists in
`bin/*.sh` · Rank **A**

- **Precondition.** Any of: the health-check agent (R1-10) revives a run whose orchestrator is actually alive but quiet; a user runs the start command twice; a crash-recovery path fires while the original is paused inside a quota wait; a restart lands while executors are still running (Д10).
- **Trigger.** The second start.
- **Wrong behaviour.** The owner names the consequence himself — *"це буде просто нескінченний цикл оркестраторів"*. Both write the same registry, both claim the same tickets, both act on the same control file, and each may read the other's sessions as unowned. Note the adjacent real incident in §1.6: a `question`-role session's terminal title read `harness-question-q-screen-orchestrator` and **the product owner read it as a second orchestrator** — so even the human-facing signal was ambiguous.
- **Assertion.** Four tests, and this is the one place the corpus recommends a hard invariant rather than a detector.
  1. **Mutual exclusion.** Acquire an exclusive, OS-level lock (an `O_EXCL` file holding pid + boot time + run id, or `flock`) before any orchestrator action. Test: start two concurrently in a loop of 50 rounds; assert exactly one proceeds every round and the loser exits non-zero with a clear reason.
  2. **Stale-lock recovery.** Kill the holder with `SIGKILL`, assert the next start acquires the lock (pid dead ⇒ stale) and that it does **not** acquire it while the holder is merely stopped (`SIGSTOP`) — a paused orchestrator inside a quota wait must not be declared dead.
  3. **Pid reuse.** Give the lock a dead pid that has been reused by an unrelated process; assert the boot-time/run-id field prevents a false "still alive" reading.
  4. **No false positive from naming.** Assert the liveness check keys on the lock, never on a process name, window title or `pgrep` pattern — see F-45 for why pattern matching over sessions is unsafe.
- **Substrate.** Process control only. No API calls.
- **Mutation.** Replace the lock check with a `pgrep -f orchestrator` test. Test 4 must go red — and it will, because the fake session's own prompt text contains the word.

---

**F-14 · A finished session is closed by nobody**
`→ Д3 ("щоби не залишати хвостів"), R1-16` · CLAIMED (§1.6: a question-role session stayed registered
and idle for **one day and four hours**, was logged `finished-awaiting-close` for hours by a watcher
with no remit to close it, and was closed by hand) · Rank **A**

- **Precondition.** A session completes its work. The actor that spawned it has moved on; the actor that can see it is finished has no authority to close it.
- **Trigger.** Completion.
- **Wrong behaviour.** The session holds a terminal, an account slot, a registry entry and a concurrency slot indefinitely, and confuses the human.
- **Assertion.** Every spawned session must have **exactly one named owner responsible for its close**, recorded in the registry at spawn. Test: complete a double, advance the clock past the reap threshold, assert the session is closed and deregistered by its recorded owner, and that the close is attributed in the log. Second test: kill the *owner*, assert the session is still reaped (ownership must fall back, never dangle) — this is the Д10 restart case.
- **Substrate.** `SESSION-DOUBLE` + `CLOCK-DOUBLE`.
- **Mutation.** Remove the fallback owner. The second test goes red.

---

**F-15 · A restart finds executors still alive and has no defined relationship to them**
`→ Д10, R1-16, R1-10` · CLAIMED (§1.6, §10.1 — the previous run ended with
`orchestrator dead + no live sessions for 3 ticks — tearing down`, and the directory holds `DEAD-RUN`
and `STOPPED`) · Rank **A**

- **Precondition.** The orchestrator dies; its workers do not.
- **Trigger.** A new orchestrator starts (R1-10: "start over" means restart the orchestrator, **not** redo the work).
- **Wrong behaviour.** Two failure directions, and the previous generation could produce both: adopt-and-duplicate (re-claim a ticket a live worker is still executing) or tear-down-and-lose (kill sessions that were mid-flight).
- **Assertion.** On start, the orchestrator must reconcile the registry against the live process table **before** claiming any ticket, and classify each surviving session as `mine-alive`, `mine-dead`, or `not-mine`. Tests: (a) a live registered worker must not have its ticket re-claimed; (b) a dead registered worker's ticket must be released back per the configured rule, exactly once; (c) an *unregistered* process must be classified `not-mine` and left alone — which is the R1-16 boundary, tested here rather than only in F-44/F-45.
- **Substrate.** `WORLD-DOUBLE` process table + registry fixtures.
- **Mutation.** Make reconciliation trust the registry without checking liveness. (a) or (b) goes red.

---

### Family 4 — Quota: read wrong, read never, and failing open

R1-06 makes quota handling a four-part requirement with hard/soft semantics and cross-platform
adaptation (including providers with no limits at all). The previous generation's quota layer failed
in six distinct ways, and the fix for one of them regressed twice.

---

**F-16 · Quota reads UNKNOWN for a whole run and the run proceeds anyway**
`→ R1-06` · CLAIMED (§11.7: `weekly_all=unreadable%` recurring across many separate days — six
consecutive ticks on `2026-09-06T03:01–03:19Z`, more at 08:36 and 22:48–23:03, single ticks on the
9th, 10th and 11th) and **VERIFIED in source**: `harness-limits.sh:95` defaults
`limits.on_unreadable` to `proceed` · Rank **A**

- **Precondition.** The usage endpoint is unavailable, rate-limited, returning malformed JSON, or the token is missing.
- **Trigger.** Every tick.
- **Wrong behaviour.** The verdict is `UNKNOWN`, the configured default is `proceed`, and the run continues blind for hours. The code is careful — it fails **closed to `UNKNOWN`** and its comment says "never OK-by-default" — and then the *policy* layer converts `UNKNOWN` into "carry on". The honest read and the unsafe action coexist.
- **Assertion.** Three tests. (a) `PROVIDER-DOUBLE` returns malformed JSON / `401` / a hang: assert the verdict is `UNKNOWN` in all three and never `OK`. (b) Assert `UNKNOWN` is **rate-limited into an escalation**: N consecutive unknown reads must trigger the configured notification and the configured stop semantics — a blind run must not be able to continue silently past a threshold. (c) Assert the run record distinguishes "quota was fine" from "quota was never read", so a post-mortem can tell them apart.
- **Substrate.** `PROVIDER-DOUBLE` + `CLOCK-DOUBLE`.
- **Mutation.** This is M3 above. Make `UNKNOWN` return `OK`. Test (a) must go red. **The old suite passed this mutation 51/51.**

---

**F-17 · Quota is measured against the wrong account**
`→ R1-06, R1-07` · CLAIMED (§11.7: *"my limits position was measuring the wrong account"*, with the
building account reading 94% weekly on the wrong pool) · Rank **A**

- **Precondition.** R1-07 explicitly requires roles on different accounts and per-role provider restriction. Multi-account is now the normal case, not the exception.
- **Trigger.** A quota read that resolves credentials from ambient state rather than from the role being metered.
- **Wrong behaviour.** A healthy reading for account X is used to decide about account Y. The run either stops needlessly or burns through a real limit.
- **Assertion.** Every quota reading must be **labelled with the account it came from**, and the consumer must assert the label matches the role it is deciding about. Test: configure two accounts, request a verdict for role `worker`, assert the returned record carries `worker`'s account identifier and that a mismatch is a hard error, not a warning.
- **Substrate.** `PROVIDER-DOUBLE` with two distinct identities.
- **Mutation.** Drop the account label from the record. Red.

---

**F-18 · The usage endpoint returns `authentication_error` for an extended stretch and nobody re-authenticates**
`→ R1-06, R1-07 ("verified to work before a run starts")` · CLAIMED (§11.7, `2026-09-02T13:52–15:14Z`,
blinding every cap read) · Rank **A**

- **Precondition.** A token expires mid-run. R1-07's config mechanisms — API key, subscription account, profile — all expire on their own schedules.
- **Trigger.** Time.
- **Wrong behaviour.** 82 minutes of blind operation. An auth error is a *different* condition from an unreadable endpoint and demands a different response (re-auth or escalate to the human), yet both collapsed into `UNKNOWN`.
- **Assertion.** The quota layer must return a **typed error**, distinguishing `Unauthenticated` from `Unreachable` from `Malformed`. Test: assert `401` produces `Unauthenticated` and that this routes to the configured notification channel immediately rather than to the generic unknown path. Second test: the pre-run verification required by R1-07 must **exercise an authenticated call per configured account** and fail the run start on `401` — not merely check that a key is present.
- **Substrate.** `PROVIDER-DOUBLE`.
- **Mutation.** Collapse `401` into the generic unknown branch. Red.

---

**F-19 · A usage figure moves without any usage changing**
`→ R1-06, R1-07` · CLAIMED (§12.4: when the supervisor was repointed from one account to another
mid-run the weekly reading fell from 26% to 6% **from the account switch alone**) · Rank **A**

- **Precondition.** R1-07 requires account assignments to be changeable **mid-run** via the watched file, with soft/hard semantics.
- **Trigger.** An account reassignment.
- **Wrong behaviour.** Any consumer that tracks quota as a time series, or that reacts to a *drop*, sees a phantom event. A "we have headroom again" reading is manufactured by a config change.
- **Assertion.** Quota series must be keyed by account identity, and a reading for a different account must start a **new series**, never continue the old one. Test: record readings for account A, switch to B mid-run, assert the consumer's series for A is closed and B's begins fresh, and assert no threshold-crossing event is emitted at the switch.
- **Substrate.** `PROVIDER-DOUBLE` + config fixture.
- **Mutation.** Key the series by role instead of account. Red.
- **Adjacent, same root.** §8 records that a mid-run account move required editing a second script in the same change because it watched the watched account **by path**, and that a session already booted keeps the account it booted with. Test both: (a) no component may resolve an account by hard-coded path; (b) after a soft account change, assert already-running sessions are still attributed to their **boot** account in the registry, and only new spawns use the new one.

---

**F-20 · A detached process does not inherit the environment the quota read needs**
`→ R1-06, R1-10 (the health-check agent is by definition detached)` · CLAIMED (§12.4:
`harness-limits.sh verdict` returns `UNKNOWN` unless called with `HARNESS_ROLE=<role>` prefixed,
because a session's environment deliberately withholds the usage token; and three detached scripts
must export the `gh` account themselves because `launchd` and `nohup` start with no environment) ·
**VERIFIED in source**: `harness-limits.sh:21` `[ -n "${HARNESS_ROLE:-}" ] && ec=$(cfg ".accounts.$HARNESS_ROLE.env_command" '')` · Rank **A**

- **Precondition.** The orchestrator's watchdog, health-checker or supervisor runs under `launchd`, `nohup`, `cron`, or a scheduled agent — all of which R1-10 requires ("запускати якогось агента раз в N годин на якійсь іншій підписці").
- **Trigger.** Normal start.
- **Wrong behaviour.** The component silently degrades: `UNKNOWN` quota forever, or `gh` resolving the wrong account, or the wrong repository. The degradation is **indistinguishable from the healthy case** to everything downstream.
- **Assertion.** Every detached entry point must be tested under a **scrubbed environment** — `env -i` plus only what it is declared to need — and must either succeed or fail loudly at startup. Test: run each entry point under `env -i`; assert it does not silently produce a degraded-but-plausible result. This is a cheap, high-yield, fully local test and it generalises to the `gh`-account and repo-resolution cases.
- **Substrate.** Process control + `PROVIDER-DOUBLE`.
- **Mutation.** Remove an explicit environment export from a detached script. Red.
- **Note.** The cleaner structural fix — every component declares its required environment and the launcher materialises it — is testable as a property: for each component, `declared_env ⊇ actually_read_env`, asserted by running under `env -i` with only the declared set.

---

**F-21/F-22/F-23 · The pause path's three-step regression**
`→ R1-06, Д12` · CLAIMED (§11.7, issues `#65`, `#73`, `#82` — the last still open) · Rank **A**

This is one bug fixed twice, badly, and it is the strongest argument in the whole record for
state-machine tests over example tests. Three entries, one fixture.

- **F-21 (`#65`).** *Precondition:* the quota API is unreadable, so the pause path uses its wall-clock fallback. *Trigger:* any pause. *Wrong behaviour:* the fallback epoch was pinned to a fixed **past** timestamp, so the resume condition `now >= resume_at` was true immediately and an unreadable read **resumed a paused run at once** — the exact opposite of pausing. *Assertion:* property test — for all reachable states and all clock values, `paused` must imply `resume_at > pause_at`, and a resume must never occur in the same tick as the pause. Assert with `CLOCK-DOUBLE` over a swept range including the epoch, far past, far future and DST boundaries.
- **F-22 (`#73`).** *Precondition:* the fix placed the new epoch lookup **between** the two writes that record a pause. *Trigger:* a restart landing in that window. *Wrong behaviour:* the restart read `STOP` present without its companion marker and interpreted it as a **manual owner stop**, so it exited instead of resuming. *Assertion:* crash-consistency test — for **every** instruction boundary in the pause path, simulate a crash there, restart, and assert the recovered state is one of the legal states and never "manual stop" when no human issued one. Implement by writing the pause path so its steps are enumerable, then looping over crash points. This is the test that would have caught both `#65` and `#73`.
- **F-23 (`#82`, open).** *Precondition:* the writes were serialised, but the `STOP` write remains unconditional on the marker write succeeding. *Trigger:* a failed marker write (disk full, permissions, a truncation as in F-11). *Wrong behaviour:* an **unattributed `STOP`** is left on disk; the run stops and nothing records who or why. *Assertion:* a stop record without an attribution field must be rejected by the reader as corrupt and escalated, not obeyed. Test: write a stop marker with the attribution missing, assert the orchestrator escalates rather than silently stopping. Then assert the writer cannot produce that state: inject a failure into the marker write and assert **no** `STOP` is left behind.
- **Substrate.** `CLOCK-DOUBLE` + filesystem fault injection. No API calls.
- **Mutation.** Reintroduce each of the three historical bugs in turn; each must turn its own test red. **This trio is the single best acceptance test for the rebuild's state layer — if the suite catches all three, the state machine is genuinely covered.**

---

### Family 5 — Liveness: work that is not work, and stalls that are not stalls

R1-09 delegates this entirely to the orchestrator's judgement — *"Агент сам повинен це вирішувати"* —
with no fixed timeout ladder. That raises the stakes on the **signals** that judgement is built
from, because the previous generation's signals were all forgeable.

---

**F-24 · Heartbeat staleness read as a stall on a healthy session**
`→ R1-09` · CLAIMED (§1.5: six false nudges in one run — `v-phase-10`, `w-phase-13`, the orchestrator
twice, `v-phase-12`, `w-phase-15`, every session healthy at the time; §11.3: `STALLED` raised against
demonstrably healthy sessions **eight or more times across about seven hours**; §12.3: 33 nudges total)
· Rank **A**

- **Precondition.** A session heartbeats **between** turns. A validator running a 14-minute suite, or a worker in a long turn, does not heartbeat at all.
- **Trigger.** Any long turn.
- **Wrong behaviour.** The watch treats a long turn as a stall and intervenes — and intervention means typing, which means F-01 to F-05. **The false positive is the delivery bug's trigger.** FIELD-NOTES §11.2 records a stranded `continue` sitting beside a live Playwright run it could have corrupted.
- **Assertion.** No single signal may authorise an intervention. Test a **decision table** over the cross-product of (heartbeat age, mid-turn indicator, recent output, recent git/file activity, child-process activity): assert that every combination where *any* progress indicator is positive yields `no-action`, and that the healthy-long-turn row specifically yields `no-action`. Record the six real false-positive cases from the run as named fixtures with their actual observed signal values.
- **Substrate.** `SESSION-DOUBLE` + `CLOCK-DOUBLE` + fixture table.
- **Mutation.** Drop any one input from the decision table. Its fixture rows go red.
- **Note.** A false-positive **rate** is also assertable: replay the run's recorded signal traces and require zero interventions on the sessions that were retrospectively healthy.

---

**F-25 · A shell that can never exit reads as work**
`→ R1-09` · CLAIMED (§2.2: a lane held one shell running `until grep … sleep 5` against a file that had
finished being written forty-five minutes earlier — the pattern could never match, the loop could never
end, and no check would ever have called that session parked) · Rank **A**

- **Precondition.** Shell count is used as a busy signal (and per F-08, it is also the compact gate — so this bug **blocks compaction too**).
- **Trigger.** A polling loop whose predicate is already unsatisfiable.
- **Wrong behaviour.** Permanent, undetectable "busy". The session is neither stalled by heartbeat (its loop prints) nor idle by shell count. It is invisible to every detector simultaneously.
- **Assertion.** A busy signal must be **qualified by progress, not by existence**. Tests: (a) a child process alive for longer than a configured ceiling with no change to its output stream must be classified `suspect`, not `busy`; (b) a child whose command matches a polling shape (`until`/`while` + `sleep`) and whose target has not changed since before the loop started must be classified `suspect`; (c) assert the classification is reported, because R1-09 gives the orchestrator the decision — the test's job is to guarantee the orchestrator is **told**, not to prescribe what it does.
- **Substrate.** `WORLD-DOUBLE` process table with scriptable child processes.
- **Mutation.** Classify on existence alone. (a) and (b) go red.
- **Related, same family.** §2.2 also records a lane accumulating **58 concurrent child shells**, each a `sleep 590` poll, spawned every two minutes for two hours — ~75 MB and 0% CPU, but each returning output into the session and eating its context. Assert a per-session cap on concurrent children with escalation on breach.

---

**F-26 · A retry loop against an unreachable dependency is indistinguishable from working**
`→ R1-09, Д5` · CLAIMED (§11.1: a subagent retried `docker desktop start` for **33 m 31 s** against an
unreachable daemon, spending **184k tokens**, found only by reading the log by hand) · Rank **A**

- **Precondition.** Any dependency that can be down.
- **Trigger.** The retry.
- **Wrong behaviour.** Heartbeats are fresh, output is flowing, tokens are burning, and zero progress is being made. Д5 exists for exactly this ("three identical failures → act per configuration") but nothing measured *identical*.
- **Assertion.** Implement Д5 as a tested rule: **N structurally identical failures in a row** (normalised: command + error class, with timestamps and ids stripped) trigger the configured action. Tests: (a) three identical failures trigger exactly once, not three times; (b) three *different* failures do not trigger; (c) the normalisation strips volatile fields — feed three failures differing only in timestamp and assert they are recognised as identical; (d) the token/wall-clock spend of a retry loop is attributed to the loop and reported.
- **Substrate.** Fixture streams, no live calls.
- **Mutation.** Compare raw error strings instead of normalised ones. (c) goes red.

---

**F-27 · Idle with ready work and no lanes — "held" is not "parked"**
`→ R1-09, Д6, Д7` · CLAIMED (§10.2 `J-SUP-34`: the orchestrator sat idle **35+ minutes with eight
ready tickets and no lanes**, because the watcher classified it as "held" rather than "parked", so the
auto-nudge never fired; separately its heartbeat file had not moved since `2026-09-02T06:09:50Z`
despite real activity — a false *stale* reading in the same incident) · Rank **A**

- **Precondition.** A classification vocabulary with more than two states and no total coverage.
- **Trigger.** A state that is in the vocabulary but not in any action rule.
- **Wrong behaviour.** Silent inaction. Note this incident contains a false positive **and** a false negative on the same session at the same time — the detectors were wrong in both directions at once.
- **Assertion.** The state classification must be **total and mutually exclusive**, and every state must have a defined action (including an explicit `no-action`). Tests: (a) exhaustiveness — enumerate the state enum and assert every value maps to a rule, as a compile-time or startup assertion, not a runtime default; (b) the specific fixture — ready work present, zero lanes running, orchestrator idle — must produce an action, and this is worth encoding as a **global liveness invariant**: *ready work + free capacity + no progress for T ⇒ escalate*, asserted independently of the session classifier, so that a classifier bug cannot suppress it.
- **Substrate.** Fixture state + `CLOCK-DOUBLE`.
- **Mutation.** Add a new state to the enum without a rule. (a) goes red at startup.
- **Design note.** (b) is the highest-value single test in Family 5: it is a **backstop that does not depend on any detector being right**, and the record shows every detector being wrong at some point.

---

**F-28 · The only escalation is a nudge; no ceiling triggers anything stronger**
`→ R1-09, R1-17, Д5` · CLAIMED (§11.1: observed peaks before a nudge fired were 2808 s in one run and
**44791 s — about 12.4 hours** — in the other, with a single orchestrator and no lanes; the nudge is
re-armed only every 3600 s) · **VERIFIED in source**: `harness-run.sh:291` is a one-shot per hour and
no other escalation path exists · Rank **A**

- **Precondition.** A session that a nudge cannot fix (which, per F-01, is every session where the nudge does not submit).
- **Trigger.** Time passing.
- **Wrong behaviour.** The ladder has one rung. After it, nothing. 12.4 hours of a dead night.
- **Assertion.** The escalation ladder must be a tested, ordered sequence with **a terminal rung that reaches the human** through the R1-17 channel. Tests: (a) drive the clock forward against an unresponsive double and assert each rung fires in order at its configured threshold; (b) assert the final rung **always** fires — there is no path through the ladder that ends in silence; (c) assert the ladder is bounded: it cannot repeat forever without escalating (see F-40, F-42).
- **Substrate.** `SESSION-DOUBLE` + `CLOCK-DOUBLE` + a notification recorder.
- **Mutation.** Remove the terminal rung. (b) goes red.

---

### Family 6 — Success reported for work that did not happen

This is the family the owner was shown during the interview and **declined to act on**: R1-13 says
verification belongs to the configured process and the orchestrator imposes no checks of its own —
*"не роби обмеження те, що вся робота потім буде мати тести"* — and the evidence below was explained
to him [342] and did not change the answer.

That answer is respected here, and it does not remove these entries, because they split into two
groups that the interview did not separate:

- **Checks on the work** (did the tests pass, is the code good) — the process's business. Out of scope, correctly.
- **Checks on the orchestrator's own bookkeeping** (did the step I was configured to run actually run; did the merge I reported actually move anything) — the orchestrator's own business, and the only thing that makes R1-06's "в реєстрі має записуватись кожен стан" true rather than decorative.

Every entry below is written as the second kind. None of them inspects the user's work or imposes a
quality gate. **This distinction should be put to the owner in round 2** — it is the one place where
this corpus does not simply follow ANALYSIS-01, and it is flagged rather than assumed.

---

**F-29 · A merge reports success and does nothing**
`→ R1-12, R1-13, Д4` · CLAIMED (§4.1) · Rank **A**

- **Precondition.** A tracked file is dirty in the working tree. In the observed case this was guaranteed: GSD rewrites `.planning/milestone.lock` during every phase and leaves it dirty. Any configured process with a lock or state file has the same property.
- **Trigger.** `git checkout master` aborts because of the dirty file; the merge command that follows then runs **on the phase branch against itself**.
- **Wrong behaviour.** It prints `Already up to date` and `Everything up-to-date`. **Both read like success.** Exit status 0. The phase did not reach the trunk. It was caught only because the orchestrator checked what `master` actually pointed at after the push instead of trusting the exit status.
- **Assertion.** A merge is not an exit code; it is a **ref movement**. Test: record the target ref's SHA before and after; assert the post-merge SHA differs, that the source SHA is an ancestor of it, and that the operation reports failure when the ref did not move. Then the fixture that reproduces the original: a scratch repo with a dirty tracked file, run the merge path, assert it **fails loudly** rather than reporting `Already up to date`.
- **Substrate.** `WORLD-DOUBLE` scratch git repo. Fast, free, fully deterministic.
- **Mutation.** Report success on exit status 0. Red.
- **Note.** This is the archetype of the whole family: *an operation that asserts its attempt succeeded rather than that its effect occurred*. Compare F-07 (log says nudged), F-36 (`SYNTAX OK` with nothing written), F-52 (audit log of events that never happened).

---

**F-30 · A step in the configured process is silently skipped, and the artefact self-attributes**
`→ R1-13, R1-03, R1-06 part 3` · CLAIMED (§11.4: GSD's verify stage was silently skipped for
**phases 14 to 18**, each `NN-VERIFICATION.md` self-attributing with
`verified_by: the lane that built the phase`; the cause was an orchestrator generalising a narrow
`council-advisor` warning into "every GSD agent"; **no automated check caught it — manual review did**)
· Rank **A**

- **Precondition.** R1-03 gives the user a configured step list (GSD, superpowers, or custom, with no mixing). The orchestrator's job is to run those steps.
- **Trigger.** Anything that makes the orchestrator skip a step — a misgeneralised warning, a crash, a model's judgement call.
- **Wrong behaviour.** Five phases shipped with builder-only verification. The artefact that should prove independence instead **records its own dependence in a field nobody read**. Five phases' worth of work carried a false quality signal to the trunk.
- **Assertion.** This is bookkeeping, not verification. For each ticket, assert the orchestrator's own record shows every step of the configured process reached a terminal state, and that any step which did **not** run is recorded as `skipped` with a reason. Tests: (a) configure a three-step process, cause step 2 to be skipped, assert the ticket cannot reach `done` with an unaccounted step; (b) assert an artefact whose producer identity equals the ticket's executor identity is **flagged as non-independent** when the configured process declares that step independent — a one-line identity comparison, no judgement about the work itself; (c) assert the run summary lists per-ticket step coverage, so five skipped phases are visible without manual review.
- **Substrate.** Fixture process definitions + a recorder. No model calls.
- **Mutation.** Let a ticket close with a step in state `unknown`. (a) red.

---

**F-31 · Work reaches the trunk before its validation ran**
`→ R1-12, R1-13` · CLAIMED (§4.2, §11.4: `phase-21` went from the lane's `pr-ready` marker straight to
the merge at `2fb5301` because the orchestrator never spawned the validator; every other phase went
worker → validator → merge; the orchestrator caught its own error within about a minute and ran the
validation after the fact, with the verdict binding on whether the merge stood — it passed) · Rank **A**

- **Precondition.** A step ordering that exists only in the orchestrator's intention.
- **Trigger.** A single missed spawn.
- **Wrong behaviour.** The ordering constraint was real but unenforced. It happened to end well; it is not guaranteed to.
- **Assertion.** Step ordering must be **data the orchestrator enforces**, not prose it follows. Test: declare `merge` as requiring `validate` complete; attempt the merge with `validate` in state `not-started`; assert refusal. Then assert the *recovery* path the run actually used is also supported and tested: validate-after-the-fact with the verdict binding on whether the merge stands, including the revert path on a failing verdict.
- **Substrate.** Fixture process graph + `WORLD-DOUBLE` git.
- **Mutation.** Make the dependency advisory. Red.
- **Note.** R1-12 says there is no universal gate and the trunk policy is the user's — correct, and this test does not impose one. It asserts that *whatever the user declared* is enforced.

---

**F-32 · A memory-truncated test run reports a clean-looking result**
`→ R1-13, R1-06` · CLAIMED (§11.5: **346 passed, 0 failed** — caught only by arithmetic, because 346
plus 35 never-reached does not equal the declared 382, and the missing test was not even in the
never-reached list; it followed host memory pressure of ~75 MB free and 2378 M of 3072 M swap that had
killed the watcher's own collection task eight minutes earlier) · Rank **A**

- **Precondition.** A runner that can be killed mid-stream and still emit a well-formed-looking summary.
- **Trigger.** Memory pressure, OOM, a timeout.
- **Wrong behaviour.** `0 failed` is true and meaningless. **The pass count is not the assertion — the arithmetic is.** A human caught this with subtraction.
- **Assertion.** Whenever the configured process reports counts, assert the **conservation identity**: `declared_total == passed + failed + skipped + not_reached`. Any discrepancy is a hard failure of the *run*, independent of any verdict about the code. Tests: (a) the exact historical numbers — 382 declared, 346 passed, 0 failed, 35 never-reached — must produce a failure; (b) a truncated output stream (killed mid-run) must not be accepted as a result; (c) a run whose process exited on signal must be recorded as `incomplete`, never as its printed summary.
- **Substrate.** Fixture output files + a killable fake runner.
- **Mutation.** Accept the summary line without the arithmetic. (a) red.
- **Boundary note.** This is squarely *bookkeeping about whether the step completed*, not an opinion about the tests. It applies only when the configured process emits counts, and does nothing when it does not — which satisfies R1-13/N2 ("може таке бути, що десь не буде тестів, і це також окей").

---

**F-33 · A collection crash reports "No tests found", which reads as zero rather than as failure**
`→ R1-13` · CLAIMED (§12.2: a Playwright spec importing `src/instrumentation.ts` crashes at collection
and reports `No tests found`) · Rank **A**

- **Precondition.** A runner that distinguishes "nothing matched" from "I crashed before I could look" only in its exit code, or not at all.
- **Trigger.** An import-time crash.
- **Wrong behaviour.** Zero tests, zero failures, exit that reads as fine.
- **Assertion.** A result of zero units must be treated as **suspect and reported**, never as success, unless the configured process explicitly declares zero as expected. Test: feed a `No tests found` output with a crash on stderr and assert the step is `errored`; feed a genuine zero-match with a clean exit and assert it is `zero-expected` only when declared.
- **Substrate.** Fixture outputs.
- **Mutation.** Map zero-units to success. Red.

---

**F-34 · A check exists only as prose and nothing runs it**
`→ R1-03, R1-13` · CLAIMED (§11.4: a records-drift check across seven handoff files exists only as
prose; issues `#50`, `#325`, `#324`) · Rank **A**

- **Precondition.** A configured process whose steps are described in a document rather than declared as executable units. R1-03 explicitly permits a custom process "з допомогою якогось ямл файлу" where the user defines the steps.
- **Trigger.** Configuration time.
- **Wrong behaviour.** The step appears in every plan and every report and has never executed once.
- **Assertion.** At configuration time, every declared step must **resolve to something runnable** and the resolution must be proven by a dry-run before the run starts — this is the R1-04/R1-07/R1-17 "verify before you run" rule applied to the process definition. Tests: (a) a step naming a non-existent command must fail configuration, not fail at 3 a.m.; (b) a step that resolves must be recorded with what it resolved to; (c) at run end, assert every declared step has a non-zero execution count or an explicit `skipped` reason.
- **Substrate.** Fixture configs.
- **Mutation.** Let an unresolvable step pass configuration. (a) red.
- **Note.** This is the single cheapest high-value test in the corpus and it directly serves the owner's "переконатися, що це працює" instinct (R1-17) without imposing any policy on what the steps are.

---

**F-35 · A sweep reports a false clean when run from the wrong directory**
`→ R1-03, Д4` · CLAIMED (§11.4: the drift check reports `OK, 0 files compared` from a subdirectory,
and a tracked-tree sweep claimed exit 0 against 1242 bytes of real diff) · Rank **A**

- **Precondition.** Д4's default recommendation — every task in its own worktree — makes "the process runs from an unexpected cwd" the normal case.
- **Trigger.** Invocation from a subdirectory or a worktree.
- **Wrong behaviour.** `0 files compared` is printed as `OK`. The scope was empty and the tool called that a pass.
- **Assertion.** **An empty scope is never a pass.** Test every sweep-shaped step from three cwds — repo root, a subdirectory, a separate worktree — and assert identical results; assert that a scope of zero items produces `inconclusive`, not `OK`. Generalise as a property across all configured steps: `result(step, cwd=root) == result(step, cwd=sub) == result(step, cwd=worktree)`.
- **Substrate.** `WORLD-DOUBLE` git repo with worktrees.
- **Mutation.** Print `OK` on an empty scope. Red.

---

**F-36 · A self-patch reports `SYNTAX OK` while its anchor never matched and nothing was written**
`→ R1-03, R1-10` · CLAIMED (§12.2, recorded as **the third such case that day**) · Rank **A**

- **Precondition.** Any automated edit that locates its target by pattern — `sed` anchors, string replacement, a model editing a file.
- **Trigger.** The anchor does not match (a rename, a reformat, a version drift).
- **Wrong behaviour.** `sed` succeeds at doing nothing. The validity check then runs against the **unmodified** file and passes. Two green signals, zero change. "Three such cases that day" indicates a systemic pattern, not an accident.
- **Assertion.** An edit must assert its **effect**: the file's hash changed, and the intended post-condition holds. Test: run an edit whose anchor cannot match and assert it fails; run one that matches and assert both hash change and post-condition. Never accept "the result is syntactically valid" as evidence that an edit occurred.
- **Substrate.** Filesystem fixtures.
- **Mutation.** Drop the hash-change assertion. Red.
- **Note.** F-29, F-36, F-07 and F-52 are one defect with four faces. If the rebuild adopts a single rule — **every action reports the observed effect, never the attempted operation** — one property test covering all mutating operations retires a large slice of this corpus.

---

## 5. Rank B — likely recurrence

### Family 7 — Context: unmeasured, and spent on nothing

---

**F-37 · Nothing measures context, and a session reaches 91% unobserved**
`→ R1-08` · **VERIFIED absent**: `grep -rniE 'compact|ctx=|context.?window|percent' bin/*.sh` returns
only token-quota percentages; the plugin's 33 config keys include `limits.pause_next_spawn_at` and
`limits.weekly_pause_at`, which are **quota** thresholds, not context thresholds · Rank **B**

- **Precondition.** R1-08 requires a user-set percentage threshold, per-session or per-provider, with soft/hard semantics and a **guaranteed** mechanism. None of that machinery existed.
- **Trigger.** Normal operation.
- **Wrong behaviour.** The context watch refilled 9%→91% in about ten hours; a worker reached 91% in three and a half hours; the orchestrator reached 64% after 30 hours. All of this was measured by a human reading screens. FIELD-NOTES notes the figure is available with **no new machinery** — it is on every session's own status line, and the watch already captures every screen each cycle.
- **Rank B rather than A** because the rebuild will certainly implement *something* here (R1-08 is explicit), so the recurrence risk is not "nothing exists" but "what exists is wrong" — the entries below.
- **Assertion.** (a) Parsing: feed recorded status lines, including the decimal-version and wrapped-line variants that broke the old parser (F-60), and assert the percentage is extracted or an explicit `unreadable` is returned — never a silent default. (b) Threshold: assert the configured soft/hard action fires at the configured percentage, once, with `CLOCK-DOUBLE`. (c) **Unreadability must escalate**, mirroring F-16: N consecutive unreadable context reads is a reportable condition, because a threshold that never fires is indistinguishable from a healthy session.
- **Substrate.** Recorded screen fixtures — free, and they already exist in the run's `state/screens/`.
- **Mutation.** Return a fixed 0% when parsing fails. (c) red.

---

**F-38 · A lane spends three quarters of its context window on polling**
`→ R1-08, Д11 (minimal tokens), Д8 (cheap models for watch duties)` · CLAIMED (§3.1, and it is the
most precisely measured record in the whole document: **3,466 of 3,626 Bash calls were the literal
command `echo idle`**, mean interval 2.54 s, ~1,400/hour, from `13:50:57Z` to `17:05:52Z`; cost
deduped by API response: **445k tokens of context added by the idle responses — 77% of all context
growth in that window against 135k from real work — 274k output tokens, 1.83 billion cached tokens
re-read**; the session reached 91%) · Rank **B**

- **Precondition.** A session waits for subagents by polling instead of ending its turn.
- **Trigger.** Model choice. Note carefully: **every other worker lane in the run — phases 1, 2, 10 through 18 — has zero `echo idle`.** Lanes 1 and 2 waited on 10 and 34 `Agent` calls without polling at all; lane 18 used `Monitor`. This lane had loaded `Monitor` via `ToolSearch` and never used it. Its prompt warned that subagents may hang, which is the likely cause of the defensiveness. It stopped within one minute of being told to end its turn — 18–21 calls/minute through `17:05`, then zero from `17:06`.
- **Wrong behaviour.** Three quarters of a context window and a quarter of a million output tokens consumed producing nothing, with every liveness signal green throughout.
- **Why this is Rank B and not C.** The trigger is a prompt that warns about hangs — and the rebuild's prompts will warn about hangs, because hangs are in this very corpus. The failure is *induced by the safety advice*.
- **Assertion.** (a) **Repetition detector**: N identical tool invocations within a window is a reportable condition on any session, asserted against the recorded transcript shape. (b) **Context-growth attribution**: assert the run record can state, per session, how much context growth came from repeated identical calls — the metric that made this diagnosable. (c) **Prompt regression**: a golden-fixture test that the waiting instruction given to workers names the non-polling mechanism explicitly; assert by mutation that removing it changes the fixture.
- **Substrate.** Transcript fixtures (`.jsonl`), already available.
- **Mutation.** Raise the repetition threshold above 3,466. (a) red against the recorded transcript.

---

**F-39 · The compact mechanism has no proof it ran**
`→ R1-08` · CLAIMED (§1.1, §10.2 `J-WATCH-01`) · Rank **B**

- **Precondition.** R1-08's demand for a **guaranteed** mechanism, plus the fact that a session cannot compact itself — `/compact` is typed into a session's terminal by another process, so the guarantee depends entirely on Family 1.
- **Trigger.** A threshold crossing.
- **Wrong behaviour.** Any of F-01 to F-08 makes the compact silently not happen, and the session keeps filling until the client auto-compacts on its own terms (observed: 91%→95%→auto-compact), losing the controlled handoff.
- **Assertion.** Compact is a transaction with a post-condition: capture the percentage, perform the mechanism, re-read the percentage, assert it fell; on failure, escalate. Tests: (a) the double does not compact — assert the procedure reports failure and escalates; (b) the double compacts — assert success is recorded with before/after values; (c) R1-08's alternative mechanisms (a custom skill, a full orchestrator relaunch, a post-compact prompt) satisfy the same post-condition contract, asserted as a shared property across mechanisms.
- **Substrate.** `SESSION-DOUBLE`.
- **Mutation.** Report success without the re-read. (a) red.

---

### Family 8 — Loops nothing internal can break

---

**F-40 · An 85-minute self-sustaining loop that nothing internal detected**
`→ R1-09, R1-17, Д5` · CLAIMED (§11.6, and it is the most instructive single incident in the record) ·
Rank **B**

- **Precondition.** A detector that matches text on a screen, where the screen can contain the detector's own subject matter.
- **Trigger.** The deterministic watch matched what looked like a usage-cap banner **inside the orchestrator's own wrapped prose**.
- **Wrong behaviour.** It pressed Escape and sent `continue` about every sixty seconds. Each zero-second turn left the screen unchanged, **so the same text matched again** — a closed loop with a fixed point. It ran from `2026-09-06T21:53:15Z` to `23:21:39Z`. Two things compounded it: the human-notification watchdog had already exited ("run finished") and was never restarted, and `state/attention.tmp` was truncated to zero bytes on every pass. **Nothing internal detected it.** It ended when an external `SIGTERM` reached the orchestrator. Line 5620 of the log reads `NO ONE IS BEING TOLD`.
- **Assertion.** Three independent tests, because this incident had three independent causes and any one of them would have broken it.
  1. **Loop bound.** Any corrective action taken against the same target with the same trigger must be counted; N repetitions without a change in the observed state must escalate and stop repeating. Test: a double whose screen never changes; assert the action fires at most N times and then escalates.
  2. **Fixed-point detection.** If an action's post-condition is "the screen changes" and the screen does not change, the action must be recorded as ineffective — the same effect-not-attempt rule as F-29/F-36.
  3. **Watchdog liveness.** The component that notifies the human must itself be supervised. Test: kill the notifier, assert it is restarted or its absence is escalated within a bounded time. (This is the "quis custodiet" case, and the log line `NO ONE IS BEING TOLD` is the acceptance criterion.)
- **Substrate.** `SESSION-DOUBLE` + `CLOCK-DOUBLE` + notification recorder.
- **Mutation.** Remove the repetition counter. (1) red.
- **Note.** §12.5 records a second instance — a **45-minute false-positive rate-limit-banner loop** on a healthy orchestrator, re-issuing resume kicks every 66 seconds. Two occurrences of the same shape in two runs is why this is Rank B and not C.

---

**F-41 · A component that exited is never restarted, and its silence reads as calm**
`→ R1-17, R1-10` · CLAIMED (§11.6: the human-notification watchdog had exited on "run finished" and
was never restarted, during the loop above) · Rank **B**

- **Precondition.** A supervising component with its own exit conditions.
- **Trigger.** A premature terminal condition.
- **Wrong behaviour.** The channel that would have told the human is gone, and its absence produces no signal — silence from a notifier is indistinguishable from nothing to report.
- **Assertion.** Notification channels must be **heartbeat-verified, not assumed**: assert the notifier is alive on a schedule and that its absence escalates through a second path. Test: kill the notifier, advance the clock, assert an alert arrives by another route. Combined with R1-17's "повинен лише переконатися, що це працює", assert a channel **round-trip at run start** — send and confirm, not just configure.
- **Substrate.** Process control + notification recorder.
- **Mutation.** Check the notifier's config instead of its liveness. Red.

---

**F-42 · A condition re-flagged 1085 times over five days**
`→ Д11, R1-17` · CLAIMED (§11.6: a dead run flagged
`STOPPED present with no run.complete — treating as an accidental teardown, not a finish` every three
minutes **for about five days**, 1085 times, unresolved) · Rank **B**

- **Precondition.** A detector with no memory and no resolution path.
- **Trigger.** A state that is detected but not actionable.
- **Wrong behaviour.** Perfect detection, zero effect, and 1085 log entries that train every reader to ignore that message. Note this is the same underlying state as F-23's unattributed `STOP`.
- **Assertion.** Every repeated finding must be **deduplicated with a count and escalated on persistence**, never re-emitted identically. Tests: (a) the same finding across 100 ticks produces one record with `count=100`, not 100 records; (b) a finding unresolved past a threshold escalates; (c) a finding that can never be resolved by any available action is reported as such at first detection.
- **Substrate.** Fixture ticks + `CLOCK-DOUBLE`.
- **Mutation.** Emit on every tick. (a) red.
- **Related.** §11.6 also records an unwedge process polling `run is stopped — holding` every 180 s for 32 minutes while doing nothing, and §12.3 records `context-watch`'s own collection task **OOM-killed twenty-six or more times** with host swap down to ~63 MB free, fixed only around cycle 380 by moving the collection into the foreground. Assert that a component's own subprocess deaths are counted and escalated (F-47).

---

**F-43 · A recovery component holds instead of acting, and never gives up**
`→ R1-10, Д7, Д12` · CLAIMED (§11.6: an unwedge process polled `run is stopped — holding` every 180
seconds for about 32 minutes while doing nothing) · Rank **B**

- **Precondition.** A recovery component whose precondition ("the run is not stopped") is not satisfied, with `hold` as its only response.
- **Trigger.** The run being in a state the recovery component was not designed for — in this case stopped, possibly by the unattributed `STOP` of F-23.
- **Wrong behaviour.** The component that exists to unwedge the run waits politely for 32 minutes for a condition that nothing will change. It is alive, logging, and useless — indistinguishable in every log from a component correctly waiting for a transient condition. R1-10 requires that a provider failure "не залишає ран зупиненим" and that something can revive a run **without the user's involvement**; a holding loop satisfies the letter and defeats the purpose.
- **Assertion.** Every waiting state must be **bounded and must name what would end it**. Tests: (a) a component in `hold` past its bound escalates through the R1-17 channel rather than continuing; (b) a component holding on a condition that no actor in the system can change must report that at first detection, not on a timer (the same rule as F-42c); (c) assert the hold record names the awaited condition, so a human reading one line can tell a transient wait from a permanent one.
- **Substrate.** `CLOCK-DOUBLE` + fixture states.
- **Mutation.** Remove the bound on the hold. (a) red.

---

### Family 9 — Blast radius: touching what it did not start

R1-16 is PARTIAL by the owner's deliberate choice, and he ruled out heavy isolation as
overengineering: *"я не хочу якихось детерміністського варіанту для цього … але дуже якийсь простий
та надійний варіант"*. Д3 adds that on finishing, the orchestrator stops **what it started** and
nothing else. The entries below are written as the cheap, simple version he asked for: **ownership
labels plus a refusal, not sandboxing.**

---

**F-44 · A destructive command lands on the default project**
`→ R1-16, Д3` · CLAIMED (§11.5: the owner's default stack was destroyed by a `docker compose down -v`
run with **no `COMPOSE_PROJECT_NAME` exported**, which landed it on the default project instead of a
lane project; `2026-09-11` ~22:51–22:53Z; detected only afterwards from image and volume timestamps;
**the actor was never identified**, and a session had refused that exact action as owner-only two
minutes earlier) · Rank **B**

- **Precondition.** A tool whose scope comes from an environment variable that a detached or re-entrant process does not inherit (the same root as F-20).
- **Trigger.** Cleanup — which Д3 makes a **mandatory end-of-run step**, so the rebuild will execute this class of command by design.
- **Wrong behaviour.** The command is well-formed and does exactly what it was told; the *scope* was wrong and the default was the owner's own stack. Irreversible (`-v` destroys volumes). No attribution, so no post-mortem was possible.
- **Assertion.** (a) **No destructive command may run with an implicit scope.** Test: invoke the cleanup path with the scope variable unset and assert it refuses rather than defaulting. (b) **Ownership label.** Everything the orchestrator creates must carry a run-id label at creation; cleanup enumerates by label and asserts every target carries it, refusing the whole operation if any does not. Test: put an unlabelled resource in the target set and assert cleanup aborts and reports. (c) **Attribution.** Every destructive action records actor, run id and target list *before* executing, so an unidentifiable actor is impossible by construction.
- **Substrate.** `WORLD-DOUBLE` fake container runtime recording invocations. No real containers, no daemon, free.
- **Mutation.** Let cleanup fall back to the default project when the variable is unset. (a) red.
- **Note.** This satisfies the owner's constraint: it is a label and a refusal, not isolation machinery.

---

**F-45 · A pattern kill over-matches the session whose prompt contains the pattern**
`→ R1-16, R1-10 (see F-13 test 4)` · CLAIMED (§11.8: `pkill -f 'playwright test'` killed an unrelated
lane, **because every lane's own prompt text contains that literal string**, so `pgrep`/`pkill` match
sessions rather than suites; `2026-09-05T12:11:51Z`; the killed worker was respawned 83 seconds later)
· Rank **B**

- **Precondition.** Agent sessions whose command lines contain their entire prompt — which is true of every platform in R1-07's list.
- **Trigger.** Any `pkill -f` / `pgrep -f` over a descriptive pattern.
- **Wrong behaviour.** The orchestrator kills its own or the owner's sessions while trying to clean up a subprocess. This is the mechanism by which a *liveness* check can become a *destructive* one.
- **Assertion.** Process targeting must be by **recorded pid with a verified parentage or ownership label**, never by command-line pattern. Tests: (a) create a double whose command line contains the target pattern and assert the cleanup does not select it; (b) assert selection is by pid from the registry plus a liveness/identity check (the F-13 pid-reuse guard applies); (c) a static check that no shipped code path uses `pkill -f`/`pgrep -f` with a non-anchored pattern — and this one may legitimately be a grep, provided a mutation adding such a call turns it red.
- **Substrate.** `WORLD-DOUBLE` process table.
- **Mutation.** Add a `pkill -f` call. (c) red — verify it, since the old suite's greps did not work this way.

---

**F-46 · Concurrent builds OOM-kill the owner's own container**
`→ R1-16, R1-05 (machine-resource awareness explicitly deferred)` · CLAIMED (§5.1, §11.5:
`<work-project>-app-1` on port 3000 was `OOMKilled` (exit 137) at `2026-09-13T03:29:01Z` while
`v-phase-21` ran two `docker compose up --build` at once on an 8 GB Docker VM; builds started
`03:28:30Z`, dead by `03:29:01Z` — **31 seconds**; restarted `04:01:35Z`; **detected only by
correlating timestamps with `docker inspect OOMKilled=true` — there was no live alert**) · Rank **C→B**

- **Precondition.** R1-05 lets the user set a concurrency maximum and **explicitly defers machine-resource awareness to later** — "ресурси машини, поки це заберемо, це добавимо в майбутнє". So the rebuild will ship with this deferred, by decision.
- **Trigger.** Two resource-heavy steps scheduled concurrently within the user's configured limit.
- **Wrong behaviour.** A process the orchestrator did not start is killed by memory pressure it caused. The boundary is violated **indirectly** — no command touched the owner's container.
- **Why it is ranked up.** R1-16's boundary requirement and R1-05's deferral are in tension. Being ranked here is the point: this is a **known accepted risk** that should be recorded as such rather than discovered again.
- **Assertion.** Given the deferral, the minimum testable obligation is detection and attribution, not prevention: (a) assert the run records, for every externally-killed process it can see, whether the kill coincided with its own resource-heavy steps — the correlation a human had to do by hand; (b) assert the end-of-run report lists any owner-visible casualty; (c) **if** a concurrency limit for heavy steps is implemented, assert it is enforced with a fixture of two heavy steps and limit 1. Also record FIELD-NOTES §5.2's measurement rule: swap **occupancy** is not a pressure signal on macOS; `memory_pressure -Q` is — so assert any future resource gate reads the right meter.
- **Substrate.** `WORLD-DOUBLE`.
- **Mutation.** Read swap occupancy as the pressure signal. (c) red, if implemented.

---

**F-47 · The watcher's own subprocesses are OOM-killed twenty-six times and it keeps reporting**
`→ R1-09, R1-10` · CLAIMED (§12.3) · Rank **B**

- **Precondition.** A monitoring component that forks its collection work.
- **Trigger.** Host memory pressure.
- **Wrong behaviour.** The collector dies; the watcher continues on stale or empty data and its output looks normal. Detection of everything else silently degrades.
- **Assertion.** A component must distinguish "collected and found nothing" from "collection failed". Test: make the collector fail; assert the cycle is marked `degraded` and that consumers do not treat a degraded cycle as evidence of health. Assert repeated degradation escalates (F-42).
- **Substrate.** Process control + fault injection.
- **Mutation.** Treat a failed collection as an empty result. Red.
- **Note.** Same defect as F-59 and F-35: **an empty result must never be read as a clean result.** That single rule covers three entries.

---

**F-48 · Orphaned resources left by a dead prior run**
`→ Д3, R1-16` · CLAIMED (§11.11: about **150 orphaned Docker volume pairs** left by a dead prior run) ·
Rank **B**

- **Precondition.** A run dies without reaching its cleanup step — which §10.1 shows is the normal way the previous runs ended.
- **Trigger.** Teardown, crash, or `DEAD-RUN`.
- **Wrong behaviour.** Resources accumulate across runs and contribute to F-46's memory pressure.
- **Assertion.** Cleanup must be **idempotent and resumable from labels alone**, not from in-memory state. Test: create labelled resources, kill the orchestrator without cleanup, start a new run, assert it can enumerate and reclaim the previous run's resources **by label** and that it refuses to touch anything unlabelled (F-44b). Assert a startup report of orphans from prior runs.
- **Substrate.** `WORLD-DOUBLE`.
- **Mutation.** Track resources only in memory. Red.

---

### Family 10 — State, and fixes that do not stick

---

**F-49 · A documented fix lives only in the installed copy and reverts on the next sync**
`→ R1-03, and the repo's own conventions` · **VERIFIED on this machine, still true today** (see §1.3
above: `l_add()` in `plugins/harness/bin/harness-tickets.sh` allocates ids with an unlocked
read-then-write; `grep` for any locking primitive returns nothing; FIELD-NOTES §12.6 and issues
`#37`/`#169` record the fix as applied to the installed copy only) · Rank **A**

- **Precondition.** A plugin that is installed from a marketplace and also developed in a source repository — exactly this repository's model.
- **Trigger.** A fix applied at 3 a.m. to the copy that is running, because that is the copy that is broken.
- **Wrong behaviour.** The fix works, is documented as landed, and is silently reverted by the next `/plugin update`. A reader of the documentation believes the bug is fixed. **Thirteen days later it is still unfixed in source.**
- **Assertion.** (a) A **drift test**: assert the installed copy and the source tree agree, run at session start and in CI, reporting any file that differs. (b) A **provenance test**: any documented fix must reference a commit in the source repository, and the doc build fails on a fix note with no commit. (c) For this specific bug, the concurrency test it should have had: N concurrent `add` operations must produce N distinct ids — the historical data gives the acceptance criterion directly, since **two concurrent adds produced two files under one id in five rounds out of five**, and a twenty-way add produced twenty files under three ids.
- **Substrate.** Filesystem + concurrent process spawning. Free and fast.
- **Mutation.** This one needs no mutation — **the bug is live**. Write test (c) first and watch it fail against the current source. That is the strongest possible demonstration that the corpus works, and it should be the rebuild's first committed test.

---

**F-50 · State labels left inconsistent — `blocked` is never removed**
`→ R1-04 (the board is a working surface the orchestrator writes to), Д2` · CLAIMED (§12.6:
`harness-tickets.sh done` leaves a previously blocked issue holding **two state labels**, seen twice) ·
**VERIFIED in source**: `gh_block()` removes `in-progress` and `ready` when blocking, but the `done`
path does not remove `blocked` · Rank **A**

- **Precondition.** R1-04 makes the board a working surface with user-overridable status names adapted to the configured process — so status transitions are configuration, not constants.
- **Trigger.** A ticket that goes `ready → blocked → … → done`.
- **Wrong behaviour.** The ticket is simultaneously `done` and `blocked`. Any query by status returns it in both sets; the queue's shape becomes ambiguous.
- **Assertion.** Model status as a **single-valued state** with declared transitions, and assert **mutual exclusivity as an invariant after every transition, from every reachable predecessor state**. Test: enumerate all reachable state pairs, apply every transition, assert exactly one state label is present after each. The historical bug appears only on a specific path, which is precisely why path-exhaustive testing is required rather than example testing.
- **Substrate.** Fixture board (local file backend) + a recorded fake board API.
- **Mutation.** Remove one label-clearing call. The exhaustive test finds it; a single happy-path example does not.

---

**F-51 · Ticket-id allocation without a lock produces duplicate ids**
`→ R1-04, Д2` · CLAIMED (§10.2 `J-T169-01`) · **VERIFIED as still unfixed in source** (F-49) ·
Rank **A**

- **Precondition.** Concurrent `add` — guaranteed by Д2 (work added mid-run) plus R1-05 (configurable parallelism) plus the user adding tickets by hand while the run is going.
- **Trigger.** Two adds racing.
- **Wrong behaviour.** Two files under one id, **and both callers are told they succeeded.** Historical rates: 5/5 rounds for two-way; 20 files under 3 ids for twenty-way. After the (unlanded) fix, two-, twenty- and fifty-way adds never shared an id.
- **Assertion.** See F-49(c). Run at 2, 20 and 50 concurrent adds, assert `count(distinct ids) == count(adds)` and that no two records share an id. Also assert the **failure mode is a refusal, not a silent collision** — an allocator that cannot guarantee uniqueness must error.
- **Substrate.** Concurrent process spawning. Free.
- **Mutation.** Remove the lock — i.e. use the current source. Red.
- **Related.** §11.11 records a separate ticket-filing id race (`#273`, `#276`), so this shape recurred in a second component.

---

**F-52 · An audit log records events that never happened**
`→ R1-06 part 2, Д11` · CLAIMED (§12.7: a security review of a single API read found **26 refusal
events in the audit log that never occurred**) · Rank **B**

- **Precondition.** Logging from intent rather than outcome — the F-07/F-29/F-36 root.
- **Trigger.** A code path that emits a record on a branch that does not execute the action, or retries that each log.
- **Wrong behaviour.** The record used for both recovery (R1-06: "в реєстрі має записуватись кожен стан") and for security review is fiction. Twenty-six phantom events from **one** real read.
- **Assertion.** Log records must be emitted from the site that observed the effect, carrying the effect's evidence. Test: perform one action, assert exactly one record; perform an action that fails, assert the record says failed; drive a retry of three attempts, assert the record count matches the declared model (one record with three attempts, or three records — either is fine, but the test pins it). Cross-check: an end-of-run reconciliation asserting record counts match observed effects.
- **Substrate.** Recorder fixtures.
- **Mutation.** Emit the record before the action. Red.

---

**F-71 · A test run whose tree was modified by a concurrent actor reports a confident wrong result**
`→ R1-05, R1-16` · **VERIFIED here, by accident** (see §1.5) · Rank **B**

- **Precondition.** Parallel agents sharing a working area — which R1-05 makes the normal case and Д4's worktree default is designed to mitigate but does not fully prevent (F-12 shows worktrees create their own aliasing).
- **Trigger.** Another actor edits a file under test while a run is in progress.
- **Wrong behaviour.** In my own experiment, mutation M3 in `harness-limits.sh` produced a deterministic failure in `H-39`, an unrelated `hlib.sh` test, reproducibly three times. The result looked like a real finding about the mutation. It was contamination. **A run that is reproducible is not therefore trustworthy.**
- **Assertion.** Every run must record a **content hash of the tree it tested** and refuse to report a result if the tree changed during the run. Test: modify a file mid-run and assert the run reports `tree-changed`, not a verdict. Additionally, assert each run executes against an immutable snapshot (a copy or a worktree at a pinned commit) rather than a live shared directory.
- **Substrate.** Filesystem + hashing.
- **Mutation.** Drop the hash check. Red.

---

## 6. Rank C — conditional recurrence

These recur only under a configuration the user may not choose. They are specified more briefly;
each is still a real observed failure with a real assertion.

**F-53 · A branch name computed from a slug differs from the lane's branch.** `→ Д4, R1-03` · CLAIMED
(§4.3, §11.8: GSD computed `gsd/phase-23-tooling-the-harness-and-the-pre-commit-checkers` from the
roadmap slug, one word off the lane branch `…-the-harness-SCRIPTS-and-the-…`; left alone,
`execute-phase` would have cut that name fresh from `origin/master` and **lost the merged master
tip**). *Assertion:* the orchestrator must pass the branch explicitly and assert the process operated
on the branch it was given; a mismatch between the intended and actual branch is a hard stop before
any destructive git operation. Test in a scratch repo with a deliberately divergent slug. *Mutation:*
remove the post-condition branch check. Rank **C** (GSD-specific, but any process that derives names
from text has this shape).

**F-54 · A lane spawns into the wrong worktree.** `→ Д4` · CLAIMED (§11.8: the spawn validator caught
`w-phase-5.sh` whose session id, log and prompt all said phase 5 while the script `cd`'d into the
**phase-4** worktree; rejected twice before a correct spawn). *Assertion:* internal consistency of a
launch spec is a pure function — assert every identifier in a spawn descriptor (session id, cwd,
prompt, branch, log path, ticket id) refers to the same unit, as a **free, deterministic, local
check**, not a model review. *Mutation:* cross-wire one field. Rank **C**, and note this is a case
where the previous generation's sonnet validator **worked** — but the same check costs nothing as a
pure assertion, and M5 above showed the suite could not tell whether the validator was even running.

**F-55 · A reused slug spawns into a stale worktree with a stale prompt.** `→ Д4` · CLAIMED (§11.8,
`2026-09-06T14:15:39Z`). *Assertion:* run-scoped unique identifiers; assert a spawn refuses when its
target directory already exists with content from a different run id. Rank **C**.

**F-56 · An external ref move corrupts a checked-out tree silently.** `→ R1-16, R1-12` · CLAIMED
(§4.4: `git update-ref refs/heads/master origin/master` moved HEAD and touched neither index nor
working tree; with `master` checked out, the tree silently held older content and `git status` showed
the newest committed content as a **staged deletion**, one `git commit` away from reverting it —
observed against `docs/open/RUN-NOTES.md`: HEAD 69 lines, index and worktree 65). *Assertion:* never
move a ref that is checked out anywhere; assert the operation refuses when the target branch is the
HEAD of any worktree, and assert a post-operation tree-vs-HEAD consistency check. Test in a scratch
repo. Rank **C** (needs the orchestrator to do ref surgery at all) — but the consistency check is
cheap and catches an irreversible loss.

**F-57 · A ticket body containing the harness's own template tokens breaks or subverts a spawn.**
`→ R1-04, Д2` · CLAIMED (§10.2 `J-ORCH-37`: `harness-spawn.sh` refused to spawn because a ticket quoted
`{{HBIN}}` and `{{RUN_DIR}}` inside its fenced body; a workaround was applied and **logged as
unsafe**). *Assertion:* ticket content must never be substituted into a template — bind it as data,
not text. Test with bodies containing every template token, the fence sentinels, and a spoofed
close-sentinel; assert the rendered prompt is unchanged in structure. **The existing H-44 is the one
old test that catches its mutation** and is the model to copy. Rank **C→B**, since R1-04 makes ticket
bodies arbitrary user/board text.

**F-58 · A workaround edit is misattributed as a lane's alteration.** `→ R1-13` · CLAIMED (§10.2
`J-ORCH-39`, the direct consequence of F-57; also §11.11's spawn-guard/prompt-template collision
producing a false validator finding). *Assertion:* every prompt or file modification carries an actor
label, and any review step reports the labelled actor rather than inferring one. Rank **C**.

**F-59 · A detector globs the wrong directory and reports a clean zero.** `→ R1-09` · CLAIMED (§11.3:
a marker detector globbed `state/` instead of `markers/` and **silently reported zero markers for
several cycles**). *Assertion:* the empty-is-not-clean rule (F-35, F-47) plus a startup self-check
that every configured path exists and is non-empty when it must be. *Mutation:* repoint a glob. Rank
**B**, since it is the same rule as two Rank A/B entries and costs nothing extra.

**F-60 · A status-line regex misses a decimal version and degrades silently.** `→ R1-08, R1-11` ·
CLAIMED (§12.2: `Opus 4.8` did not match, so the watch fell back to a broken capture window for three
validators **without saying so**). *Assertion:* golden-fixture parsing over recorded status lines
covering integer and decimal versions, wrapped lines, non-ASCII characters, and unknown model names;
assert unknown input yields an explicit `unparsed` that escalates, never a silent fallback. Fixtures
are free and already exist. Rank **B** — R1-11 requires per-platform session handling, multiplying
the number of status-line formats that must be parsed.

**F-61 · A probe that can never succeed and never complains.** `→ R1-09` · CLAIMED (§11.3: BSD
`find -newermt "-10 minutes"` errors out, and with stderr routed to `/dev/null` it returns empty every
time — **which would have declared every healthy session idle for ever**; caught by cross-checking
against files known to be minutes old; switched to `-mmin`). *Assertion:* every probe must have a
**positive control** in the test suite — a fixture it is known to match — so a probe that can never
match fails at build time. Assert also that no shipped probe discards stderr. *Mutation:* break a
probe's syntax; its positive control goes red. Rank **B**: cheap, and it generalises to every
detector in the system.

**F-62 · A parser silently substitutes a tighter default when its input scrolls off.** `→ R1-09` ·
CLAIMED (§11.3: when `timeout 1800s` scrolled off a forty-line capture window, the parser fell back to
a 900 s default, **tightening the stall ceiling from 33 to 18 minutes**). *Assertion:* a parser must
distinguish "absent" from "not in view"; assert that a truncated input yields `unknown` and that
`unknown` never silently becomes a default. Test with a capture window deliberately shorter than the
content. Rank **B**.

**F-63 · A non-ASCII space is misread as an unsent nudge.** `→ R1-09` · CLAIMED (§11.3, one of **four
detector false positives fixed in one day**: a non-ASCII space misread as an unsent nudge; a
validator's own quoted warning text triggering a full alarm; a dialog's shape alone treated as proof
of a captive session; and a whole-screen scan matching a dialog quoted inside a session's own report).
*Assertion:* normalise Unicode before matching, and **never match a detector's subject matter over a
region that can contain quoted text** — restrict screen scans to the input line or status region, and
test each detector against a screen containing its own trigger phrase quoted in prose. This is the
F-40 root cause, and the four-in-one-day rate is why it belongs in the suite as a category. Rank
**B**.

**F-64 · Secrets reach transcripts and tool output, which nothing scans.** `→ R1-11, Д11` · CLAIMED
(§11.10: **two local role passwords printed in clear text into a session transcript** by Playwright's
`--trace on` while diagnosing a timeout, found by manual review afterwards, with **no automated secret
scan covering tool output or transcripts**; traces deleted, nothing committed or pushed, the owner
asked to rotate; separately a Sentry breadcrumb recorded the address of every outgoing request and one
such address was a Slack webhook secret, `#83`). *Assertion:* a secret scan must cover the artefacts
the orchestrator itself produces — transcripts, logs, screen captures, state files — not only the git
index. Test: plant a known credential pattern in each artefact type and assert it is detected and the
artefact quarantined. Rank **B** for a code-adjacent run, **C** for the non-code uses N2 allows.
*Repo-convention note:* this repository's own CLAUDE.md requires checking for credential exposure
before staging, and screen captures of agent sessions are a new artefact class that rule does not yet
cover.

**F-65 to F-69 · The commit-gate family.** `→ R1-03, R1-13` · CLAIMED (§11.9, and note the header
there: **"each was found by mutation rather than by the gate failing"** — the previous generation
already learned this corpus's central lesson in one subsystem and did not generalise it).
- **F-65.** A lane worktree can commit with **no pre-commit gate at all** — `npm ci --ignore-scripts` skips husky entirely (`#122`). *Assertion:* assert the gate ran, from the commit's own evidence, rather than assuming installation implies execution.
- **F-66.** The magic-value and credential checker self-tests **assert the checker as it sits on disk, not the version being committed**; a stage-then-restore commits a dead rule at exit 0, and `git rm --cached` on either checker commits its own deletion at exit 0 with **no self-test run at all** (`#290`, `#298`); three further mutation-discovered ways to disable a checker while `--self-test` stays green (`#72`, `#69`, `#75`). *Assertion:* self-tests must run against the **staged** content; assert deleting the checker fails the commit.
- **F-67.** The credential checker silently ignores a bare path argument (a sweep without `--scan` reads clean over files it never opened), refuses files larger than 32 MB as "unreadable" and leaves them silently unscanned, and scans the wrong file when a staged file is literally named `0:<path>` (`#293`, `#258`, `#261`). *Assertion:* files-not-scanned must be an output, and a non-zero skip count must fail the gate — the empty-is-not-clean rule again.
- **F-68.** Gates 4 and 5 swallow a failed `docker inspect` or `docker ps` and then **release the network or mark the run finished on the swallowed error** (`#167`, `#168`). *Assertion:* a failed probe must not reach a success branch; test by making the probe fail and asserting the gate errors.
- **F-69.** Gate 5's six-hour rule reads a UTC timestamp as local time and **never fires on this machine** (`#160`). *Assertion:* `CLOCK-DOUBLE` sweep across timezones and DST boundaries; assert the rule fires at the intended wall-clock interval in every zone.

Rank **C** collectively — these belong to the user's configured process, which R1-13 puts outside the
orchestrator's remit. They are included because they are the **best-documented evidence in the record
that grep-shaped gates fail silently**, and because F-34's "does the step resolve and run" assertion
is the orchestrator-side check that would have surfaced F-65.

**F-70 · A terminal backend cannot type at all, and the gap is discovered at 3 a.m.** `→ R1-11, R1-08`
· **VERIFIED in source**: `harness-term.sh:228` refuses `send`/`key` on the Terminal.app backend, and
`:26` warns that "graceful stop, stall nudges, and rate-limit auto-resume are unavailable" there ·
Rank **B**. *Precondition:* R1-11 requires per-platform interactive/headless/hybrid configuration, so
the number of backends multiplies. *Wrong behaviour:* a backend silently lacking a capability that
half the orchestrator's mechanisms depend on — and, with M6 above, the engine could be made to believe
it typed. *Assertion:* every adapter must **declare its capability set**, and configuration must fail
at start if the chosen process needs a capability the chosen backend lacks. Test: a capability matrix
per adapter, asserted by actually exercising each verb against a double, and a configuration test that
rejects an incompatible pairing before the run starts rather than degrading during it. *Mutation:*
that is M6 — have an adapter claim a capability it does not have; the matrix test must go red where
the old suite stayed green.

---

## 7. The seven "hard to test" cases, answered directly

The brief named seven failures as hard to test. Each is above; this table says what makes each one
testable and what it costs, because "hard to test" turned out in every case to mean "untestable
through the interface the old suite used, cheap through a different one".

| Named difficulty | Entry | What makes it testable | Cost |
|---|---|---|---|
| An instruction that never arrives | F-01…F-09 | A `SESSION-DOUBLE` with a **submitted-inbox and a transcript**. The assertion moves from "did we type" to "did a user turn appear". Nine bugs collapse into one `deliver()` contract. | Build the double once; tests are sub-second, zero API cost |
| A shell that can never exit reading as work | F-25 | Classify on **progress, not existence**: a child alive past a ceiling with an unchanged output stream is `suspect`. Scriptable child processes in a `WORLD-DOUBLE`. | Process table fixtures; free |
| A merge that reports success and does nothing | F-29 | Assert the **ref moved**, not the exit code. A scratch repo with a dirty tracked file reproduces the original exactly. | Scratch git repo; milliseconds |
| A truncated test run reading as a pass | F-32 | The **conservation identity** `total == passed + failed + skipped + not_reached`, plus signal-exit ⇒ `incomplete`. The historical numbers (382/346/0/35) are the fixture. | Output fixtures; free |
| Two orchestrators alive at once | F-13 | An OS-level exclusive lock, then **50 concurrent start rounds** asserting exactly one winner, plus stale-lock, `SIGSTOP`-not-dead and pid-reuse cases. | Process control; seconds |
| Quota read as UNKNOWN for a whole run | F-16…F-20 | A `PROVIDER-DOUBLE` returning malformed/401/hang, plus an assertion that **N consecutive unknowns escalate**. `env -i` covers the detached-process variant. | Local HTTP stub; zero API cost |
| A documented fix missing from the code | F-49, F-51 | An installed-vs-source **drift test**, a doc-to-commit provenance test, and the concurrency test the fix should have shipped with. The bug is **live in this repository right now**, so the test fails before it passes. | Filesystem + concurrent spawns; free |

**None of the seven needs a paid API call.** The reason they were hard before is that the old suite's
only interface to the system was the text of its source files. Six of the seven become easy the moment
the system is given seams — a delivery layer, a clock, a provider client, a process/world facade —
that a test can substitute. That is a design requirement on the rebuild, not a testing preference: **a
system that cannot be tested without a live session and a live account will not be tested.**

---

## 8. Ranked summary

Rank is probability of recurrence in the rebuild, highest first. "Mut." names the mutation that must
turn the test red; every entry has one, and no test enters the suite until its mutation has been seen
to fail.

| # | Failure | Rank | Threatens | Substrate |
|---|---|---|---|---|
| F-09 | No delivery receipt exists — sent and arrived are one variable | A | R1-08, R1-09, Д12 | SESSION-DOUBLE |
| F-10 | Control file rebuilt each tick, destroying external writes | A | Д12, Д7, R1-07, Д6 | filesystem |
| F-13 | Two orchestrators alive at once (no guard exists today) | A | R1-10, Д10 | process control |
| F-16 | Quota UNKNOWN for a whole run; policy default is `proceed` | A | R1-06 | PROVIDER-DOUBLE |
| F-29 | A merge reports success and does nothing | A | R1-12, R1-13 | scratch git |
| F-01 | A bare Enter does not submit text on the line | A | R1-08, Д12 | SESSION-DOUBLE |
| F-02 | `send` destroys pending text, including a human's | A | R1-08, Д12 | SESSION-DOUBLE |
| F-21/22/23 | The pause path's three-step regression (one still open) | A | R1-06, Д12 | CLOCK-DOUBLE + fault injection |
| F-24 | Heartbeat staleness read as a stall — the trigger for F-01 | A | R1-09 | SESSION-DOUBLE + table |
| F-30 | A configured step is silently skipped; artefact self-attributes | A | R1-13, R1-03 | fixtures |
| F-32 | A truncated test run reads as a pass | A | R1-13 | output fixtures |
| F-49 | A documented fix lives only in the installed copy — **live now** | A | repo conventions | filesystem |
| F-51 | Ticket-id allocation unlocked → duplicate ids — **live now** | A | R1-04, Д2 | concurrency |
| F-50 | `blocked` never removed on `done` — two state labels | A | R1-04 | fixture board |
| F-25 | A shell that can never exit reads as work | A | R1-09 | WORLD-DOUBLE |
| F-27 | Ready work + free capacity + no progress, and no rule fires | A | R1-09, Д6 | fixtures + clock |
| F-28 | The only escalation is a nudge; 12.4 h observed before one fired | A | R1-09, R1-17 | clock + recorder |
| F-31 | Work reaches the trunk before its validation ran | A | R1-12, R1-13 | process graph |
| F-34 | A step exists only as prose; nothing runs it | A | R1-03, R1-13 | config fixtures |
| F-35 | An empty scope reported as a clean pass | A | R1-03, Д4 | worktree repo |
| F-36 | `SYNTAX OK` while the anchor never matched | A | R1-03, R1-10 | filesystem |
| F-03 | `send` silently truncates above an unknown ceiling | A | R1-08 | SESSION-DOUBLE |
| F-04 | Recovery destroys the instruction it recovers | A | R1-08 | SESSION-DOUBLE |
| F-05 | Background re-invocation discards the idle line | A | R1-09 | SESSION-DOUBLE |
| F-06 | Delivery to a drifted pane; 149 min undetected | A | R1-09, R1-10 | SESSION-DOUBLE |
| F-07 | The log says "nudged" when nothing was delivered | A | Д11, R1-10 | SESSION-DOUBLE |
| F-08 | Compact lands only with zero shells running | A | R1-08 | SESSION-DOUBLE |
| F-11 | Staging file observed as zero bytes mid-write | A | Д12 | filesystem |
| F-12 | A channel forks into a worktree copy; a question goes unseen | A | Д6, Д4 | worktree repo |
| F-14 | A finished session is closed by nobody (28 h observed) | A | Д3, R1-16 | SESSION-DOUBLE + clock |
| F-15 | Restart with executors alive: adopt-and-duplicate or tear-down | A | Д10, R1-10 | process table |
| F-17 | Quota measured against the wrong account | A | R1-06, R1-07 | PROVIDER-DOUBLE |
| F-18 | `authentication_error` blinds every cap read; no re-auth | A | R1-06, R1-07 | PROVIDER-DOUBLE |
| F-19 | Usage figure moves 26%→6% from an account switch alone | A | R1-06, R1-07 | PROVIDER-DOUBLE |
| F-20 | Detached processes inherit no environment; silent degradation | A | R1-06, R1-10 | `env -i` |
| F-26 | A retry loop is indistinguishable from work (33 m, 184k tokens) | A | R1-09, Д5 | fixtures |
| F-33 | A collection crash reports "No tests found" | A | R1-13 | fixtures |
| F-37 | Nothing measures context at all | B | R1-08 | screen fixtures |
| F-38 | 3,466 of 3,626 calls were `echo idle`; 77% of context growth | B | R1-08, Д11 | transcript fixtures |
| F-39 | Compact has no post-condition proof | B | R1-08 | SESSION-DOUBLE |
| F-40 | An 85-min loop matching a banner in the orchestrator's own prose | B | R1-09, R1-17 | SESSION-DOUBLE + clock |
| F-41 | The notifier exited and was never restarted | B | R1-17, R1-10 | process control |
| F-42 | One condition re-flagged 1085 times over five days | B | Д11, R1-17 | clock fixtures |
| F-44 | `docker compose down -v` on the default project; actor unknown | B | R1-16, Д3 | WORLD-DOUBLE |
| F-45 | `pkill -f` matched the lane whose prompt contains the pattern | B | R1-16 | process table |
| F-47 | The watcher's collector OOM-killed 26× and kept reporting | B | R1-09 | fault injection |
| F-48 | ~150 orphaned volume pairs from a dead prior run | B | Д3, R1-16 | WORLD-DOUBLE |
| F-52 | 26 audit-log refusal events that never occurred | B | R1-06, Д11 | recorder |
| F-57 | Ticket body containing template tokens breaks/subverts a spawn | B | R1-04, Д2 | fixtures |
| F-59 | A detector globs the wrong directory and reports a clean zero | B | R1-09 | fixtures |
| F-60 | A status-line regex misses `Opus 4.8`; silent degradation | B | R1-08, R1-11 | screen fixtures |
| F-61 | A probe that can never succeed and never complains | B | R1-09 | positive controls |
| F-62 | A parser substitutes a tighter default when input scrolls off | B | R1-09 | fixtures |
| F-63 | Unicode and quoted-text false positives (4 in one day) | B | R1-09 | screen fixtures |
| F-64 | Secrets in transcripts and tool output; nothing scans them | B | R1-11, Д11 | artefact fixtures |
| F-70 | A backend silently lacks the capability the run depends on | B | R1-11, R1-08 | capability matrix |
| F-71 | A run reports a verdict on a tree that changed under it | B | R1-05, R1-16 | hashing |
| F-46 | Concurrent builds OOM-kill the owner's own container | C→B | R1-16, R1-05 | WORLD-DOUBLE |
| F-53 | A computed branch name one word off the lane's branch | C | Д4, R1-03 | scratch git |
| F-54 | A launcher whose fields disagree — wrong worktree | C | Д4 | pure function |
| F-55 | A reused slug into a stale worktree with a stale prompt | C | Д4 | filesystem |
| F-56 | An external ref move corrupts a checked-out tree silently | C | R1-16, R1-12 | scratch git |
| F-58 | A workaround edit misattributed as a lane's alteration | C | R1-13 | fixtures |
| F-65…F-69 | The commit-gate family — gates that cannot fail loudly | C | R1-03, R1-13 | process-side |

Totals across the 71 entries: **39 Rank A, 20 Rank B, 12 Rank C**. Two of the Rank C entries — F-46
(resource blast radius) and F-57 (ticket bodies as template input) — are marked C→B, because the
requirements move their preconditions toward the normal case. The table above has 64 rows: F-21/22/23
share one row and three entries, F-65…F-69 share one row and five, and F-43 is listed with the loop
family rather than repeated here.

---

## 9. Positive controls — behaviour that worked and must not regress

A corpus of only failures produces a system that is defensive and useless. FIELD-NOTES §9 records what
worked; these belong in the same suite as regression guards, because several of them are exactly what
the new failure tests could break.

- **P-01 · Sessions escalated instead of guessing.** Eleven questions were routed to the question channel rather than answered by assumption (`Q-P9-01`, `Q-T122-01`, `Q-OWN-01`…`-04`, `Q-ORCH-04`…`-07`, `Q-RESTORE-01`, `Q-PARITY-01`, `Q-T250-01`), each with a recorded fallback and each later marked answered. *Assert:* an escalation path exists, is reachable from a worker, and records a fallback. Д6 makes this channel a first-class requirement.
- **P-02 · A question was driven empirically before being asked.** `Q-PARITY-01`: the session removed a permission check, rebuilt, ran the comparison in 27.4 seconds, found 64 count-pairs identical across four roles and sixteen collections, and asked only what measurement could not settle. *Assert (prompt fixture):* the instruction to measure first survives prompt edits.
- **P-03 · Close-without-force worked as designed.** `w-phase-15`, `-18`, `-19` and `v-phase-22` each hit `job still running after timeout — LEAVING SESSION OPEN (never force-close)` and were later found already finished on their own. *Assert:* a timeout never force-kills; F-14's reaping must not break this — the reaper closes **finished** sessions, never busy ones.
- **P-04 · Two lanes at once, with no port or state collision.** Phases 12/13 (ports 3400/5444 vs 3500/5445, spawned 11 s apart) and 21/22 (4500/5455 vs 4600/5456, 13 s apart). *Assert:* port-block allocation is collision-free under concurrent spawn — a direct, cheap concurrency test, and the same shape as F-51's id allocation.
- **P-05 · After-the-fact validation with a binding verdict.** Phase 21 was merged before its validator ran; the validator was then run against the merge commit with its verdict binding on whether the merge stood. *Assert:* the recovery path in F-31 exists and its failing branch reverts.
- **P-06 · Self-correction was logged.** Two sessions corrected themselves in the run log — a screen-question test firing on a healthy idle orchestrator, and a council-advisor hang warning widened too far and reversed. *Assert:* a correction/retraction record type exists and is not destroyed by F-10's control-file rewrite.
- **P-07 · Real defects were caught before shipping.** The plan checker rejected phase 20's first draft over three revision rounds and rejected phase 23 with a blocker and four warnings (one declined with reasoning); code review on phase 22 found eight warnings plus `IN-03`, all fixed before merge; an incidental `og:image` bug was written to `17-FOUND.md` rather than folded into scope. *Assert:* these are the configured process's wins, which R1-13 keeps out of the orchestrator's remit — the orchestrator's only obligation is F-30/F-34, that the steps **ran**.
- **P-08 · A process gap was disclosed, not buried.** Phases 14–18's builder-only verification was reported to the owner (`OWNER-ACTIONS.md:22-25`). *Assert:* the run report surfaces its own gaps; F-30(c) is the automated version of what a human did here.

---

## 10. Throughput baselines, for regression

From §6 and §9.5. Useful as coarse performance guards; a rebuild that is dramatically slower or faster
than these is doing something different and should say so.

- Worker session per phase: 58 min – 3 h 20 m (phases 10–14 ≈ 1 h; phases 19–22 rose to 4–5.5 h).
- Validator session per phase: 15–50 min.
- Gap between a validator closing and the next worker spawning: 1–26 min, mostly 2–12.
- Two-lane overlap (phases 12/13): ~77 min. Nineteen phases planned, **thirteen merged in the first 34 hours**.
- 33 staleness nudges between `2026-09-11T22:49Z` and `2026-09-13T06:29Z`, across phases 10–22 — **a nudge every 62 minutes**, and §1.5 shows at least six were against healthy sessions. A rebuild should assert a *lower* intervention rate and treat the rate itself as a monitored metric.
- Quota was **not** the binding constraint: across 34 hours the watched account reached 26% of its weekly allowance, and the dependency graph bounded throughput — of nineteen phases only two pairs could ever run concurrently.

That last point matters for R1-05: the observed limit on throughput was **task dependencies**, not
limits and not the machine. A rebuild that invests heavily in quota optimisation before dependency
scheduling is optimising the wrong constraint.

---

## 11. What this corpus does not cover, and where it departs from ANALYSIS-01

**Not covered.**
- The two scratchpad evidence files named in the brief are missing (§0), so anything they contained that is not also in FIELD-NOTES.md is absent here. In particular the "failure-mode section of the orchestrator landscape" — comparative failure data from other orchestrators — is not represented at all. **If that document exists elsewhere, this corpus should be re-reviewed against it.**
- Platforms other than Claude Code. Every record comes from one vendor's CLI. R1-07 names Codex, GLM, Gemini, Kimi and ChatGPT, and instruction **I1** requires per-platform feasibility checks. The `deliver()` contract (F-09), the capability matrix (F-70) and the quota typing (F-18) are written to be run per adapter, but **no adapter other than Claude Code has any evidence behind it**. Treat every Rank A delivery entry as untested-by-history on other platforms.
- Headless mode. R1-11 permits headless, hybrid, and per-platform choices. **Every delivery failure in Family 1 is a property of driving a terminal.** Headless may retire Family 1 entirely and introduce a different family nobody has data for. This is the single largest unknown in the corpus and worth an explicit spike.
- The board backends. Only GitHub labels and local files were exercised. ClickUp, which R1-04 names, has no record.
- Non-code runs. N2 is explicit that the orchestrator may be used where there are no tests, no repository and no build. Roughly a third of this corpus (F-29…F-36, F-53…F-56, F-65…F-69) assumes git or a test runner and simply does not apply there. The corpus has **no evidence at all** about a non-code run, and the rebuild's first non-code use will be unguarded.

**Where this corpus departs from ANALYSIS-01, deliberately and visibly.**
- **Family 6.** R1-13 says the orchestrator imposes no verification of its own, and the owner heard this evidence and did not change his answer. Family 6 is written as bookkeeping about the orchestrator's own actions (did the step run, did the ref move), never as a judgement about the user's work. The distinction is real but it was not put to him in these terms. **It should be question one of round 2.** If he rejects it, F-30, F-31, F-32 and F-33 come out, and the rebuild accepts that a silently skipped verification stage can ship five phases again.
- **F-46/R1-05.** Machine-resource awareness is explicitly deferred. The corpus records the deferral as an accepted risk with a detection-only obligation rather than arguing with it.
- **F-13.** The corpus recommends a hard OS-level invariant rather than a detector, which is stronger than "це треба відслідковувати і не дозволяти" strictly requires. Given that FIELD-NOTES shows every detector in the system being wrong at least once, a detector for this invariant would be the wrong instrument.

**A note on the one question the record answers that the interview did not ask.** R1-09 delegates
silence-handling entirely to the orchestrator's judgement, with no fixed timeout ladder. The record
shows that judgement was not the failing part — the **signals** were. Six false stalls, a shell that
could never exit, a retry loop indistinguishable from work, a probe that could never match, a parser
that silently halved a ceiling. A rebuild that improves the orchestrator's reasoning while inheriting
these signals will make confident decisions on false inputs. Family 5 is written on that basis: the
tests assert what the orchestrator is **told**, and deliberately assert nothing about what it decides.
