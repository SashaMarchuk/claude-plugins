# Ground research — how long-running, non-deterministic, process-spawning systems are actually tested

**Spike:** harness-rebuild · **Date:** 2026-09-21 · **Scope:** testing strategy for the orchestrator
described in `round-1/ANALYSIS-01.md`.

**Evidence legend.** Every claim below carries one of three marks.

- **[V]** VERIFIED — I ran it on this machine in this session, or read it in the repository's own
  source. Commands are reproducible; the probe scripts are in §12.
- **[C]** CLAIMED — asserted by a document (FIELD-NOTES, a vendor page, a paper) that I read but did
  not independently reproduce.
- **[I]** INFERRED — my reasoning from [V] and [C] facts. Arguable. Marked so you can argue.

**A note on what I could not check.** The computed task pointed at a validated evidence summary at
`/private/tmp/claude-501/.../scratchpad/context/harness-evidence.md`. **That file does not exist**
[V] — the `context/` directory is empty. Everything attributed to the 34-hour run below therefore
comes from `plugins/harness/docs/FIELD-NOTES.md`, which is itself explicitly a
*conclusion-free record* and marks its own references. I have treated its records as **[C]** except
where I reproduced the mechanism here, in which case they are upgraded to **[V]** and said so.

---

## 1. The bar to beat, measured rather than asserted

The claim in the brief is that the previous suite was "51 static grep assertions that never caught 13
red-team bugs". I did not take this on faith. I copied the plugin to a scratch directory and ran
**mutation testing against its own suite** — break a contract on purpose, see whether the test fails.
Never in place; the working tree was not touched.

**Baseline [V].** `bash plugins/harness/tests/run.sh` → `PASS=51 FAIL=0`. The file's own header reads
`# harness regression tests — static assertions, no source mutation, no network, no terminals.`
It is 382 lines and contains **83 `grep` invocations** across 51 test ids.

**Five mutations, each disabling a real safety behaviour [V]:**

| # | Mutation — what real behaviour it destroys | Suite result |
|---|---|---|
| M1 | Rate gate never fires: `if [ "$v" = "PAUSE" ]` → `"PAUSE_NEVER_MATCHES"`. The orchestrator now spawns sessions into an exhausted quota. | **PASS=51 FAIL=0** |
| M2 | `wait_clear()` returns immediately. A paused run resumes instantly into the wall it was waiting for. | **PASS=51 FAIL=0** |
| M3 | `require_ready_body()` returns 0 always. Any ticket becomes "ready" with no acceptance criteria. | PASS=48 **FAIL=3** |
| M4 | `tell s to close` commented out in `harness-term.sh`. Sessions are never closed. | **PASS=51 FAIL=0** |
| M5 | Spawn validator's reject code `65` → `6500`. The pre-spawn safety review can no longer reject anything. | **PASS=51 FAIL=0** |

**Four of five behaviour-killing mutations were invisible to the suite.** M1 is the sharpest: the test
that "covers" it, `H-11 pause-not-stop contract`, greps for the literal string `return 75` — which is
still in the file, now unreachable. `H-11` printed `PASS` while the gate was dead.

**The one mutation that was caught is the whole lesson [V].** M3 was caught by exactly three tests —
`H-44`, `H-45`, `H-46` — and those three are the only tests in the file that **execute the script
against a real fixture**: they `mktemp -d`, write a ticket file, run `harness-tickets.sh`, and assert
on the resulting file contents. The other 48 read source text. The suite's entire defect-detection
power lives in its three behavioural tests.

> **The bar, restated precisely.** It is not "more tests". It is: *every test must be able to fail for
> the reason it claims to check.* A test earns its place by failing under a mutation of the behaviour
> it names. That is a mechanical, checkable property — §11 makes it a CI gate.

---

## 2. The five shifts that most change how this system should be tested

Stated up front; each is argued in the section named.

1. **Put a seam at every process, clock, network and terminal boundary — testability is an
   architectural decision, not a test-suite decision.** The previous generation's quota gate calls
   `curl` inline against a hardcoded URL with no override; that alone makes the single most
   safety-critical decision in the system untestable without a network call. I verified a 3-line
   `curl` shim on `PATH` makes it fully drivable with zero spend (§3, §4).
2. **Time must be injectable, or nothing about a long-running system is testable.** The failures worth
   catching happen at hour 12, not second 12. I drove a 44,791-second stall — the real observed peak
   from the previous run — through a stall detector in **zero wall-clock seconds** using a `now()`
   seam (§5).
3. **The orchestrator is a reconciliation loop, and the Kubernetes controller literature is the
   closest-fitting body of practice there is.** Its core discipline — a single `Reconcile(state) →
   actions` pure function, tested by table-driven cases over synthetic world states — converts most of
   this system's logic into cheap, deterministic unit tests (§9).
4. **Non-determinism is not the enemy; hidden non-determinism is.** Every decision the orchestrator
   makes must be a pure function of a *recorded* input snapshot. Then replay is exact, and the LLM is
   the only non-deterministic component left — quarantined behind a fake (§6, §7).
5. **The bugs that actually hurt are in the adapters, not the logic.** Of the ~60 distinct failures in
   FIELD-NOTES, the large majority are terminal I/O, tool-flag, parser and environment defects — not
   orchestration-logic defects. I reproduced two of those mechanisms exactly on this machine, and
   found a third that is live right now (§4.3, §8.4, §10).

---

## 3. Hermetic simulation

The umbrella technique. Replace every real external dependency with a controllable stand-in, so a test
run touches no network, no account, no real terminal and no real money.

### 3.1 Fake binaries on `PATH`

**What it is.** Prepend a directory of executable scripts that impersonate the real CLIs. The system
under test calls `claude`, `codex`, `gh`, `curl`, `docker` exactly as it does in production; the shim
intercepts, records argv, and replies from a script.

**[V] It works here, unmodified.** Probe A:

```bash
cat > fakebin/claude <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_ARGV_LOG:-/dev/null}"
case "${FAKE_SCRIPT:-ok}" in
  ok)           echo "READY"; exec /bin/sh -c 'while :; do sleep 1; done' ;;
  rate_limited) echo "Claude usage limit reached. Your limit will reset at 3pm."; exit 0 ;;
  crash)        echo "boom" >&2; exit 1 ;;
  hang_silent)  exec /bin/sh -c 'while :; do sleep 1; done' ;;
esac
EOF
```

`FAKE_SCRIPT=rate_limited claude --model opus --session-id abc123 "prompt"` replayed the banner, and
`argv.log` captured `--model opus --session-id abc123 prompt text` for assertion.

**What it catches in this orchestrator.**

- *The launcher contract.* FIELD-NOTES records `w-phase-5.sh` whose session id, log and prompt all
  said phase 5 while the script `cd`'d into the **phase-4** worktree [C]. An argv+cwd assertion on a
  shimmed `claude` catches that class in milliseconds. It was caught in the real run only by a paid
  Sonnet pre-spawn review — which M5 above shows the suite cannot even prove is wired [V].
- *Per-platform spawn matrices.* R1-07 and R1-11 require Claude Code, Codex, GLM, Gemini and opencode
  to each be spawnable interactive or headless, with per-platform account switching. That is a
  combinatorial matrix no human will ever exercise by hand. One shim per platform turns it into a
  table-driven test: assert the exact argv, env and cwd each combination produces.
- *R1-06 quota semantics per provider.* "Adapt to whatever the provider's scheme is, including
  none/pay-as-you-go." A shim per provider lets you assert the verdict for each scheme without an
  account on any of them.
- *Д3 "stop what it started, touch nothing else".* Shim `docker` and `kill`; assert the exact set of
  targets. FIELD-NOTES records the owner's default stack destroyed by a `docker compose down -v`
  without `COMPOSE_PROJECT_NAME` [C] — an argv assertion on a shimmed `docker` is precisely the test.

**Cost to build.** Low. ~30–60 lines per shim, one afternoon for the full set. No dependencies beyond
bash. **This is the highest value-per-hour technique available and should be built first.**

**How to wire it here.**

```
tests/
  fakebin/            # claude, codex, gh, curl, docker, security, tmux…
  fixtures/
    usage/            # recorded quota bodies (§6)
    screens/          # recorded pane captures (§8)
  scenarios/          # declarative run scenarios (§7)
  lib/harness.bash    # with_fakebin(), with_clock(), with_project()
```

`with_fakebin` sets `PATH="$TESTS/fakebin:$PATH"` and points `FAKE_*` env at the scenario's script.
One helper; every test uses it.

**The trap, and the fix.** A shim only intercepts if the code resolves the binary through `PATH`.
Production code that hardcodes `/usr/bin/curl`, or sanitises `PATH` before calling out, escapes the
shim silently — the test then exercises the real thing or nothing. **Make "no absolute path to an
external binary outside the resolver" an enforced lint**, and give the orchestrator one
`resolve_bin <name>` function that tests can point elsewhere. (The current `harness-spawn.sh` does
sanitise `PATH` in generated launchers [C, from FIELD-NOTES §0]; that is correct for production and
must be overridable in test.)

### 3.2 A fake agent CLI that replays scripted behaviour

One step beyond a shim: a stand-in that behaves like an *interactive* agent over a pty — prints a
status line, accepts turns, emits tool-call-shaped output, can be told to stall, to emit a rate-limit
banner, to fill its context, to die.

**What it catches.** Everything the shim cannot, because the shim exits immediately:

- *Liveness and silence judgement (R1-09).* The requirement delegates "is this session progressing?"
  to the orchestrator's judgement with no fixed ladder. That is a *policy* that must be regression-
  tested against scripted session behaviours: healthy-but-quiet, genuinely hung, finished-and-idle,
  looping. FIELD-NOTES records the engine nudging **six healthy sessions** it misread as stalled, and
  conversely a 149-minute stall nothing detected [C]. Both are the same missing test.
- *Context-fullness thresholds (R1-08).* The requirement is emphatic — "повинен бути механізм, який
  гарантовано робить цю дію". A fake agent that reports a rising context percentage on its status line
  lets you assert the soft/hard compaction semantics deterministically. FIELD-NOTES records that
  **nothing in the previous plugin measured context at all** [C] — a grep of `bin/*.sh` for
  `compact|ctx=|auto-compact` returns nothing — while the percentage was printed on every session's
  status line the watch loop was already capturing.
- *Д10, restart with executors alive.* Script three fake agents in different states, kill the
  orchestrator, restart it, assert what it does to each.

**Cost.** Medium. ~200–400 lines for a decent one, plus a small scripting format. A day or two. Worth
it: it is the only way to test the watch loop's judgement, which is where this system's novel risk
lives.

**A caution I verified [V].** A fake agent is a *lower-fidelity* stand-in than the real TUI, and the
difference can invert a test's result. In my tmux probe, a bare `Enter` **did** submit text already on
the input line (probe C2: 21 chars typed without Enter, then bare Enter → delivered). FIELD-NOTES
records that against real Claude Code a bare Enter does **not** submit, measured twice [C]. A test
suite built only on the fake agent would have "proved" the nudge works. **Keep a small, separately-run
conformance tier against the real CLI (§10.3) whose only job is to check that the fake still matches
reality on the handful of behaviours the fakes assert.**

### 3.3 Dependency injection at the process boundary

The general form: route every outside-world call through a named seam the test can replace. In bash
that is a function, not a framework.

**[V] The decisive demonstration on this repository.** `harness-limits.sh`'s `snapshot()` calls
`curl` inline against a hardcoded URL, and `grep -nE 'HARNESS_(USAGE|FAKE|SNAPSHOT)|USAGE_JSON|_FIXTURE'`
over the file returns **nothing** — there is no injection seam. Yet because it resolves `curl` through
`PATH`, a 3-line shim makes the whole gate drivable:

```bash
cat > shim/curl <<'EOF'
#!/usr/bin/env bash
cat >/dev/null 2>&1            # drain the -H @- stdin
printf '%s' "$FAKE_USAGE_BODY"
EOF
run() { PATH="$SHIM:$PATH" CLAUDE_CODE_OAUTH_TOKEN=fake FAKE_USAGE_BODY="$1" \
        bash bin/harness-limits.sh verdict; }
```

Seven behaviours of the shipped gate, driven in milliseconds, no network, no spend [V]:

| Fixture | Verdict produced |
|---|---|
| `session 12 / weekly 30` | `VERDICT=OK SESSION=12 WEEKLY=30` |
| `session 97 / weekly 30` | `VERDICT=PAUSE … REASON=session UNTIL=2026-09-21T18:00:00Z` |
| `session 10 / weekly 99.5` | `VERDICT=PAUSE … REASON=weekly` — fractional percent handled |
| `percent: null` | `VERDICT=UNKNOWN` — fails closed, correct |
| `percent: "97"` (string) | `VERDICT=UNKNOWN` — fails closed, correct |
| HTTP 401 auth-error body | `VERDICT=UNKNOWN` — fails closed, correct |
| `five_hour.utilization` shape | `VERDICT=UNKNOWN` — see §4.3 |

**The code is right. The tests prove none of it.** The suite has four references to
`harness-limits.sh`; all four are greps (one greps for the literal string `all(type=="number")`).
None drives the function. And M2 — neutering `wait_clear()` — passed 51/51 [V].

**Cost.** Near zero when designed in; expensive to retrofit. **Rule for the rebuild: no module calls
`curl`, `date`, `claude`, `gh` or a terminal directly. Each goes through a one-line resolver that an
env var can redirect.** This costs nothing at write time and is the difference between a testable and
an untestable system.

---

## 4. The seams this specific orchestrator needs

From `ANALYSIS-01.md`, the orchestrator touches the outside world in exactly seven places. Each needs
a seam, and each seam is a test surface.

| # | Seam | Requirement | Fake | What it unlocks |
|---|---|---|---|---|
| 1 | **Agent process** spawn/observe/close | R1-07, R1-11, Д10 | `fakebin/<platform>` + fake agent | launcher argv/env/cwd, per-platform matrix, liveness policy |
| 2 | **Terminal** — send, key, capture | R1-11, R1-08 | tmux in test mode | delivery round-trip, compaction, screen parsing |
| 3 | **Clock** | R1-06, R1-09, Д7 | `now()` seam | stalls, quota resets, timeouts, 34-hour runs in seconds |
| 4 | **Quota / usage HTTP** | R1-06 | recorded cassettes | hard/soft thresholds, unreadable, schema drift |
| 5 | **Board** — GH Issues / ClickUp / local | R1-04, Д2, Д6, Д8 | in-memory fake board | readiness rules, status writes, mid-run edits |
| 6 | **Control file** (watched, per-tick) | R1-07, Д7, Д12 | tmpdir + injected clock | soft/hard semantics, mid-run config change |
| 7 | **Notification channel** | R1-17 | recording sink | "verify before you run", per-type routing |

Seams 3, 4 and 6 are the ones the previous generation lacked entirely, and they map one-to-one onto
its three worst failure families: undetected stalls, quota blindness, and lost control messages [I].

### 4.1 The control file is a concurrency surface, not a config file

Cross-cutting requirement 2 says a single file carries account assignments (R1-07), stop commands
(Д12) and behaviour overrides (Д7), re-read every tick, with hard/soft semantics. That is a
**shared-mutable-state protocol between the operator and a running loop**, and it needs the tests a
protocol needs:

- *Torn reads.* The operator's editor writes non-atomically; the tick reads mid-write. Test: write a
  half-file, assert the tick keeps the last good config and does not crash or apply half.
- *Read-modify-write loss.* FIELD-NOTES §2.1 [C]: `state/attention` was rebuilt from scratch every
  cycle, silently destroying everything anyone else appended — for a whole night, discovered only when
  a watcher grepped for a block it had written four minutes earlier. Line 5620 of that log reads
  `NO ONE IS BEING TOLD`. Test: a second writer appends; assert it survives a tick.
- *Hard vs soft ordering.* A hard stop written while a soft stop is pending must win. Table-driven.
- *Idempotence.* The same command must not fire twice if the file is unchanged. Assert on mtime *and*
  content hash — mtime alone is a known-flaky trigger.

**Cost.** Low — a tmpdir and the clock seam. **Value: very high.** This file is the operator's only
live control over an unattended run; if it silently drops a stop command, the system has no brakes.

### 4.2 Notification "verify before you run"

Cross-cutting requirement 5 demands the notification channel be proven working before a run starts
(R1-17). The testable contract is two-sided: the preflight must **fail** when the channel is broken.
Fake sink that returns 401/timeout/success; assert the run refuses to start in the first two cases.
This is the cheapest high-value test in the whole system and is exactly the shape of assertion the
previous suite never made [I].

### 4.3 A live schema divergence I found while probing — flag, do not act

While building the quota fixtures I hit a contradiction I could not resolve, and it is worth your
attention because it may be a live bug rather than a testing observation.

- **[V]** The shipped parser requires `.limits` to be an **array**, and reads `.limits[].group`
  (`session`/`weekly`) and `.limits[].percent`.
- **[V]** Your own global `CLAUDE.md` documents the same endpoint as returning
  `five_hour.utilization` and `seven_day.utilization`.
- **[V]** Fed the `CLAUDE.md` shape, the shipped parser returns `VERDICT=UNKNOWN` — it rejects the
  body as unreadable before reaching any threshold.
- **[V]** The live endpoint returns **HTTP 401 `authentication_error`** from this machine right now,
  so I could not determine which shape is current.
- **[C]** FIELD-NOTES §11.7 records `weekly_all=unreadable%` recurring across many separate days, and
  an extended stretch where the endpoint returned `authentication_error` "with nobody
  re-authenticating".

**[I]** Two schemas cannot both be right. Either the API changed shape and the parser has been
silently failing closed ever since, or `CLAUDE.md` is stale. **This is the exact failure mode a
recorded cassette with a schema-conformance check catches on the day it happens**, and that no grep
test can ever catch. I have not changed anything; verifying it needs a working token.

---

## 5. Virtual clocks and time-travel testing

**The problem.** Every interesting behaviour in this system is a function of elapsed time: stall
ceilings, quota resets, heartbeat ages, soft-stop boundaries, the 7-day reclaim sweep, three-strikes
failure counting (Д5). Testing those against the real clock means either sleeping (a suite nobody
runs) or asserting nothing.

**[V] It works, and it is trivial in bash.** Probe G — an injectable `now()`:

```bash
now() { if [ -n "${FAKE_NOW:-}" ]; then echo "$FAKE_NOW"; else date +%s; fi; }
```

Driving a 20-minute stall ceiling through it:

| `FAKE_NOW` offset | Result |
|---|---|
| +19 min | `FRESH age=1140s` |
| +20 min exactly | `FRESH age=1200s` — boundary is `>`, not `>=` |
| +21 min | `STALE age=1260s` |
| +44,791 s (12.4 h — the real observed peak from the previous run) | `STALE age=44791s` |

**12.4 hours of stall, asserted in zero wall-clock seconds.** The `+20 min exactly` row is the point:
off-by-one at a threshold boundary is invisible without a clock you can place exactly on it.

**What it catches here.**

- *R1-06 hard/soft/intermediate limit semantics.* Freeze at 89%, 90%, 90.0001%, 99%; assert the exact
  transition. Fractional percents are real — the shipped gate handles `99.5` correctly [V], and its
  own source comments say an integer `[ -ge ]` comparison "would error and, with `2>/dev/null`,
  silently take the no-pause branch". That near-miss is precisely a boundary test's job.
- *R1-06 "wait for the reset, then continue".* Set the reset to `now+3600`, advance the fake clock,
  assert exactly one resume and no early resume. FIELD-NOTES §11.7 [C] records a three-step regression
  in this path where the wall-clock fallback was pinned to a *fixed past epoch*, so an unreadable read
  resumed a paused run immediately — then the fix created a second bug, then a third (`#82`, still
  open). Three regressions in one time-handling path, none caught by a test.
- *Д5 three-strikes.* Assert the counter's window semantics: three failures in an hour vs three across
  a week are different situations.
- *Д7 mid-run behaviour change.* Assert the change is picked up on the *next* tick, not the current
  one, and not two ticks later.

**Cost.** Near zero if the seam exists from day one. `libfaketime` is **not installed on this machine
and has no Homebrew-clean path on modern macOS** [V] — do not depend on it. The `now()` seam is better
anyway: it is explicit, has no dynamic-linker fragility, and works identically in bash, Python and
Node.

**Design rule.** *No module calls `date`, `$SECONDS`, or `time.time()` directly.* One clock module;
everything asks it. Make it a lint. This is a five-minute decision on day one and unbuyable later.

**Beyond a frozen clock.** The stronger form is a **virtual scheduler**: the loop does not `sleep`, it
asks the clock to advance to the next scheduled event. A 34-hour run then executes in milliseconds and
is perfectly reproducible. This is the core of deterministic simulation testing (§7), and it is worth
designing the tick loop so it *can* be driven that way — `tick(now)` as a pure-ish function, with the
sleeping done by a caller the test replaces.

---

## 6. Record and replay (VCR-style cassettes)

**What it is.** Record real interactions once, store them as fixtures, replay them thereafter. Tests
become fast, offline and deterministic.

**Two distinct surfaces here, with very different economics.**

### 6.1 HTTP — genuinely cheap and high value

The quota endpoint, GitHub Issues, ClickUp, and the notification channel are all HTTP. Record one real
response per interesting state, commit the JSON, replay through the shim.

- **Cost:** low. Recording is a one-off; replay is free.
- **Catches:** schema drift (§4.3 — the single most valuable thing cassettes do here), auth failure
  handling, pagination, rate-limit responses, malformed bodies.
- **Secrets:** cassettes *will* capture bearer tokens. FIELD-NOTES §11.10 records two local passwords
  reaching a transcript via Playwright `--trace on`, with the note that **no automated secret scan
  covers tool output or transcripts** [C]. **Redact at record time, never at commit time**, and run
  the credential scanner over `fixtures/` in CI. Learn this from their incident rather than repeat it.

**The freshness problem, and the honest answer.** A cassette that never re-records is a test of what
the API used to do. Mitigation: a **separate, opt-in, non-blocking `contract` job** that re-records
against the live API on a schedule (weekly is plenty for a single operator) and fails loudly on a
schema diff. It is the only test tier allowed to touch the network, it never gates a commit, and it is
what turns §4.3 from a mystery into an alert.

### 6.2 Agent transcripts — useful, but not as a test oracle

Recording an agent session and replaying it is tempting and mostly a trap [I]. The recorded model
output is not a contract: it changes with the model, the prompt, and the temperature, and asserting on
it produces a suite that fails for reasons nobody caused.

**What transcripts are genuinely good for here:**

- *R1-10 recovery source.* The requirement explicitly names transcripts as a configured recovery input
  ("transcripts for Claude Code and Codex"). Real recorded transcripts are then **fixtures for the
  recovery parser** — assert that a given transcript yields the right reconstructed state. That is a
  deterministic contract with a real oracle.
- *Regression corpus for detectors.* Every false positive in FIELD-NOTES §11.3 and §12.2 was a parser
  reading the wrong thing. Each one becomes a permanent fixture (§8.4).
- *Cost accounting (R1-06 part 3).* Assert the accounting reader against a known transcript.

**Do not** assert "the agent did the right thing" from a replayed transcript. R1-13 is explicit that
verification belongs to the configured process and the orchestrator imposes no checks of its own —
so the orchestrator's tests should not either.

---

## 7. Deterministic seeds and deterministic simulation testing (DST)

**The lineage.** FoundationDB pioneered simulation-first testing for distributed databases; TigerBeetle
built on it with both *logical* determinism (no multithreaded concurrency in the control plane) and
*physical* determinism (replicas converge byte-for-byte); Antithesis — built by the FoundationDB
people — sells a deterministic hypervisor that can rewind time and reproduce any bug exactly [C,
vendor and community sources].

**The core idea, stripped of the database context.** Make every source of non-determinism an explicit
input: the clock, randomness, scheduling order, I/O latency, failure timing. Seed them. Then a run is a
pure function of its seed, you can run thousands of seeds, and any failure reproduces exactly from its
seed alone.

**Does it transfer to a single-operator orchestrator? Partly, and the honest split matters [I].**

- **Transfers well:** the *decision logic*. Given a world snapshot — which sessions exist, their ages,
  quota, board contents, control file — what does the orchestrator decide? Make that a pure function
  and you can run 10,000 seeded world-states in seconds with no agents, no terminals and no money.
- **Transfers badly:** the *adapters*. The real bugs in FIELD-NOTES are in tty line discipline, `find`
  flag dialects, AppleScript, `pkill` over-matching. A simulator faithful enough to reproduce those is
  more complex than the system. Those need real-environment tests (§10).
- **Does not transfer:** the agent. A fake agent is a caricature; the real one is the thing you cannot
  simulate.

**Cost.** Antithesis itself is out of scope — reported pricing around $200k [C], and it is built for
cloud fleets, not a Mac. Open-source deterministic hypervisors (openthesis, dhyve) exist but are
Linux/KVM or bhyve, WIP, and not a fit for a single-operator macOS plugin [C].

**What to actually build: DST-lite.** The 5% that gives most of the value:

1. One seeded PRNG for every random choice, printed in the run header.
2. The clock seam (§5), advanced by the scenario.
3. The tick as `decide(world) → actions` — a pure function returning a *plan*, executed separately.
4. A scenario runner that builds `world`, calls `decide`, asserts on the plan.

Then randomised scenario generation over `world` is nearly free, and every failure prints a seed that
reproduces it. **This is the single biggest architectural payoff available [I], and it costs almost
nothing if decided before the first line of the loop is written.**

> **Concrete shape.** Do not let the tick both decide and act. `decide()` returns
> `[{spawn: …}, {notify: …}, {write_board: …}]`; `apply()` performs them. Every test in §9 then runs
> against `decide()` with no side effects at all, and `apply()` gets its own much smaller adapter
> tests. This one split is what makes everything else in this document cheap.

---

## 8. Golden-file testing

**What it is.** Capture output, store it as an approved reference, diff future runs against it.

**Where it fits here — four good uses and one bad one.**

**Good — the run's decision log.** Replay a fixed scenario; the sequence of decisions is a golden file.
Any behaviour change shows as a reviewable diff. This is the fastest way to notice that a refactor
quietly changed the orchestrator's mind.

**Good — generated launchers.** FIELD-NOTES shows the launcher is a real defect surface: wrong worktree
[C], stale slug reused [C], `{{HBIN}}` template tokens leaking from a ticket body and blocking a spawn
[C]. A golden launcher per (platform × role × mode) makes every change to generation visible.

**Good — rendered prompts.** Ticket bodies reach prompts through an untrusted-input fence. FIELD-NOTES
records a ticket whose body quoted the harness's own template tokens breaking a spawn [C], and the
current `H-44` is a real behavioural test of exactly this. Golden-file the rendered prompt for a set of
hostile bodies — embedded fences, template tokens, 10k characters, ANSI escapes, a body claiming to be
a system message.

**Good — the status surface (Д11).** "The orchestrator must print nothing for me" unless asked. Golden
the silent-mode output (should be empty) and the `status` output. Assert silence; it is a requirement.

**Bad — anything with a timestamp, pid, path or duration in it.** This is where golden files rot.
FIELD-NOTES' own artefacts are full of exactly these. **Normalise before comparing** — replace
timestamps with `<TS>`, pids with `<PID>`, the tmpdir with `<TMP>`, durations with `<DUR>` — and keep
each golden small and focused. A giant golden nobody reads gets rubber-stamped on every diff, which is
worse than no test.

**Cost.** Low, with one discipline cost: an `--update-goldens` flag plus a review rule that a golden
diff is read, never auto-approved.

### 8.4 The detector-regression corpus — the best-value golden variant here

Nearly every false positive in FIELD-NOTES is a detector reading the wrong text. These are **pure
functions of a captured screen**, which makes them the cheapest tests in the system.

**[V] I reproduced the 85-minute loop's mechanism exactly.** FIELD-NOTES §11.6 describes a
rate-limit-banner regex matching the orchestrator's *own wrapped prose*, pressing Escape and sending
`continue` every ~60 s for 85 minutes; nothing internal detected it; it ended only when an external
`SIGTERM` arrived. Probe H:

```bash
det() { grep -qE 'usage limit reached|limit will reset at' <<<"$1" && echo "RATE-LIMIT" || echo clean; }
```

| Input | Result |
|---|---|
| `Claude usage limit reached. Your limit will reset at 3pm.` | `RATE-LIMIT` ✓ |
| `I checked and the session had a usage limit reached banner, so I paused.` | `RATE-LIMIT` ✗ **false positive** |
| `> NOTE: watch for "limit will reset at" in the pane` | `RATE-LIMIT` ✗ **false positive** |

And a candidate fix — anchor to the banner being the last non-empty line, matched at line start —
passes all three [V]. **Three lines of test would have prevented 85 minutes of a self-sustaining loop.**

**Build a corpus.** One captured screen per known situation: healthy busy, healthy idle, rate-limited,
trust dialog, trust dialog *quoted inside a report*, compaction in progress, a model version with a
decimal (FIELD-NOTES §12.2: `Opus 4.8` failed to match a status-line regex [C]), non-ASCII space,
session finished awaiting close. Every false positive ever seen becomes a permanent fixture. This
corpus is the institutional memory of the previous 34 hours, and it is the single most direct way to
turn FIELD-NOTES into tests.

**Cost.** Very low per case, and it compounds. Start it on day one.

---

## 9. Testing supervisors, watchdogs and reconciliation loops

The most relevant literature, because this orchestrator is a supervisor.

### 9.1 Kubernetes controllers — the closest fit

**The practice.** A controller is a reconciliation loop: observe world, compute desired state, act,
repeat. The ecosystem tests it at two tiers [C]:

- **fake client** — an in-memory API surface, no processes, no network. Fast, non-flaky, used for the
  loop's logic.
- **envtest** — real `etcd` + real API server, no kubelet. Used for integration behaviour the fake
  cannot model. The community's stated caution is that the fake client has *no schema, no defaulting,
  no pruning* — it stores whatever you hand it — so it must not be the only tier.

**The transferable discipline, and it is the single most useful idea in this document [I]:**

1. **`Reconcile` is a pure function of observed state.** No hidden reads of the clock, the filesystem
   or the network inside it. This is §7's `decide(world)`.
2. **Table-driven tests over synthetic world states.** Each case: a world, the expected actions. Dozens
   of cases, all sub-second.
3. **Reconciliation is idempotent and level-triggered, not edge-triggered.** Reconciling the same world
   twice must produce actions once. **Test it explicitly** — call `decide()` twice on an unchanged
   world and assert the second returns nothing. FIELD-NOTES §11.6 is what edge-triggered logic on a
   screen that never changes looks like: `continue` sent every 60 s for 85 minutes [C]. A two-line
   idempotence test kills that entire bug class.
4. **Requeue-after semantics** — when the loop says "check again in N", assert N, do not sleep it.

**Mapping to this system.** The orchestrator's world is: registry of sessions it started, their ages
and screens, quota verdict, board contents, control file, worktree states. Its actions are: spawn,
nudge, compact, close, write board, notify, stop. **Almost every requirement in `ANALYSIS-01.md` is a
statement about that function** — R1-05 concurrency caps, R1-06 thresholds, R1-09 silence, Д5 three
strikes, Д6 non-blocking queue, Д7 wait-vs-finish. All of them become table-driven unit tests the
moment `decide()` is pure.

**Cost.** This is an architecture cost, not a test cost — and it is *negative* if paid up front,
because it also makes the system easier to reason about and to change without fear, which is the
owner's stated goal.

### 9.2 Erlang/OTP supervision trees

**The idea.** Supervisors restart children per a declared strategy (`permanent`/`transient`/
`temporary`, `one_for_one`/`one_for_all`/`rest_for_one`) with restart-intensity limits: more than
`MaxR` restarts in `MaxT` seconds and the supervisor itself gives up rather than thrash [C].

**What transfers.**

- **Declared restart policy per child type.** The requirements imply different policies already: the
  orchestrator is `permanent` (R1-10 health check restarts it), a worker session is `transient`
  (finishing is success), a question session is `temporary`. **Making the policy declarative makes it
  testable**; leaving it implicit in control flow makes it untestable. FIELD-NOTES §1.6 records a
  finished question-session left registered and idle for **one day and four hours** because nobody
  owned closing it [C] — that is an undeclared lifecycle.
- **Restart intensity is Д5, already.** "Three identical failures → act per configuration." OTP's
  `MaxR`/`MaxT` is the same primitive with 30 years of production behind it, including the crucial
  part: *what the supervisor does when it gives up*. Test it with the clock seam — three failures in
  one minute vs three across a week must differ.
- **Let it crash, supervise the restart.** The orchestrator should not defensively wrap everything; it
  should die cleanly and be restarted by something simpler than itself. Which is R1-10's health check —
  and OTP's hard-won lesson is that **the supervisor must be simpler than the supervised**. A health
  check that is itself an LLM agent is a supervisor more complex than its child [I]; prefer a
  dead-simple deterministic checker with the agent as an escalation path, which is also what R1-10 asks
  for ("the check must be reliable/deterministic").

**Testing them.** Property: *after any sequence of child deaths, the tree converges to the declared
state within the restart budget, or reports giving up.* This is §10's property test.

### 9.3 systemd — the watchdog protocol worth stealing

`Type=notify` + `WatchdogSec`: the service must send `WATCHDOG=1` at least every `WatchdogSec`, at a
recommended interval of half that; miss it and systemd `SIGABRT`s and restarts per `Restart=` [C].

**The transferable insight, and it is the direct fix for the worst detector bug in FIELD-NOTES [I].**
systemd's liveness signal is **pushed by the process, on a defined schedule, as an explicit statement
of health** — not inferred by an observer scraping output. The previous generation inferred liveness
from heartbeat-file age and screen text, and FIELD-NOTES documents both failure directions:

- *False stall:* a session heartbeats **between** turns, so a validator running a 14-minute suite
  never heartbeats. Six healthy sessions nudged [C].
- *False alive:* "a shell that cannot exit reads as work" — a lane held one shell running
  `until grep … sleep 5` against a file that had finished being written 45 minutes earlier. The
  pattern could never match, the loop could never end, **and no check would ever have called that
  session parked** [C].

**A pushed watchdog with an explicit turn-boundary protocol fixes both.** Have the agent emit
`WATCHDOG progress=<n> phase=<s>` on a schedule *including during long turns*, and treat a missing
signal as unknown-not-dead, escalating on a ladder. Then "is it alive?" stops being a screen-scraping
inference problem. **This is the highest-leverage design change available from the supervisor
literature** — and note that it changes what you test from "did the detector guess right?" to "did the
protocol get followed?", which is a far cheaper test.

**Caveat [I].** It requires cooperation from the agent, and R1-11 allows headless sessions where you
may not control the output stream. So: pushed signal where possible, inferred as fallback, and the
*inference* path keeps the §8.4 corpus.

### 9.4 The single-orchestrator invariant (R1-10) deserves its own testing

"не може бути такого, що вже якісь існуючі оркестратор і спускається наступний … якщо раптом одночасно
два якісь оркестратори працюють, то це не окей."

**[V] I raced three candidate primitives, 50 concurrent acquirers, 3 rounds each:**

| Primitive | Winners per round | Verdict |
|---|---|---|
| `mkdir "$LOCK"` | 1, 1, 1 | exclusive |
| `( set -o noclobber; echo $$ > "$LOCK" )` | 1, 1, 1 | exclusive |
| `[ ! -f "$LOCK" ] && echo $$ > "$LOCK"` (naive check-then-write) | **18, 18, 23** | **broken** |

Also verified [V]: `flock` is **not present on macOS**; `shlock` and `lockf` are (`/usr/bin/`).
`ln -s` is also atomic here. Use `mkdir` or `noclobber`; both are portable and dependency-free.

**But the far more important result is the one that corrected me [V].** My first naive-pidfile racer
contained a `sleep 0.01` between the check and the write. Suspecting that had done the work, I re-ran
**without** it — 100 concurrent acquirers, 5 rounds:

```
  round 1: winners=1     round 2: winners=1     round 3: winners=1
  round 4: winners=1     round 5: winners=1
```

**The broken primitive passed every round.** So I swept the injected delay:

| Injected delay between check and write | Winners (of 60) |
|---|---|
| 0 | **1 — test passes, bug invisible** |
| 0.001 s | 5 |
| 0.005 s | 13 |
| 0.02 s | 26 |

**This is the most important single result in this document [I].** A concurrency test that merely runs
things in parallel *proves nothing* — it passed five rounds of 100 against a primitive that is
categorically broken. It found the bug only when I **deliberately widened the race window**. Which
means: *scheduling perturbation is not an optional extra on top of concurrency testing; it is the part
that does the work.*

**Wire it here.** Give every critical section a `TEST_DELAY_<name>` hook that injects a configurable
sleep at the dangerous instant, and run the concurrency suite across a ladder of delays. FIELD-NOTES
§10.2 `J-T169-01` records the same lesson learned the hard way: before the fix, two concurrent ticket
`add`s produced two files under one id **in five rounds out of five**, and a twenty-way add produced
twenty files under three ids [C]. They got lucky that the ticket-id window was wide enough to show
itself. The orchestrator-lock window may not be.

**Then test what the loser does.** Exclusivity is half the requirement. The second orchestrator must
exit cleanly, say why, and not tear down the first one's sessions (R1-16, Д3). Assert on the loser's
exit code, its message, and — critically — that it touched nothing.

**And test lock staleness.** A crashed orchestrator leaves a lock. The recovery path (R1-10: "start
over means restart the orchestrator, not redo the work") must reclaim it, which means proving the
holder is dead — and `kill -0` on a recycled pid is a known trap. Fixture: a lock whose pid now belongs
to an unrelated process. This is the same defect class as FIELD-NOTES' dead run that flagged
`STOPPED present with no run.complete` every three minutes **for about five days, 1085 times,
unresolved** [C].

---

## 10. Fault injection and chaos, scaled to one machine

Chaos engineering for a Mac, not a fleet. The goal is not a chaos platform; it is a set of cheap,
deliberate perturbations.

### 10.1 What to inject, ranked by what FIELD-NOTES says actually happened

| Fault | Injection | Requirement / evidence |
|---|---|---|
| Agent process dies mid-turn | fake agent exits non-zero at turn N | R1-09, Д10 |
| Agent hangs silently | fake agent sleeps forever, no output | R1-09; §1.1 council-advisor hung 40 min, never returned [C] |
| Orchestrator killed | `kill -9` the loop mid-tick | R1-10; the 85-min loop ended only on external SIGTERM [C] |
| Quota API 401 / timeout / garbage | cassette | R1-06; **live right now** [V] |
| Board unreachable | fake board returns 500 | R1-04 |
| Disk full / read-only | tmpdir on a small image | atomic-write paths |
| Clock jumps backwards | clock seam returns a smaller value | §11.7 fixed-past-epoch regression [C] |
| Memory pressure | `stress-ng`-style load | §11.5 owner's container OOMKilled; watcher's collector OOM-killed **26+ times** [C] |
| Config file torn mid-write | write half a file | §4.1 |
| Two orchestrators race | §9.4 harness | R1-10 |

**Scheduling perturbation belongs in this table too**, per §9.4 — it is the injection that makes the
concurrency faults visible at all.

### 10.2 Crash-recovery testing deserves special emphasis

R1-10 is one of the hardest requirements: survive your own death, never run two orchestrators. The
standard technique is **crash-at-every-step**: run a scenario to step N, `SIGKILL`, restart, assert
the invariants hold; loop N over every step. With a fake agent and a virtual clock, a 30-step scenario
is 30 sub-second tests.

**The invariants to assert after every crash point:**

- exactly one orchestrator runs (§9.4);
- no ticket is lost, and none is in-progress with no live session (FIELD-NOTES notes the previous
  run's report claimed **zero stranded in-progress tickets** — a real, checkable property [C]);
- nothing the orchestrator did not start was touched (R1-16, Д3);
- no duplicate work — "restart the orchestrator, not redo the work" (R1-10);
- every state write was atomic — no half-written registry entry.

**Cost.** Medium to build the runner, then near-zero per scenario. **This is the test tier that most
directly answers "convince me it will work" [I].**

### 10.3 The real-environment tier

Some things cannot be faked, and their bugs are the ones that actually bit. Keep a small, slow,
manually-triggered tier that runs against real tmux, a real scratch git repo, real Docker and the real
CLI, asserting only adapter-level contracts — never agent quality. Ten to twenty tests, minutes to
run, executed before a release rather than on every commit.

**What lives here:** terminal send/capture round-trip (§11 below), git worktree lifecycle, the merge
behaviour of §11.4, Docker project isolation, real `claude --version`-shaped conformance checks that
the fakes still resemble reality (§3.2's caution).

---

## 11. The terminal is the highest-risk adapter, and it is testable

FIELD-NOTES' single largest failure family is text typed at a session that never arrives: **five
separate instructions never delivered** in one run, including two real operator instructions —
`push master` and `carry on with the queue` — sitting unsubmitted in input boxes while the engine log
recorded them as nudged [C].

**[V] I reproduced the mechanism, and found its exact boundary.** Using tmux, a fake agent that logs
the length of every line it actually receives (the ground truth of delivery), and one fresh pane per
size:

| Characters sent + Enter | Delivered? |
|---|---|
| 100 | yes |
| 200 | yes |
| 450 | yes |
| 1000 | yes |
| **1023** | **yes** |
| **1024** | **no — silently** |
| 1100 | no |
| 2000 | no |

**The boundary is exactly 1024 — the tty line discipline's canonical-mode input limit (`MAX_CANON`).**
FIELD-NOTES §12.1 records this as "`send` fails silently above roughly 200 characters", with a
~1100-char message vanishing and a ~450-char version of the same message landing [C]. **Both of their
observations are consistent with a 1024 limit; their stated threshold of ~200 was a guess, and the
real cause is a fixed OS-level buffer.** No error is raised at any layer.

**What this buys the rebuild.**

1. **A real root cause instead of folklore.** The rule is not "keep messages short"; it is "a single
   canonical-mode line cannot exceed `MAX_CANON`". The fix is to chunk below the limit, or bypass the
   line discipline, or write to a file and send a short command that reads it — and each of those is
   now a testable contract.
2. **A test that would have caught it**, and which costs one fixture:

```bash
# assert_delivered <text> — the round-trip the previous generation never made
send_to_session "$s" "$text"
wait_for_delivery_ledger "$s" "$(hash "$text")" || fail "send reported success, nothing arrived"
```

   **Every send must be delivery-confirmed, never fire-and-forget.** FIELD-NOTES describes exactly one
   instruction all run whose arrival was verified three ways, and it was the one that worked [C].

3. **Also verified [V]:** typing without Enter strands text (nothing delivered), and a subsequent
   oversized send does not recover it. FIELD-NOTES adds that `send` *overwrites* pending text and that
   a recovery attempt destroyed the instruction it was recovering [C]. So the contract is three-part:
   confirm delivery, never type over a non-empty line, and detect a non-empty line before sending.

**Cost.** tmux is installed [V] and drives headlessly — detached session, `send-keys`, `capture-pane`,
poll for an expected string with a bounded timeout, never a fixed sleep. `expect` is also present [V]
for pty-level work. This tier is cheap and it covers the riskiest adapter in the system.

**The fidelity caveat, restated because it matters.** tmux + a fake agent is not Claude Code's TUI —
§3.2 shows a case where the two disagree in a way that would invert a test's verdict. Use tmux for
*mechanism* tests (buffer limits, round-trip confirmation, stranded-line detection) and a small real-CLI
conformance tier for *behaviour* claims.

---

## 12. Property-based, model-based and metamorphic testing

### 12.1 Property-based testing for state machines

**What it is.** Instead of examples, state invariants and let a generator search for a counterexample,
then shrink it to a minimal case. For stateful systems, Hypothesis's `RuleBasedStateMachine` generates
*sequences* of operations and checks invariants after each [C].

**Properties worth asserting about this orchestrator [I]:**

- **Never two orchestrators** (R1-10) — after any interleaving of start/crash/restart.
- **Concurrency cap respected** (R1-05) — live sessions never exceed the configured max, under any
  sequence of spawns, completions and failures.
- **No dependency violation** (R1-05) — a task whose predecessor has not completed never starts.
- **Touch-nothing-unstarted** (R1-16, Д3) — the set of processes/containers acted on is always a
  subset of the set the orchestrator started. This is a *set-containment* property, ideal for PBT, and
  it directly targets the `pkill -f 'playwright test'` incident that killed an unrelated lane because
  every lane's own prompt text contained that literal string [C].
- **Hard beats soft** (R1-06, R1-07, Д12) — for any sequence of control-file writes, a hard command
  applied at tick T is never overtaken by a soft one.
- **Monotonic ticket progress** — a ticket never moves backwards except through an explicit release.
- **Idempotent reconciliation** (§9.1) — `decide()` twice on an unchanged world acts once.

**Cost.** Medium, and honestly assessed: **Python has no `hypothesis` on this machine** [V] (nor
`pytest`, `freezegun`, `vcrpy`). A `pip install` into a venv is trivial, but it makes the test suite
depend on a Python toolchain the plugin does not otherwise need. **[I] Recommendation: do not adopt a
PBT framework on day one.** Write the properties as *assertions inside the scenario runner* first —
checked after every action of every scenario, which is where most of the value is. Add a generator
later if the properties keep passing and you want search. A hand-rolled sequence generator over a
dozen operations is ~100 lines if it comes to that.

### 12.2 Model-based testing

**What it is.** Write a simple reference model of the intended behaviour; run model and implementation
on the same input sequence; assert they agree.

**Where it earns its place here [I]:** the **ticket/board state machine** (R1-04, Д2, Д8, Д9). Statuses
move `ready → in-progress → done | blocked | needs-review`, across two backends (local files, GitHub
Issues) that must behave identically, with user-overridable status names (R1-04). A 50-line model of
the intended transitions, run against both backends, catches divergence immediately. FIELD-NOTES §12.6
records precisely this class: `harness-tickets.sh done` leaves a previously-blocked issue holding
**two state labels**, because `blocked` is never removed — seen twice [C]. A model would have caught it
the first time.

**Cost.** Low for this one machine; do not model the whole orchestrator.

### 12.3 Metamorphic testing — for when there is no oracle

**The idea.** When you cannot say what the right output is, you can often say how the output must
*relate* across two runs [C]. That is exactly this system's situation: R1-01 says there is no universal
measurable definition of a good run, and R1-13 refuses to impose verification.

**Usable metamorphic relations here [I]:**

- Rename a ticket's id → the plan is identical modulo the id. (Catches id-dependent logic.)
- Reorder independent ready tickets → the same set of tasks starts, order aside.
- Double every duration in the world → the same decisions, at doubled times. (Catches hardcoded
  constants hiding among the configured ones.)
- Add an unrelated ticket that is not ready → no change to the plan.
- Run with `output=verbose` vs `output=silent` (Д11) → **identical decisions**, different printing.
  This is a genuinely valuable one: it asserts that observability does not alter behaviour.

**Cost.** Very low once the scenario runner exists — each relation is a second run plus a diff. **[I] A
quietly high-value technique for this system specifically, because so much of it is "user-configured"
and therefore has no fixed oracle.**

---

## 13. Mutation testing as the meta-gate — the house rule, mechanised

The repo already has the rule ("contract tests must be verified by mutation"). §1 shows it was not
enforced: 4 of 5 behaviour-killing mutations passed.

**Make it a gate, not a habit [I].**

Maintain `tests/mutations/` — one file per mutation, each declaring the edit and the test id that must
fail:

```
# tests/mutations/M-rate-gate-dead.mut
target:  bin/orchestrator-limits.sh
apply:   s/if \[ "\$v" = "PAUSE" \]/if [ "$v" = "PAUSE_X" ]/
expect_fail: LIMITS-07, LIMITS-08
```

The runner copies the tree to a tmpdir, applies the mutation, runs the suite, and **fails if the named
tests still pass**. Keep it to 15–30 hand-picked mutations aimed at the *safety-critical* behaviours —
the quota gate, the single-orchestrator lock, the never-touch-what-I-did-not-start rule, delivery
confirmation, hard/soft semantics. Full mutation coverage is not the goal; proving the contracts can
fail is.

**Cost.** Low — ~100 lines of runner. A copy-and-run of the current suite takes ~2 s [V], so 30
mutations is about a minute. **[I] This is the single mechanism that most directly answers "I want to
change it without fear": it is a test of the tests.**

**Also worth knowing [V]:** `shellcheck` is installed; `bats` and `kcov` are not. Coverage tooling for
bash is weak, and mutation testing is the better investment for this codebase anyway, because it
measures *detection* rather than *execution*.

---

## 14. The environment is a test surface — three live hazards found here

FIELD-NOTES §11.3 and §12.4 describe tool-dialect and environment bugs. I probed for them and found
this machine currently carries three.

**14.1 `find` is not `find` [V].** On the interactive `PATH`, `find` resolves to **`bfs` 4.1.1**, not
`/usr/bin/find`. Under `env -i` — which is what `launchd` and `nohup` give a detached process —
`find` resolves to `/usr/bin/find`. **The same script runs two different programs depending on how it
was started**, and they do not accept the same flags (`/usr/bin/find` rejects `-color`, which `bfs`
accepts [V]). FIELD-NOTES §12.4 records exactly this family: three detached scripts had to export
their `gh` account themselves "because launchd and `nohup` start with no environment" [C]. `grep` is
shadowed too [V].

**14.2 `/tmp` is a symlink, and `find` does not descend it [V].** `/tmp -> private/tmp`. A file just
created in `/private/tmp` is **not** found by `/usr/bin/find /tmp -maxdepth 1 -mmin -10`, but **is**
found by the same command rooted at `/private/tmp`. A freshness probe written against `/tmp` silently
returns empty for ever — which is the same *symptom* as FIELD-NOTES' BSD `-newermt` bug ("would have
declared every healthy session idle for ever"), from a **second, independent cause** [V/I].

**14.3 `date` is BSD [V].** `date -v-8d` works; `date -d '8 days ago'` fails with
`illegal option -- d`. The current suite's `H-46` already handles this with a fallback — good — but it
is a standing hazard for anything new.

**The testing conclusion [I].** Two rules, both cheap:

1. **A preflight that asserts the tool dialect** — resolve each external binary, confirm it is the
   expected implementation, confirm the flags actually used are accepted. Run it at run start and in
   CI. This is R1-07/R1-17's "verify before you run" applied to the toolchain.
2. **Run the suite twice: once in the developer's environment, once under `env -i` with a minimal
   `PATH`.** These find different bugs, and the second is the one the unattended run will actually
   experience. Cost: one extra CI line.

---

## 15. Proposed test architecture

Five tiers. Only the first two gate a commit.

| Tier | What | Deps | Runtime | Gates commit? |
|---|---|---|---|---|
| **0 — static** | `bash -n`, `shellcheck`, JSON/YAML validity, config-schema, tool-dialect preflight | none | < 5 s | yes |
| **1 — unit / reconciliation** | `decide(world) → plan` table tests; detector corpus (§8.4); parsers; clock-boundary tests; config precedence (Д1) | none | < 30 s | yes |
| **2 — hermetic integration** | Scenario runner: fake agents, fake board, cassettes, virtual clock, crash-at-step-N, concurrency + scheduling perturbation, golden decision logs | fakes only | 1–3 min | yes |
| **3 — mutation** | 15–30 curated mutations must fail their named tests | none | ~1 min | yes (nightly or pre-release if slow) |
| **4 — real environment** | tmux round-trip, real git worktrees, Docker isolation, CLI conformance, cassette re-record vs live API | real tools, one real account | 5–15 min | **no** — manual / pre-release |

**Only tier 4 can cost money, and only its conformance and re-record jobs.** Everything that gates a
commit is free and offline. That satisfies the single-operator constraint without giving up rigour.

**The 475-test repo harness.** A plugin is only covered if listed in `tests/run-all.sh`'s `PLUGINS`
array [V]. Tiers 0–2 belong in `plugins/<name>/tests/run.sh` so `run-all.sh` picks them up. Tiers 3–4
should be separate entry points (`tests/mutations.sh`, `tests/real.sh`) invoked deliberately —
`run-all.sh` currently runs each plugin's runner **twice** to re-extract counts [V], which is fine for
fast static tests and would be wasteful for slow ones.

---

## 16. Requirement → technique map

| Requirement | Primary technique | Tier |
|---|---|---|
| R1-01 finished run is user-defined | metamorphic (§12.3); no universal oracle | 2 |
| R1-02 what may be delegated | config precedence table tests | 1 |
| R1-03 pluggable process (GSD/superpowers/custom) | fake process adapter; golden step sequence | 2 |
| R1-04 queue source + readiness | model-based over both backends (§12.2) | 1–2 |
| R1-05 concurrency + dependencies | property tests; scheduling perturbation | 1–2 |
| R1-06 limits, hard/soft, accounting | cassettes + virtual clock + boundary tests | 1–2 |
| R1-07 accounts, roles, control file | fake env-switcher; control-file protocol tests (§4.1) | 1–2 |
| R1-08 context exhaustion, guaranteed compaction | fake agent with rising ctx%; tmux round-trip | 2, 4 |
| R1-09 silent session | fake-agent behaviour matrix; §8.4 corpus | 1–2 |
| R1-10 orchestrator dies; single-instance | lock race + perturbation (§9.4); crash-at-step-N | 2 |
| R1-11 visible/headless per platform | argv/env golden matrix per platform | 1–2 |
| R1-12 reaching the trunk | fake `git`/`gh`; real worktrees in tier 4 | 2, 4 |
| R1-13 verification belongs to the process | assert the orchestrator imposes **no** checks — a negative test | 1 |
| R1-14 autonomy / escalation | decision-policy table tests; golden decision log | 1–2 |
| R1-15 the red-line file | assert it is read by every spawned prompt (prompt golden) | 1 |
| R1-16 touch nothing unstarted | set-containment property; fake `docker`/`kill` argv | 1–2 |
| R1-17 notifications verified pre-run | fake sink; assert refusal on broken channel (§4.2) | 1 |
| Д1 config precedence | table tests over the six slots / three levels | 1 |
| Д3 clean end, no tails | set-containment on teardown targets | 2 |
| Д4 worktrees | real git scratch repo | 4 |
| Д5 three strikes | virtual clock windows | 1 |
| Д6 questions channel non-blocking | scenario: blocked task + independent queue continues | 2 |
| Д7 mid-run behaviour change | control-file protocol + tick-boundary assertion | 2 |
| Д8 ticket changed mid-flight | fake board mutation mid-scenario; assert silence when unchanged | 2 |
| Д9 contradicts finished work | decision-policy table | 1 |
| Д10 restart with executors alive | crash-at-step-N with live fakes | 2 |
| Д11 status output silent by default | golden: assert empty output | 1 |
| Д12 stop-hard / stop-soft / stop-custom | control-file protocol; hard-beats-soft property | 1–2 |

**Note on R1-13.** The negative test matters. The requirement is explicit that the orchestrator must
impose no verification of its own — so there should be a test that *fails if it starts to*. Scope creep
in a supervisor is a real risk, and this is how you pin the boundary [I].

---

## 17. What I verified on this machine

Everything below was run in this session on 2026-09-21; probe scripts are under
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/`.

1. **Baseline:** `plugins/harness/tests/run.sh` → `PASS=51 FAIL=0`; 382 lines, 83 `grep` calls; header
   declares "static assertions, no source mutation, no network, no terminals".
2. **Mutation:** 4 of 5 behaviour-killing mutations pass 51/51 — dead rate gate (M1), neutered
   `wait_clear` (M2), commented-out session close (M4), disabled spawn validator (M5). Only M3 failed,
   caught solely by `H-44/45/46`, the only three tests that execute a script against a fixture.
3. **Fake binary on `PATH`** intercepts and replays scripted CLI behaviour; argv captured for assertion.
4. **The real quota gate driven hermetically** via a 3-line `curl` shim: OK / PAUSE-session /
   PAUSE-weekly / fractional 99.5 / null / string / 401, all in milliseconds, no network, no spend.
   `snapshot()` has **no injection seam** (`grep` for `HARNESS_(USAGE|FAKE|SNAPSHOT)|_FIXTURE` → none);
   the `PATH` shim is what makes it testable.
5. **Live:** the usage endpoint returns **HTTP 401 `authentication_error`** right now. A naive
   `jq -r .five_hour.utilization` of that body yields `null`; `[ "$U" -ge 90 ]` then errors, and with
   `2>/dev/null` takes the no-pause branch. The shipped code correctly fails closed to `UNKNOWN`.
6. **Schema divergence (unresolved):** the shipped parser wants `.limits[].group`/`.percent`;
   `CLAUDE.md` documents `five_hour.utilization`. Fed the documented shape, the parser returns
   `UNKNOWN`. Cannot determine which is live while the endpoint 401s. Possible cause of FIELD-NOTES'
   recurring `weekly_all=unreadable%`. **Nothing changed — flagging only.**
7. **Virtual clock:** `now()` seam drives a stall detector across 19/20/21 minutes and 44,791 s in zero
   wall-clock time. `libfaketime` is not installed and is not needed.
8. **Terminal delivery boundary:** with tmux and a delivery ledger, sends of 100/200/450/1000/**1023**
   chars arrive; **1024**/1100/2000 **vanish silently**. The boundary is the tty `MAX_CANON` limit.
   This explains FIELD-NOTES §12.1 and corrects its "~200 characters" estimate. Typing without Enter
   strands text; a subsequent oversized send does not recover it.
9. **Lock primitives, 50-way × 3:** `mkdir` 1/1/1, `noclobber` 1/1/1, naive check-then-write
   **18/18/23**. `flock` absent on macOS; `shlock`, `lockf` present; `ln -s` atomic.
10. **Scheduling perturbation — the result that corrected me:** the naive lock passed **5 rounds of 100
    concurrent acquirers** with no injected delay. Winners rose 1 → 5 → 13 → 26 as the injected delay
    went 0 → 1 ms → 5 ms → 20 ms. Parallelism alone does not find races; widening the window does.
11. **Detector false positive reproduced:** a `usage limit reached|limit will reset at` regex fires on
    the orchestrator's own prose and on the pattern quoted in a report — the mechanism behind the
    85-minute self-sustaining loop. A last-non-empty-line anchor passes all three cases.
12. **Environment hazards:** `find` → `bfs` 4.1.1 interactively but `/usr/bin/find` under `env -i`
    (different flag dialects); `/tmp` is a symlink that `find` will not descend, so `/tmp`-rooted
    freshness probes return empty for ever; `date` is BSD (`-d` fails, `-v` works). `grep` is also
    shadowed.
13. **Toolchain present:** `shellcheck`, `jq`, `tmux`, `expect`, `docker`, `gh`, `sqlite3`, `python3`,
    `node` 22, `bun`, `playwright`. **Absent:** `bats`, `faketime`, `socat`, `flock`, `kcov`, and all of
    `pytest` / `hypothesis` / `freezegun` / `vcrpy` / `pexpect`.
14. **The brief's evidence file does not exist:** `scratchpad/context/harness-evidence.md` is absent;
    `context/` is empty.

---

## 18. Open questions for the owner

1. **Quota schema (§4.3).** Which shape is live? Needs a working token. If the parser is stale, the
   quota gate has been failing closed — safe, but blind — and R1-06's thresholds have never actually
   fired on real data.
2. **Pushed vs inferred liveness (§9.3).** A pushed watchdog signal is far more testable and kills two
   whole failure families, but requires cooperation from each platform's agent. Is that acceptable
   given R1-11 allows headless sessions you may not control?
3. **Is `decide()/apply()` acceptable as an architectural constraint (§7)?** It is the precondition for
   most of this document. It costs nothing up front and cannot be retrofitted cheaply.
4. **How much real-CLI conformance is worth paying for (§10.3)?** My recommendation is 10–20 tests, run
   pre-release, on one account — but that is the only line item with a cost, and it is your call.
5. **PBT framework or hand-rolled properties (§12.1)?** Adding `hypothesis` means the plugin's tests
   depend on a Python venv. I lean hand-rolled first.

---

## 19. Sources

Web sources consulted for the literature sections, all read 2026-09-21:

- [Deterministic simulation testing — Antithesis docs](https://antithesis.com/docs/resources/deterministic_simulation_testing/)
- [What's the big deal about Deterministic Simulation Testing? — notes.eatonphil.com](https://notes.eatonphil.com/2024-08-20-deterministic-simulation-testing.html)
- [Protocol-Aware Deterministic Simulation Testing — TigerBeetle](https://tigerbeetle.com/blog/2026-08-20-protocol-aware-dst/)
- [Deterministic Simulation Testing for Our Entire SaaS — WarpStream](https://www.warpstream.com/blog/deterministic-simulation-testing-for-our-entire-saas)
- [Building an open-source version of Antithesis, Part 1](https://databases.systems/posts/open-source-antithesis-p1)
- [openthesis — open-source Antithesis alternative](https://github.com/openthesis/openthesis)
- [Testing Production Kubernetes Controllers — SuperOrbital](https://superorbital.io/blog/testing-production-controllers/)
- [Fake Client vs envtest vs Testcontainers K3s](https://bex.co/blog/2026/07/12/testcontainers-k3s-module-operator-testing)
- [Testing — kube-rs controller guide](https://kube.rs/controllers/testing/)
- [Supervisor Behaviour — Erlang/OTP design principles](https://www.erlang.org/doc/system/sup_princ.html)
- [Who Supervises The Supervisors? — Learn You Some Erlang](https://learnyousomeerlang.com/supervisors)
- [sd_notify — systemd manual](https://www.freedesktop.org/software/systemd/man/latest/sd_notify.html)
- [Set Up systemd Watchdog Monitoring](https://oneuptime.com/blog/post/2026-03-04-set-up-systemd-watchdog-monitoring-for-critical-services/view)
- [Rule Based Stateful Testing — hypothesis.works](https://hypothesis.works/articles/rule-based-stateful-testing/)
- [Stateful tests — Hypothesis documentation](https://hypothesis.readthedocs.io/en/latest/stateful.html)
- [VCR — record and replay HTTP interactions](https://github.com/vcr/vcr)
- [Using VCR and pytest with pytest-recording — Simon Willison](https://til.simonwillison.net/pytest/pytest-recording-vcr)
- [Approval Testing and Golden Master Testing Guide — QASkills](https://qaskills.sh/blog/approval-testing-golden-master-guide)
- [Metamorphic Testing: A Simple Approach to Alleviate the Oracle Problem — IEEE](https://ieeexplore.ieee.org/document/5569943)
- [Testing terminal user interface apps — Waleed Khan](https://blog.waleedkhan.name/testing-tui-apps/)
- [termlens — headless PTY test harness](https://github.com/cestercian/termlens)
- [kcov — coverage for compiled programs, Python and Bash](https://github.com/SimonKagstrom/kcov)
- [Get Experience from Practice: LLM Agents with Record & Replay (arXiv 2505.17716)](https://arxiv.org/pdf/2505.17716)
- [Rethinking Testing for LLM Applications (arXiv 2508.20737)](https://arxiv.org/pdf/2508.20737)
- [Maximizing Error Injection Realism for Chaos Engineering with System Calls (arXiv 2006.04444)](https://arxiv.org/pdf/2006.04444)
- [Testing Distributed Systems — curated list, asatarin](https://asatarin.github.io/testing-distributed-systems/)
- [Porcupine — fast linearizability checker](https://github.com/anishathalye/porcupine)

Repository and local sources: `plugins/harness/tests/run.sh`, `plugins/harness/bin/*.sh`,
`plugins/harness/docs/FIELD-NOTES.md`, `tests/run-all.sh`,
`product/spikes/harness-rebuild/round-1/ANALYSIS-01.md`, and the owner's global `CLAUDE.md`.
