# Round 2 — context for the interviewer

Read this before the session. **Do not read it aloud.** Use it only when the owner asks what a
question means, what a word means, or why something is being asked — then answer in one or two
sentences and return to the item.

## Where this stands

Round 1 is analysed. Eighteen listed items plus twelve raised outside the list were answered and
confirmed; one answer was cut off mid-sentence when the session ended. Between the rounds, research
was done against real systems: fifteen agent platforms probed hands-on, the field of comparable
orchestrators rebuilt and verified, four competing architectures designed, judged and attacked, and
an evaluation plan drafted. This round exists because that work produced three kinds of question:
things he must define, things his own answers collide on, and things a platform physically cannot do.

The tool is called **оркестратор** (orchestrator) — he renamed it during round 1 [118].

## What round 1 settled — never re-ask these

- **Success is what the user configured.** No universal definition of a good night; an external stop
  (lost access) is not a plugin failure [062].
- **The orchestrator runs a process it does not own** — an existing one (GSD, superpowers) or a fully
  custom one — never a mix [118]. Whether the new default pair below counts as a mix is open: item А-08.
- **It is not only for code.** No assumption of tests, repos or builds [344].
- **Work comes from a local registry or a connected board** (GitHub Issues first, ClickUp, any), and
  the orchestrator sets statuses and comments there [129, 149].
- **The user sets the concurrency maximum**; dependency-blocked work does not start; machine-resource
  awareness is deferred [160, 163].
- **Limits:** wait for a reset and continue; thresholds are user-set; hard stop = now, soft stop =
  finish the current task and start nothing new [034, 171].
- **Roles may sit on different accounts**, assigned in one watched file; a change is soft or hard
  [195]; per-platform switching must be explained and verified before a run [199].
- **Context:** user-set threshold, soft waits for the current step, hard stops now; per platform or
  per session; for the orchestrator, compaction or a fresh session; the command is configurable and
  the action must be guaranteed [204, 209].
- **A silent session is the orchestrator's judgement call**, not a fixed timeout ladder [231].
- **Never two orchestrators of one run** — a launch journal and a liveness check before starting a
  new one [300].
- **Sessions may be interactive or headless per platform**, and the orchestrator may answer a
  session's question within its authority [324].
- **Reaching the trunk is configurable** and must respect repo rules such as PR-only [331].
- **Verification belongs to the configured process**, not to the orchestrator [344].
- **One text file of prohibitions** every agent must read [357].
- **Notifications:** any channel the user configures, verified to work; terminal-only is valid [395].
- **He keeps building his own** rather than adopting someone else's tool [403].
- **Configuration precedence follows his own the owner's company marketplace rules** [416].
- **Work added mid-run is picked up if ready** [422]; **the run ends when no ready work remains**, and
  stops only what it started [430]; **worktrees are the default recommendation**, one per task off the
  main branch [433]; **three identical failures then act per configuration** [442]; **independent work
  continues while one task waits**, with a single user-configured questions channel [449]; **default
  is to stay and wait**, changeable mid-run [455, 458]; **an active ticket's description is watched by
  a cheap model** [466]; **changes to finished work prefer a new ticket** [482]; **the orchestrator
  prints nothing unless asked** — status comes from a separate command [508, 512].

## Decided after round 1 — never re-ask, only А-08's one point

- **The workflow is agnostic and built from replaceable elements** (owner, 2026-11-01). Default: GSD for
  execution, OpenSpec for requirements; OpenSpec can be swapped for another requirements format he prefers.
  The only open point is whether this pair falls under the "never a mix" rule [118] (item А-08); either
  answer is his, and the item is open for discussion even though rejected item 5 below cites [118].
  Recorded as requirement H-001 in `plugins/harness/openspec/`.

## The confidence problem behind block А

Counted mechanically: **22 of 48 restatements in round 1 never got his «так»** — the session simply
moved on, and six times the interviewer confirmed on his behalf. No decision is in doubt because of
this, but four load-bearing ones are unratified and everything else is denominated in them: the
prohibitions file, the stop vocabulary, notifications, and the health check he actually disowned
(«це не як правило, це лише просто пояснення»). Block А closes them before anything is built on top.
The full audit is in `round-1/ANALYSIS-01-ERRATA.md`.

## Already rejected — never propose these

1. **Patching the old tool incrementally.** It is being rebuilt from zero.
2. **Tying the orchestrator to one workflow engine.**
3. **Naming a specific vendor or tool inside the plugin's own code** — sources are configured, resolved
   at run time.
4. **Adopting an existing open-source orchestrator instead of building** — he decided this in round 1
   [403], and the research confirmed it: neither DeepSeek Harness nor OpenClaw does this job.
5. **Combining a ready-made process with a custom one** [118]. (Whether GSD + OpenSpec is such a combination is item А-08 — discuss it.)

## What the research changed, in plain terms

Use these only if he asks why a question exists.

- **Seven of fifteen platforms cannot report how much quota is left at all.** His rule "wait for the
  reset and continue" has nothing to stand on there.
- **Two incompatible worlds of capacity exist:** a window that resets at a known time (Claude, Codex,
  Kimi, Copilot, GLM) and a credit balance that never resets (DeepSeek, Amp, Cursor). Percentages are
  meaningless in the second.
- **GLM's concurrency limit is contractual, not technical** — 1 to 2 sessions by plan, with a ban after
  three violations. **Kimi pools every device and key into one account pool**, so two lanes on one
  account halve each other.
- **No platform, of fifteen, can change a live session's account.** A hard account change means: stop
  the session, start a new one, pay for the context again.
- **On four platforms compaction cannot be triggered from outside at all**, so his hard mode cannot
  exist there.
- **Several of his own settings have no default**, and seven of them compound into a run that parks on
  the first question and waits forever, printing nothing.
- **Three of his answers were never confirmed**: the stop commands (the session ended mid-answer), the
  clause that an autonomous run may stop itself, and a limit reserve for his own daytime work, which
  the interviewer lost entirely.
- **His own boundary answer was recorded with the interviewer's words, not his.** He refused a
  *container*; he himself proposed a path list. Nobody offered him the middle option.

## Words used in the questions

- **Ран** — one unattended stretch of work. **Лінія (lane)** — one platform + account + role working
  one ticket. **Провайдер** — the platform or endpoint the model comes from. **Дошка** — the board or
  local registry work comes from. **Компакт** — squeezing a session's history so it can continue.
  **Хардстоп / софтстоп** — act now / act at the next safe boundary. **Сторож (watchdog)** — a small
  external check that the run is still alive. **Канал питань** — the single place where a blocked
  session leaves a question for him.
