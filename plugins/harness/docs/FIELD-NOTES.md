# Field notes — what the 0.6.0 engine did in two long unattended runs

These are observations from two unattended runs of harness 0.6.0 against one real project. The first run lasted about a week. The second ran 34 hours and planned nineteen phases, one ticket per phase.

Not every record is about the plugin's own code. The project ran its own helper scripts beside the plugin: a watcher session with its own detectors, and a supervisor script that paused and resumed runs. Records A10, F4, F5, I1, I2, I3 and I5 come wholly or partly from those helpers or from the project's own checks. So do single facts inside A4 (the "held" log entry), A6 (the repeated alert) and F2 (the reader pointed at another account folder). They stay because the new engine takes over the same jobs.

This file is a filtered copy. It keeps only what helps to build or test the rebuilt engine: a failure the new engine must not repeat, a measured cost, a check that caught a real defect, or a test scenario. Records about parts that the rebuild drops are gone.

How to read a record:

- The text states what happened. It gives no recommendation.
- **Why it matters** is one line that ties the record to the new engine.
- **Relates to** names requirement IDs (`H-…`) and design decisions (`D…`, `S8-…`) from the change `harness-stable-beta`. "No requirement" means none fits.

The raw logs these records come from are in a private project and are not public. Session, branch and ticket names are removed. Where the source contradicts itself, the record says so and does not pick a side.

Context for section A: the old engine called a session stalled when three things held together. Its heartbeat file was older than 20 minutes, git showed no recent activity, and its screen did not show the "working" marker. The reaction was one typed Enter.

## A. Liveness, recovery and closing

**A1. A stale heartbeat was not a stall.** A session wrote its heartbeat between turns only. A validator in a 14-minute test suite, or a worker in one long turn, wrote none. The stall rule fired on healthy sessions throughout the second run. The source counts the nudges three ways: 6 in one pass, 12 in another, 33 in a count over the full logs. It calls the sessions behind the 6 and the 12 healthy. It gives no verdict for the 33. In the first run the same nudge also went to an orchestrator that was later found dead (see A6).
*Why it matters:* liveness must come from what the session does, not from a file the agent remembers to write.
*Relates to:* H-089, H-091.

**A2. A shell that can never exit read as work.** One session held a shell running `until grep … ; sleep 5` against a file that had been complete for 45 minutes. The pattern could never match. The count of running shells was the strongest "busy" signal, so no check would ever have called that session idle.
*Why it matters:* "a child process exists" and "tool calls keep coming" are not progress.
*Relates to:* H-089, H-090.

**A3. A session burned its context on polling.** One worker waited for subagents by running `echo idle` in a loop instead of ending its turn. Of its 3,626 shell calls, 3,466 were that command, one every 2.5 seconds for 3 hours 15 minutes. The idle replies added 445k tokens of context, 77% of all growth in that window, against 135k from real work. The session reached 91% of its window. It stopped within one minute of being told to end its turn. Eleven other workers in the same run never polled. The polling worker had loaded the `Monitor` tool and never used it. Its prompt warned that subagents may hang; the source names that warning as the likely cause (see also C3). A different worker built up 58 concurrent `sleep` shells over two hours; each returned output into the session.
*Why it matters:* a hook log full of tool calls can describe a session that does nothing; worker prompts must say how to wait, and a warning in a prompt can cause defensive behaviour.
*Relates to:* H-089, H-091.

**A4. The heartbeat was also wrong in the other direction.** In the first run the orchestrator sat idle for more than 35 minutes with eight ready tickets and no workers. The watcher had logged it as "held", so nothing reacted. Separately, its heartbeat file had stopped moving at an earlier date although the session showed real activity after that.
*Why it matters:* an idle orchestrator with ready tickets is a failure that a liveness signal alone does not show.
*Relates to:* H-003, H-089, H-098.

**A5. Silent hangs were found only by a human reading logs.** A subagent retried `docker desktop start` against an unreachable daemon for 33 minutes 31 seconds and spent 184k tokens; by heartbeat it looked like work. Advisor subagents hung for about 40 minutes and never returned; the only sign was missing output. One validator session went idle three times, about 30 minutes apart, and another sat idle for 27 minutes; each needed a forced prompt to go on.
*Why it matters:* test recovery against a session that repeats one failing command, and against one that is simply silent.
*Relates to:* H-091, H-094, D20.

**A6. A dead orchestrator went unnoticed for hours.** The typed Enter was the only escalation the engine had. Nothing stronger fired at any age. The longest stale age before a nudge was 47 minutes in the second run and about 12.4 hours in the first. The first run ended with stale ages of 6457 s, 9924 s and 13578 s, then a full teardown after three dead checks. The run's own report, written by its fifth orchestrator, records thirteen merges, green full-suite gates and no ticket left in progress. The run did not end cleanly. A project script that watched the dead run wrote the same line every three minutes for about five days: 1085 times, never resolved.
*Why it matters:* this is the gap the watch script and the restart path close; a run also needs one clear end state.
*Relates to:* H-098, H-088, H-079, D23; no requirement for repeated alerts.

**A7. A finished session was closed by nobody.** A question-role session answered its question and then stayed open and registered for 28 hours. The watcher logged it as "finished, awaiting close" for hours and had no duty to close it. The orchestrator that started it had moved on. A human closed it. Its terminal title made a human read it as a second orchestrator.
*Why it matters:* close-when-done must hold for every role, not only workers.
*Relates to:* H-081, OPEN-22.

**A8. Closing without force worked.** Four sessions hit the close timeout while a job still ran. Each was left open, as designed, and was later found finished on its own.
*Why it matters:* evidence for keeping the graceful close; force stays for the explicit hard stop only.
*Relates to:* H-081, H-087.

**A9. A pattern kill hit the wrong process.** `pkill -f '<test runner name>'` killed an unrelated worker session. Every worker's prompt text contained that literal string, so the pattern matched sessions, not test suites. The worker was respawned 83 seconds later.
*Why it matters:* the reason processes are stopped by exact process ID only.
*Relates to:* H-103.

**A10. The watcher itself was killed for memory.** The watcher's background collection task was OOM-killed 26 or more times in the second run, with host swap nearly full. It became stable only after the collection moved into the foreground.
*Why it matters:* the component that watches others needs someone who checks it.
*Relates to:* H-098, D32.

## B. Sending text to a session

**B1. Typed text was lost in three ways.** Measured on live sessions:

- A bare Enter did not submit text that already sat on the input line.
- The send command typed its own text and submitted, so it destroyed whatever was pending.
- When a background task woke the session, text on an idle input line was discarded.

Five instructions were lost this way in the second run. At one point a thirteenth stranded `continue` sat on the orchestrator's input line next to a live test run. One recovery attempt (Enter, then a single space) cleared the pending instruction without sending it. The one send that worked went to an empty line of an idle session and was checked three ways: the screen, a busy check, and the last user message in the session transcript.
*Why it matters:* the typed fallback needs an empty line, and delivery needs proof from the transcript.
*Relates to:* H-099, H-101, S8-24.

**B2. The log said "nudged" and nothing had been sent.** Two real operator instructions (push the trunk; carry on with the queue) sat unsent in two sessions' input boxes while the engine log recorded them as delivered. A human found it.
*Why it matters:* a send counts only when the target's transcript records that instruction (S8-24), never on a log line alone.
*Relates to:* H-101, S8-24.

**B3. One lost Enter cost 149 minutes.** A send's Enter never landed on one worker. The worker had in fact finished 70 minutes earlier. Nothing detected the stall, and a human pushed the trunk by hand.
*Why it matters:* a test case for "delivery failed and both paths are exhausted".
*Relates to:* H-101.

**B4. Long text failed without an error.** A typed message of about 1100 characters produced no error and never appeared. A 450-character version of the same message landed. These two sizes are the only measured pair. The source also states a limit of "roughly 200 characters", taken from a separate reference.
*Why it matters:* the typed fallback needs a length test and a size limit.
*Relates to:* H-101.

**B5. A typed command was eaten as a plain message.** A slash command was typed three times into the same session. With an empty input line and no background shell it worked once. With background shells running it failed twice; once it was consumed as an ordinary user message.
*Why it matters:* graceful close also types a command, so test it against a session with background shells.
*Relates to:* H-081, H-101.

## C. Merge, validation and git

**C1. A merge reported success and did nothing.** `git checkout <trunk>` aborted because a tracked file was modified; the flow system rewrote a lock file in every phase and left it dirty. The merge that followed ran on the feature branch against itself and printed `Already up to date`, and the push printed `Everything up-to-date`. Both read like success. It was caught only because the orchestrator checked where the trunk pointed after the push.
*Why it matters:* the exact scenario of the merge confirmation; include a dirty tracked file in the test.
*Relates to:* H-046.

**C2. One change reached the trunk without validation.** The orchestrator went from the worker's ready marker straight to the merge and never started the validator. Every other phase went worker, validator, merge. The orchestrator noticed within about a minute, ran the validator afterwards, and let the verdict decide whether the merge stood. It passed. The source says in one place that the validator ran against the branch, and in another against the merge commit.
*Why it matters:* the validator gate was prompt text, so it could be skipped; the engine must refuse.
*Relates to:* H-055.

**C3. A mandatory verify step was skipped for five phases.** The orchestrator widened a narrow warning about one hanging subagent into "every agent of the flow system". Workers then verified their own work, and each verification file named the builder as verifier. No automated check caught it. Manual review did, and it was reported to the owner.
*Why it matters:* a step that exists only as prose can be reasoned away; self-verification must not count as independent.
*Relates to:* H-055, H-064, H-067.

**C4. The flow system computed a different branch name.** The flow system derived a branch name from the roadmap title that was one word off the worker's real branch. Left alone, it would have cut a fresh branch from the remote trunk and lost the already merged tip. A worker noticed and recorded it.
*Why it matters:* when the flow system owns a step, its naming can disagree with the harness.
*Relates to:* H-067, S8-07.

**C5. Moving a checked-out branch by ref corrupted the tree.** `git update-ref` moved the trunk to the remote tip while the trunk was checked out. HEAD moved; the index and working tree did not. `git status` then showed the newest committed content as a staged deletion, one commit away from reverting it.
*Why it matters:* the engine must not move a branch that is checked out anywhere.
*Relates to:* H-046; local integration branch (design reuse list).

**C6. Merge checks that misfired.** A merge-equivalence check failed falsely because it diffed the wrong pair of trees (554 unrelated files) instead of the paths the merge introduced against the paths the branch changed. Holding a merge locally did not keep it off the remote while another writer existed, so the gate moved to "right after each merge". Validators had to wait until no browser-test process was running before they started the gate suite.
*Why it matters:* test the merged-tree gate with a second writer and with two suites wanting the browser.
*Relates to:* H-046, H-107.

**C7. Test results that looked clean and were not.**

- A test run cut short by memory pressure reported 346 passed, 0 failed. Only arithmetic caught it: 346 passed plus 35 not reached did not equal the declared 382. The missing test was not in the not-reached list either. It followed a host with about 75 MB free.
- A test file that crashed at collection reported `No tests found`, which reads as "zero tests", not as a failure.

*Why it matters:* the case for the non-zero check and for the sum check; the expected total must come from the test collector, because the not-reached list was itself incomplete.
*Relates to:* H-056, H-057, OPEN-VERIFICATION-2.

**C8. A worktree can commit without the project's commit hooks.** In a fresh worktree, a dependency install with scripts disabled never installed the pre-commit hooks. Commits from that worktree passed no gate.
*Why it matters:* a worktree does not inherit the main checkout's safety net; the validator must not assume it.
*Relates to:* H-055; no requirement for the hooks themselves.

## D. Tickets, labels and state files

**D1. A shared state file was wiped every cycle.** The watch loop rebuilt its attention file from empty on every pass. Anything another process appended was gone within one interval. A watcher wrote corrections there all night and found out only by searching for a block it had written four minutes earlier. False "stalled" flags repeated for about seven hours because the corrections never survived.
*Why it matters:* test that a line appended to the run ledger by any writer survives a watch cycle.
*Relates to:* append-only run ledger (design reuse list); no requirement.

**D2. Local ticket numbers collided.** Without a lock, two concurrent adds against a queue of 272 tickets produced two files under one number in five rounds out of five. A twenty-way add produced twenty files under three numbers. Both callers were told they had succeeded. With the lock, 2-, 20- and 50-way adds never shared a number.
*Why it matters:* ready-made test sizes.
*Relates to:* H-017.

**D3. A ticket that quoted template tokens blocked a spawn.** A ticket body quoted the harness's own prompt placeholders inside its fenced text. The spawn guard refused to start the validator. A manual prompt edit worked around it. A validator then flagged the worker for an "alteration" that was that edit.
*Why it matters:* the placeholder guard must ignore text inside the untrusted fence.
*Relates to:* H-018, S8-27.

**D4. Launchers that pointed at the wrong place.** A launcher was labelled for one phase in its session ID, log and prompt, but changed into another phase's worktree. A worker name reused from an earlier wave started a worker in a stale worktree with a stale prompt.
*Why it matters:* the model-based spawn check that caught the first case is dropped, so a deterministic test must cover both.
*Relates to:* S8-27 (run IDs in markers), launcher generation (design reuse list).

**D5. Questions forked into a worktree.** The project's question file and journal existed as separate copies in a worktree. A real question for the owner sat in the worktree copy, unseen, for an hour.
*Why it matters:* the reason questions and state live in the tracker, not in files inside a checkout.
*Relates to:* H-027, H-032.

**D6. A fix existed only in the installed copy.** The ticket-number lock was patched in the installed plugin and never in the source repository. The next sync would have reverted it.
*Why it matters:* the lock must land in the source repository with a test, or the next sync removes it.
*Relates to:* H-017; the two approved hand patches (design reuse list).

**D7. `done` left a second state label.** Marking a previously blocked ticket done kept the `blocked` label, so the ticket held two state labels. Seen twice.
*Why it matters:* the scenario of the single-label rule.
*Relates to:* H-030.

## E. Workers, heavy work and Docker

**E1. Two parallel image builds killed the owner's container.** A validator ran two `docker compose up --build` at once on a Docker VM with 8 GB. The owner's own application container was OOM-killed (exit 137) 31 seconds after the builds started. It stayed down for about 30 minutes. Nothing alerted; it was found later by matching timestamps to `docker inspect` showing `OOMKilled=true`.
*Why it matters:* the reason for one heavy job at a time, and one way to confirm an out-of-memory stop.
*Relates to:* H-106, H-107, D26, OPEN-LIMITS-1.

**E2. The owner's default stack was destroyed.** Someone ran `docker compose down -v` without a compose project name. It landed on the default project, the owner's own, instead of a worker's. It was found afterwards from image and volume timestamps. The actor was never identified. Two minutes earlier a session had refused that exact action as owner-only.
*Why it matters:* a compose command without a project name lands on the default project; plugin guards for Docker are a non-goal, so this belongs in the multi-worker guide.
*Relates to:* D27; no requirement.

**E3. Two workers in parallel: what it took and what collided.** A second worker needed its own git worktree outside the repository folder, its own compose project and its own port block. Two pairs ran this way, started 11 and 13 seconds apart. Neither pair had a port or state collision. Two collisions of another kind happened, both while the second pair ran: a validator's stack could not get a subnet from Docker's shared address pool and was given one by hand, and the two builds of E1 killed the owner's container. The source does not say what used up the address pool.
*Why it matters:* input for the multi-worker recipe. Whether either event counts as a collision between workers is not settled by the source.
*Relates to:* H-105, D27.

## F. Limits, the banner, pause and resume

**F1. A false limit banner started an 85-minute loop.** The watch matched text that looked like a usage-limit banner inside the orchestrator's own wrapped prose. It pressed Escape and typed `continue` about every 60 seconds. Each empty turn left the screen unchanged, so the text matched again. Nothing internal detected it. The human-notification watchdog had already exited and was never restarted. The loop ended when an external signal killed the orchestrator. A second loop of the same kind ran 45 minutes with a resume kick every 66 seconds.
*Why it matters:* banner recognition needs negative fixtures (the banner quoted in prose), and no typed reaction.
*Relates to:* H-113, H-099, H-114.

**F2. Usage was read from the wrong account.** For a time the limit position was measured against a different account from the one that did the work; it read 94% weekly. Later, when the reader was pointed at another account folder mid-run, the weekly figure dropped sharply with no change in usage. A session that had already started kept the account it started with; a routing change reached only the next spawn.
*Why it matters:* a limit reading must carry the account it belongs to.
*Relates to:* H-109.

**F3. The limit was often unreadable.** The weekly reading came back unreadable on many separate days, once for six checks in a row. The usage endpoint returned an authentication error for about 80 minutes, and nobody re-authenticated. Inside a session the limits check returned "unknown" by design, because the session's environment withheld the usage token.
*Why it matters:* "unknown" is a common state, not an edge case; test that work continues and status shows unknown.
*Relates to:* H-111, D28b.

**F4. The pause path regressed three times.** This was in the project's supervisor script, not in the plugin's limits code.

1. The fallback used when the usage read failed was pinned to a past time. An unreadable read resumed a paused run at once.
2. The fix put a slow lookup between the two files that mark a pause. A restart in that window read the stop file as a manual stop and exited instead of resuming.
3. After the two writes were made serial, the stop file was still written even when the marker write failed. That left a stop with no recorded cause.

*Why it matters:* the same three scenarios apply to the engine's own wait-for-reset and STOP handling; a pause must be one atomic record with its cause.
*Relates to:* H-114, D28c, D25b.

**F5. A status-line pattern missed a model name.** A pattern that parsed the session status line did not match a model version with a decimal point. The watch fell back to a broken capture for three sessions and said nothing.
*Why it matters:* the new limits read parses the status line; no model names in engine code, and a parse miss must be reported.
*Relates to:* H-109, D28.

## G. Measured timings and costs

**G1. Session durations, second run (start to close).**

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

Thirteen of nineteen planned phases merged in the first 34 hours. Later phases took four to five times as long as early ones. A summary list elsewhere in the source gives 58 minutes to 3 hours 20 minutes for workers; the table contradicts it.
*Why it matters:* a healthy worker can be busy for more than five hours and silent for 14 minutes; no fixed timeout fits.
*Relates to:* H-091, H-094, D21.

**G2. Machine load and quota.** Two workers plus the owner's stack, each worker with its own app and database container: load peaked at 19.4 on 14 cores during an image build, with a 15-minute average of 5.5. Memory pressure stayed at 48–68% free. Swap grew from 3 GB to 6 GB. On macOS the amount of swap used is not a pressure signal; `memory_pressure -Q` is. Over 34 hours the run used 26% of the account's weekly allowance. The dependency order of the tickets limited throughput, not the quota: only two pairs of phases could ever run together.
*Why it matters:* sizing for the usage history and for the worker cap default.
*Relates to:* H-104, H-108.

**G3. How fast a context window filled.** A watcher session cycling every two minutes went from 9% to 91% in about ten hours. A worker reached 91% in three and a half hours (see A3). The orchestrator reached 64% after 30 hours, with one compaction.
*Why it matters:* long runs will auto-compact, so run state must be in the handoff file, not in the session.
*Relates to:* D24, D14.

## H. What worked

**H1. Asking and independent checks earned their cost.** Eleven questions went to the project's question channel instead of being answered by assumption. Each carried a fallback, and each was later answered. In the best case the session first measured what it could (it removed a check, rebuilt, ran a 27-second comparison across four roles) and asked only what the measurement could not settle. A plan checker sent one plan back for three revision rounds, and rejected another with one blocker and four warnings. A code review found nine issues on one phase, all fixed before merge.
*Why it matters:* evidence for the reused rule "blocked beats guessed", for the cheap first step before asking, and for keeping the plan check, review and validator steps.
*Relates to:* H-032, H-055, H-064, S8-11.

## I. Detectors, probes and gates that failed quietly

**I1. Probes that returned nothing and were believed.**

- A marker detector searched the wrong folder and reported zero markers for several cycles.
- On macOS, `find -newermt "-10 minutes"` is an error. With errors sent to `/dev/null` it returned empty every time, which would have marked every healthy session idle. It was caught by checking against files known to be minutes old.
- A parser read a timeout from the screen. When the value scrolled out of a 40-line capture, it silently used a 900 s default instead of 1800 s.
- Two gates swallowed a failed `docker` call and went on as if it had succeeded. One compared a UTC timestamp as local time, so its six-hour rule never fired.

*Why it matters:* every probe needs a test for "cannot read", distinct from "read and found nothing"; test on macOS tools.
*Relates to:* H-089, H-111; no single requirement.

**I2. Screen matching fired on the wrong text.** Four false positives in one day: a non-ASCII space read as unsent text; a session's own quoted warning text read as an alarm; the shape of a dialog taken as proof that a session was stuck; and a dialog quoted inside a session's report matched by a whole-screen scan.
*Why it matters:* fixture cases for any screen reading, including the input-line check.
*Relates to:* H-099, H-113.

**I3. "OK" with nothing checked.** A comparison check printed `OK, 0 files compared` when run from a subfolder. A sweep returned exit 0 against a real diff. A patch script printed `SYNTAX OK` while its search anchor never matched and nothing was written; that was the third such case in one day. A scanner ignored a bare path argument and read clean over files it never opened. The same scanner called files over 32 MB "unreadable" and skipped them without a word. The comparison check named first existed only as prose; no automation ran it.
*Why it matters:* a check must fail when it checked zero items, and "could not read" must never read as "clean".
*Relates to:* H-056, H-046; same principle as D28b (unknown is never OK).

**I4. Secrets reached a session transcript.** A test tool's trace mode printed two local passwords into a transcript. Nothing scans tool output or transcripts.
*Why it matters:* never commit a real transcript or screen capture as a test fixture without reading it.
*Relates to:* no requirement (scrubbing is a non-goal).

**I5. Detached scripts start with no environment.** Scripts started by `nohup` or by the system scheduler did not inherit the shell environment. Each had to set the tracker CLI's account itself, or the CLI could not reach the repository.
*Why it matters:* the poll script and the watch script run detached; test them from an empty environment.
*Relates to:* H-003, H-096.
