# Tasks

Order follows design.md, Decisions, Rebuild. Each ticket cites the requirement IDs it covers.

## 0. Before the build (attended)

- [ ] 0.1 Back up the installed 0.6.0 with a diff against the repo, and verify the backup matches
- [ ] 0.2 Open the requirements PR for this change, and verify `openspec validate --all --strict` passes
- [ ] 0.3 Run the read-only connections check and list owner-only actions (D36, OPEN-14)
- [ ] 0.4 Check that a separate config folder keeps its own plugin cache and that two marketplaces cannot share one name
- [x] 0.5 Build-time ground rules: the build session merges wave PRs into `harness/next` after an independent validator pass, a green `bash tests/run-all.sh` and a clean external review, and merges into `main` stay the owner's; the redacted field notes are on `harness/next`; `main` is protected (pull request only, admins included); a private sandbox repository exists for GitHub intake tests
- [ ] 0.6 Owner item, with no agent decision: the per-project worker count and safety rules 3 to 6 stay with the owner or the project

## 1. Build branch (after the owner merges the requirements PR)

- [ ] 1.1 Cut and push `harness/next` from `origin/main`, in a clean clone with harness folders excluded locally
- [ ] 1.2 Configure the frozen 0.6.0 as builder (lanes from `harness/next`, GSD, two workers, never push), and create labels
- [ ] 1.3 Run `/gsd-new-milestone` from this change and open one issue per phase; verify `/harness:status` reads the queue
- [ ] 1.4 Hold one wake assertion for the attended build session for as long as it lives, not only during builder runs (D42j)

## 2. Skeleton (attended)

- [ ] 2.1 Remove the 0.6.0 engine files; add the manifest (`harness`, "Harness Orchestrator", pre-release version) and one entry script
- [ ] 2.2 Add the test runner with the `PASS=<n> FAIL=<m>` line and a fake `claude`
- [ ] 2.3 Add the isolation self-test; verify `bash tests/run-all.sh` and `claude plugin validate plugins/harness` pass

## 3. Config and run state (wave 1)

- [ ] 3.1 Port config lookup and safe-file helpers with behaviour tests; `schemaVersion: 2`
- [ ] 3.2 Add the append-only run ledger and run IDs in every marker; verify a 0.6.0 run is refused and left byte-identical
- [ ] 3.3 Shipped default config (GSD flow, OpenSpec), the confirmed default in the user config, the one confirmation in the configuration skill or at the first start, and the stop of an unattended start with no confirmation (H-001, H-068, H-072, H-076; D37-FLOW-4, D37-FLOW-7)

## 4. Ticket queue (wave 1)

- [ ] 4.1 Port both backends and the untrusted fence, with both hand patches and a single state label
- [ ] 4.2 Verify 2, 20 and 50 parallel adds never share an ID and no report edits an older comment

## 5. Past-run mining (wave 1, no code)

- [ ] 5.1 Sonnet agents mine past runs; the agent revalidates findings under D39 and proposes test scenarios by PR to `main`

## 6. Sessions (wave 2)

- [ ] 6.1 Launcher, registry and graceful close against a fake `claude`; identity is process ID plus session ID
- [ ] 6.2 Verify a mismatched launcher cannot be produced and close refuses another run's session
- [ ] 6.3 Terminal adapter: a time limit on every call to the terminal app, sessions in a session host, a run that starts without the app, no quit and no close under a busy session, and a check that a stopped process is gone (H-132, H-133, H-134, H-135, H-103; D42a to D42d; issue #40, follow-ups in issue #89)
- [ ] 6.4 Clean launch environment with the check after launch; the registry record with account label, folder and status; the account kept at every resume (H-136, H-139, H-090; D42e, D42h, D42k; issue #40, follow-ups in issue #89)
- [ ] 6.5 Verify against a stub terminal app that sleeps 60 seconds: "not answering" within 6 seconds, the run starts in the session host within 15 seconds, and a busy worker keeps its process ID through a force-quit of the app

## 7. Flow profiles (wave 2)

- [ ] 7.1 Flow profile contract and thin role prompts; ship `gsd` and `basic`; no vendor name in engine code
- [ ] 7.2 Verify both profiles render with no leftover placeholder

## 8. Minimal run loop (wave 3)

- [ ] 8.1 Run loop as engine verbs; merge requires the verdict file, a clean tree and tip checks before and after
- [ ] 8.2 Verify a merge without a verdict fails and a no-op merge is reported as a failure

## 9. First end-to-end slice (attended)

- [ ] 9.1 One ticket to a verified merge in a throwaway repo with `--plugin-dir`; record the proof

## 10. Liveness (wave 4)

- [ ] 10.1 Liveness from hooks, transcript activity and process ID, with no typing
- [ ] 10.2 Verify a long silent job reads as working and a dead process as dead
- [ ] 10.3 Hook time bounds, and the start check that names other hooks with no time limit (H-089; D42l; issue #46)

## 11. Screen-text handling (attended, outside the builder)

- [ ] 11.1 Limit-banner recognition against saved fixtures, plus trust-dialog and password handling
- [ ] 11.2 Verify a session's own prose quoting a banner does not match
- [ ] 11.3 If no account reaches a limit during the final product check, leave a prepared deferred limit-banner test task; the build session starts it itself when the build account comes close to a real limit (H-113, D35)

## 12. Intake and tickets

- [ ] 12.1 GitHub intake by label with the write-access check, polling script, readiness check and working brief
- [ ] 12.2 Urgent ticket out of turn, and ticket changes through comments
- [ ] 12.3 Fallback triggers for trackers without labels

## 13. Tracker comments

- [ ] 13.1 Comment format with the hidden machine line, questions to humans, and answer attribution; every session reads the ticket's current comments and labels before it starts work (H-144)
- [ ] 13.2 Unblock command and label cleanup, with careful dedicated tests (R10.3)

## 14. Autonomy and git

- [ ] 14.1 Autonomy profiles checked by the engine at every step boundary and before push, PR, merge and deploy
- [ ] 14.2 Push to the ticket branch, draft PR after verification, merge confirmation by git, close on merge

## 15. Verification

- [ ] 15.1 Verdict gate, test-count rule and Verification block in the PR: verdict in the opening lines, each check named with its result, unfinished checks and exceptions stated, and the same results in the ticket comment (H-053, H-054)
- [ ] 15.2 Remarks handling and external review bots; verify-and-prove skill as an optional flow step

## 16. Limits and resources

- [ ] 16.1 Limits per account from status line data, in every window present, with optional per-window thresholds and actions; setup offers 90% for every window (H-109, H-110, H-112; D28, D28a, D29)
- [ ] 16.2 Enforced worker cap, out-of-memory lowering and the heavy-work slot
- [ ] 16.3 Record the terminal app's CPU use and the count of listing lines for its own API socket in the usage history, with one notice at the threshold (H-108; D42m; issue #66)

## 17. Run lifecycle and recovery

- [ ] 17.1 Soft and hard stops, and the STOP file
- [ ] 17.2 Test force-send of a queued stop message from a script before relying on `hard:message` (D37-LIFECYCLE-4): tmux proven (issue #62); two iTerm2 trials before release
- [ ] 17.3 Standby, end of run, automatic recovery after sleep or a crash
- [ ] 17.4 Outage monitor and dead-orchestrator restart in the watch script
- [ ] 17.5 Typed text: the byte limit, longer text through a file, the check after a launch line, and the conditions for the typed fallback (H-137, H-099; D42f, D42g; issue #64)
- [ ] 17.6 Reopen from the registry after the terminal app was quit or restarted, and the continue instruction for a live session that stopped on an error after sleep (H-088; D42h, D42i; issue #69, message path in issue #70)
- [ ] 17.7 One wake assertion for the whole run, bound to the watch process, and one for an attended controlling session (H-138; D42j; issue #70)

## 18. Notifications

- [ ] 18.1 Channel contract with Telegram, Slack and Gmail presets, priority and fallback
- [ ] 18.2 Answers written back to the tracker with their author

## 19. Codex runtime

- [ ] 19.1 Runtime profiles for Claude Code and Codex; review steps on Codex; start check for logins and skills

## 20. Distribution and setup

- [ ] 20.1 `/harness:config` and `/harness:ai-ready`; `onboard` and `init` are one-release aliases for `/harness:config`, and `/harness:ai-ready` has no alias (D33a)
- [ ] 20.2 Blind naming test for the two skill names (D33; result in D33a)
- [ ] 20.3 Short install guide, "tested with" list, newcomer section and config-folder README
- [ ] 20.4 `/harness:feedback`: an issue without labels in the plugin's own repository, with technical context and no private data, shown in full and sent only after a yes; verify a no sends nothing (H-140; D43)
- [ ] 20.5 Release checklist file in the plugin repository: automated tests, real terminals and the main success flow (H-141, H-142, H-143)

## 20a. Owner review-page answers (2026-11-26)

- [ ] 20a.1 Detect the repository's automatic reviewer from recent pull requests; wait with a first-signal limit and a total limit; a short fixed wait when there is none; offer to list a detected bot (H-145, H-146, H-147; D44, D45)
- [ ] 20a.2 Check after each terminal action: exact check, second sample, cheap checker role; an unclear answer fails; a model answer never allows typing (H-148; D46)
- [ ] 20a.3 Confidence log by terminal, runtime and operating system version, and the light, medium and deep check levels (H-149; D47)
- [ ] 20a.4 `models.json` with the four roles for each runtime; a step, check or chain names a role (H-150; D48)
- [ ] 20a.5 Offer to run printed install steps after a yes in an attended start; never in an unattended one; project install steps never offered (H-073; D49)
- [ ] 20a.6 Machine fingerprint, its digest in the local selection, block, confirm and note classes, and `/harness:config --recheck` (H-151; D50)
- [ ] 20a.7 Scan-first setup with at most five questions (H-152; D51)
- [ ] 20a.8 Readiness check: the read-only `harness doctor` command and the skill; blind naming test for its name (H-154; D52)
- [ ] 20a.9 Setup evaluation: machine-state fixtures, pass criteria, one mutant per criterion, three runs per state (H-153; D51)

## 21. Evaluation programme

- [ ] 21.1 Isolation self-test of the eval lane; verify the installed 0.6.0 and its data are unchanged (R27.14, R27.15)
- [ ] 21.2 Clean install by the guide in a separate config folder
- [ ] 21.3 About 10 scenarios across flows, trackers and profiles, with an observer terminal on every step's logs (R27.10, R27.12, R27.16)
- [ ] 21.4 Flow matrix: GSD under several profiles, superpowers variants, one third-party skill collection the owner named, `custom-eval` (R16.4)
- [ ] 21.5 Grilling cases: OpenSpec on and off, each with GSD grilling and the grilling skill of that third-party collection, plus a present `openspec/` with the setting off (R30.4, D41)
- [ ] 21.6 Every notification flow, end to end (R28.10)
- [ ] 21.7 Comparison runs across flows, including review steps on Codex (R29.8, D31)
- [ ] 21.8 Fix failures at once without over-engineering, escalate big changes, and re-test shorter, up to 4 cycles (R27.11)
- [ ] 21.9 Verify the main success flow works end to end, as the release checklist states it (H-143; R30.5, R27.17)
- [ ] 21.10 Real-terminal acceptance before release: run the iTerm2 backend once on the real app, from launch to close, together with the two trials of 17.2, and log the result; until then the backend counts as tested against fakes only (H-142; D42n; issue #78)
- [ ] 21.11 Run the release checklist in full and record the results for the release PR (H-141)
- [ ] 21.12 Run the setup evaluation and record its result for the release PR (H-153)

## 22. Release

- [ ] 22.1 Push the rollback tag `harness--v0.6.0` on the 0.6.0 commit before the release PR; there is no 0.6.1
- [ ] 22.2 Release PR `harness/next` → `main` with version `1.0.0-beta.1`, display name, "Upgrading from 0.6.0" and the migration note; the owner merges it
- [ ] 22.3 Archive with openspec archive harness-stable-beta --yes after the release PR merges
