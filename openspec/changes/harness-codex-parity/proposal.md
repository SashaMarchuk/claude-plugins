# Proposal

## Why

On 2026-11-26 the owner answered the review page of PR #100. He asked for Codex to work at the same level as Claude Code, as worker and as orchestrator of interactive terminal sessions. He asked for terminal control that corrects itself after an update breaks it. He asked for load routing between runtimes, a current list of which model fits which role, routing between subscriptions only across providers, other models inside a runtime, and the plugin and marketplace working in Codex too.

The stable beta (`harness-stable-beta`) keeps interactive Codex sessions out (its Non-goals, D30) and runs Codex non-interactively: review steps, and execution only as an experimental option. This change holds the owner's Codex answers as requirements. It is planned for the release after the beta; the owner decides whether any part moves into the beta. The beta-sized answers of the same review page (external review bots, the check after each terminal action, the confidence log, model roles, the start check, the first setup and its evaluation, the readiness check) are in `harness-stable-beta` as H-145 to H-154.

## What Changes

- **Codex as orchestrator and worker:** Codex runs interactive terminal sessions at the same level as Claude Code, under the same safety rules (H-155, H-156). Execution on Codex stops being experimental once its success path and a comparison run pass (H-075 modified).
- **Test depth:** Claude Code as orchestrator is tested fully; Codex is tested on its main success path for terminal control; a Codex orchestrator launching Claude Code exists but is not tested (H-157).
- **Self-correcting terminal control:** off, ask or automatic learning from failed terminal actions, with corrections recorded by version combination, and a learning pass on command (H-158).
- **Missing skill on one runtime:** set it up there, after a yes, or move those steps to the runtime that has it (H-159, H-078 modified).
- **Load routing:** a preferred split, fixed steps, and a permission given at setup to change the split during a run within those limits (H-160).
- **Current model list:** the role mapping of H-150 is checked against a maintained public model list and the runtimes' own lists; changes need a yes (H-161).
- **Subscription routing:** only across providers by default; within one provider only with a deliberate API billing opt-in, which also lets a Codex orchestrator launch Claude Code (H-162).
- **Other models inside a runtime:** a routing target too, with the provider and model recorded per session (H-163).
- **Codex install:** the harness, and ideally every plugin in the marketplace, installs in Codex; Claude Code users keep updating without a reinstall (H-164).
- New requirement IDs H-155 to H-164 continue the beta's numbering and are never reused.

## Capabilities

### New Capabilities
None. Every requirement extends a capability of `harness-stable-beta`.

### Modified Capabilities
- `harness/sessions-and-liveness`: H-155, H-156, H-158 added.
- `harness/flow-and-configuration`: H-075 and H-078 modified; H-159, H-160, H-161, H-163 added.
- `harness/limits-and-resources`: H-162 added.
- `harness/distribution-and-setup`: H-157, H-164 added.

## Order

This change modifies requirements that `harness-stable-beta` adds. It is archived only after `harness-stable-beta` is archived, so its MODIFIED blocks find their base. On archive, the beta Non-goal "Interactive Codex sessions: not in this beta" and the "experimental" wording of D30 and D37-RUNTIME-2 no longer apply; design.md D53 records this.

## Non-goals

- Claude desktop or web sessions as a runtime mode (the owner: «останнє мене мало цікавить»).
- Testing a Codex orchestrator that launches Claude Code sessions (the owner: «його тестувати не потрібно»).
- Rotating between subscriptions of one provider to get around limits, without the API billing opt-in.
- Assigning model roles automatically from a leaderboard or a public list without the person's yes.
- An npm installer as the first distribution step; the native Codex marketplace comes first (design.md D60).

## Impact

- `plugins/harness/` on the branch that builds the release after the beta: runtime profiles, the orchestrator prompts, the screen data for Codex, the routing and the setup.
- The marketplace root: a Codex marketplace file next to the Claude one, version sync, and a cross-tool test. Shared files change only through a PR to `main`.
