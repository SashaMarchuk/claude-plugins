# Tasks

Order follows design.md, Decisions, Rebuild. Each ticket cites the requirement IDs it covers.

## 0. Before the build (attended)

- [ ] 0.1 Back up the installed 0.6.0 with a diff against the repo, and verify the backup matches
- [ ] 0.2 Open the requirements PR for this change, and verify `openspec validate --all --strict` passes
- [ ] 0.3 Run the read-only connections check and list owner-only actions (D36, OPEN-14)
- [ ] 0.4 Check that a separate config folder keeps its own plugin cache and that two marketplaces cannot share one name

## 1. Build branch (after the owner merges the requirements PR)

- [ ] 1.1 Cut and push `harness/next` from `origin/main`, in a clean clone with harness folders excluded locally
- [ ] 1.2 Configure the frozen 0.6.0 as builder (lanes from `harness/next`, GSD, two workers, never push), and create labels
- [ ] 1.3 Run `/gsd-new-milestone` from this change and open one issue per phase; verify `/harness:status` reads the queue

## 2. Skeleton (attended)

- [ ] 2.1 Remove the 0.6.0 engine files; add the manifest (`harness`, "Harness Orchestrator", pre-release version) and one entry script
- [ ] 2.2 Add the test runner with the `PASS=<n> FAIL=<m>` line and a fake `claude`
- [ ] 2.3 Add the isolation self-test; verify `bash tests/run-all.sh` and `claude plugin validate plugins/harness` pass

## 3. Config and run state (wave 1)

- [ ] 3.1 Port config lookup and safe-file helpers with behaviour tests; `schemaVersion: 2`
- [ ] 3.2 Add the append-only run ledger and run IDs in every marker; verify a 0.6.0 run is refused and left byte-identical

## 4. Ticket queue (wave 1)

- [ ] 4.1 Port both backends and the untrusted fence, with both hand patches and a single state label
- [ ] 4.2 Verify 2, 20 and 50 parallel adds never share an ID and no report edits an older comment

## 5. Past-run mining (wave 1, no code)

- [ ] 5.1 Sonnet agents mine past runs; the agent revalidates findings under D39 and proposes test scenarios by PR to `main`

## 6. Sessions (wave 2)

- [ ] 6.1 Launcher, registry and graceful close against a fake `claude`; identity is process ID plus session ID
- [ ] 6.2 Verify a mismatched launcher cannot be produced and close refuses another run's session

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

## 11. Screen-text handling (attended, outside the builder)

- [ ] 11.1 Limit-banner recognition against saved fixtures, plus trust-dialog and password handling
- [ ] 11.2 Verify a session's own prose quoting a banner does not match
- [ ] 11.3 If no account reaches a limit during the final product check, leave a prepared deferred limit-banner test task; only the owner starts it (H-113, D35, OPEN-LIMITS-3)

## 12. Intake and tickets

- [ ] 12.1 GitHub intake by label with the write-access check, polling script, readiness check and working brief
- [ ] 12.2 Urgent ticket out of turn, and ticket changes through comments
- [ ] 12.3 Fallback triggers for trackers without labels

## 13. Tracker comments

- [ ] 13.1 Comment format with the hidden machine line, questions to humans, and answer attribution
- [ ] 13.2 Unblock command and label cleanup, with careful dedicated tests (R10.3)

## 14. Autonomy and git

- [ ] 14.1 Autonomy profiles checked by the engine at every step boundary and before push, PR, merge and deploy
- [ ] 14.2 Push to the ticket branch, draft PR after verification, merge confirmation by git, close on merge

## 15. Verification

- [ ] 15.1 Verdict gate, test-count rule and Verification block in the PR
- [ ] 15.2 Remarks handling and external review bots; verify-and-prove skill as an optional flow step

## 16. Limits and resources

- [ ] 16.1 Limits per account from status line data, with configurable thresholds and actions
- [ ] 16.2 Enforced worker cap, out-of-memory lowering and the heavy-work slot

## 17. Run lifecycle and recovery

- [ ] 17.1 Soft and hard stops, and the STOP file
- [ ] 17.2 Test force-send of a queued stop message from a script before relying on `hard:message` (D37-LIFECYCLE-4): tmux proven (issue #62); two iTerm2 trials before release
- [ ] 17.3 Standby, end of run, automatic recovery after sleep or a crash
- [ ] 17.4 Outage monitor and dead-orchestrator restart in the watch script

## 18. Notifications

- [ ] 18.1 Channel contract with Telegram, Slack and Gmail presets, priority and fallback
- [ ] 18.2 Answers written back to the tracker with their author

## 19. Codex runtime

- [ ] 19.1 Runtime profiles for Claude Code and Codex; review steps on Codex; start check for logins and skills

## 20. Distribution and setup

- [ ] 20.1 `/harness:config` and `/harness:ai-ready`; `onboard` and `init` are one-release aliases for `/harness:config`, and `/harness:ai-ready` has no alias (D33a)
- [ ] 20.2 Blind naming test for the two skill names (D33; result in D33a)
- [ ] 20.3 Short install guide, "tested with" list, newcomer section and config-folder README

## 21. Evaluation programme

- [ ] 21.1 Isolation self-test of the eval lane; verify the installed 0.6.0 and its data are unchanged (R27.14, R27.15)
- [ ] 21.2 Clean install by the guide in a separate config folder
- [ ] 21.3 About 10 scenarios across flows, trackers and profiles, with an observer terminal on every step's logs (R27.10, R27.12, R27.16)
- [ ] 21.4 Flow matrix: GSD under several profiles, superpowers variants, one third-party skill collection the owner named, `custom-eval` (R16.4)
- [ ] 21.5 Grilling cases: OpenSpec on and off, each with GSD grilling and the grilling skill of that third-party collection, plus a present `openspec/` with the setting off (R30.4, D41)
- [ ] 21.6 Every notification flow, end to end (R28.10)
- [ ] 21.7 Comparison runs across flows, including review steps on Codex (R29.8, D31)
- [ ] 21.8 Fix failures at once without over-engineering, escalate big changes, and re-test shorter, up to 4 cycles (R27.11)
- [ ] 21.9 Verify the main success flow works end to end (R30.5, R27.17)

## 22. Release

- [ ] 22.1 Owner answers OPEN-13 items 5 and 6 (version string, rollback tag)
- [ ] 22.2 Release PR `harness/next` → `main` with version, display name, "Upgrading from 0.6.0" and the migration note; the owner merges it
- [ ] 22.3 Archive with openspec archive harness-stable-beta --yes after the release PR merges
