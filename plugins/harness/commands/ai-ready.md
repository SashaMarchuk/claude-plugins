---
description: "Prepare this repository for AI development: review CLAUDE.md, add an AGENTS.md link, SECURITY.md and hooks where they fit. To configure the harness itself (flow, autonomy, settings), use /harness:config."
argument-hint: "[what to focus on, optional]"
---

Apply AI-development best practices to this repository, so AI work here is more reliable (H-129). The list below gives examples; it is open, not the full set. Use AskUserQuestion before every change, at most 4 questions per round, with the recommended option first. Show each change before you write it. If `$ARGUMENTS` names one practice, do only that one.

Rules for this command:
- Never install or configure a flow system, such as GSD. The flow is chosen in `/harness:config` (design D37-DISTRIBUTION-1).
- Write no harness config and no local selection: nothing under `.harness/`. That is the job of `/harness:config` (design D33a).
- The project must not depend on the harness (H-074). Add nothing that needs the harness to build, test, commit or push. A person without the harness must be able to work exactly as before.
- Change only what the person agreed to. Commit nothing unless the person asks.

1. **Look first.** Read the repository layout, the README, `CLAUDE.md` and `AGENTS.md` if present, `SECURITY.md`, the test and lint commands, existing hooks (`.claude/settings.json`, `.git/hooks`, a hooks manager such as husky or pre-commit) and the CI files. Note what is already there; never duplicate it.

2. **CLAUDE.md.** If it exists, review it against AI-development best practices: the build, test and lint commands are named and correct; the rules are short, specific and checkable; nothing in it contradicts the code; no secret, local path or personal detail. Propose the fixes as a short list. If it is missing, offer a short first version from what you read.

3. **AGENTS.md.** If `CLAUDE.md` exists and `AGENTS.md` is missing, offer an `AGENTS.md` symlink to `CLAUDE.md`, so other agents read the same rules.

4. **SECURITY.md.** If it is missing and the repository is shared or public, offer a short one: how to report a vulnerability privately, and which versions get fixes.

5. **Hooks.** Where hooks fit the repository, offer them, for example a check that runs the project's own formatter or fast tests after an edit, or that blocks writing a secret. Each hook needs a time limit. Prefer the project's existing hook tool.

6. **Requirements format (optional).** Ask whether the project wants OpenSpec as its requirements format. Set OpenSpec up only after a yes, and never adopt existing documents into it without asking. A project without OpenSpec is a normal case. Whether the harness uses the requirements is a harness setting: point the person to `/harness:config` (`requirements.format`).

7. **Report.** List what you changed, what you skipped and why, and what the person may still want to do.
