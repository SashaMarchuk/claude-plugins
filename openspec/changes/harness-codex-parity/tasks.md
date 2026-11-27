# Tasks

Planned for the release after `harness-stable-beta`. Each item cites its requirement IDs.

## 1. Codex spike (attended, owner approval to start a Codex session)

- [ ] 1.1 Capture Codex screen fixtures on tmux and iTerm2: idle, working, approval prompt, limit notice, after an interrupt; privacy-review them (H-155, H-156; D53)
- [ ] 1.2 Check that a Codex orchestrator can reach the tmux socket and iTerm2 automation under the sandbox and approval settings the runtime profile names (D53)
- [ ] 1.3 Confirm the form in which Codex calls a GSD step, and record it in the Codex runtime profile (H-154, H-159)

## 2. Codex as orchestrator and worker

- [ ] 2.1 Codex runtime profile: interactive launch, resume by ID, transcript and Stop hook as liveness, limits from the transcript (H-155, H-156)
- [ ] 2.2 Orchestrator prompts free of runtime names; one orchestrator procedure for both runtimes (H-155)
- [ ] 2.3 Codex orchestrator launching Claude Code behind the H-162 opt-in; not in the release tests (H-155, H-157, H-162)

## 3. Self-correcting terminal control

- [ ] 3.1 Learning settings off, ask, automatic; the learning command; corrections stored by version key (H-158; D54)
- [ ] 3.2 Tests: a fake update changes the screen; the orchestrator finds the new way; a correction that would weaken H-099 is refused (H-158)

## 4. Routing

- [ ] 4.1 Missing skill on one runtime: offer setup or move the steps (H-159, H-078)
- [ ] 4.2 Preferred split, fixed steps and the setup-time permission; ledger line and notice for each change (H-160; D56)
- [ ] 4.3 Model list check against the public list and the runtimes' own lists, at most once a day, proposed diff, change after a yes (H-161; D57)
- [ ] 4.4 Subscription routing only across providers; API billing opt-in with its hint; billing path in the session record (H-162; D59)
- [ ] 4.5 Non-default models inside a runtime as role and routing targets; provider and model in the session record (H-163; D58)

## 5. Codex install of the plugins

- [ ] 5.1 Install the current marketplace into a throwaway Codex home and record what works (H-164; D60 phase 0)
- [ ] 5.2 Make the skills self-contained and free of Claude-only variables; add the Codex marketplace file and version sync (H-164; D60)
- [ ] 5.3 Cross-tool probe test, opt-in, proven by a mutant (H-164)

## 6. Release checks

- [ ] 6.1 Codex success path on tmux and iTerm2, as orchestrator and as worker; "tested with" list updated (H-157)
- [ ] 6.2 Archive with openspec archive harness-codex-parity --yes after `harness-stable-beta` is archived and the release PR merges
