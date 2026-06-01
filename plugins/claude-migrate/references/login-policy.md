# claude-migrate: login policy (never automate login) + destination identity guard

## Purpose
This file is the SINGLE SOURCE OF TRUTH for two hard, shared rules used verbatim by the
browser SINK (`templates/sinks/browser.md`), `bin/browser-probe.sh`, `skills/apply-unit`,
`skills/confirm` (G-LOGIN / G-BROWSER), and `skills/resume`:

1. **NEVER automate login.** `claude-migrate` connects to a PRE-AUTHENTICATED browser
   session only. It never scripts credentials, 2FA codes, captchas, magic-link clicks, or
   any part of an authentication flow.
2. **Destination must differ from source** (the dest != source identity guard, H-1).

## Rule 1 - NEVER automate login (detect -> block -> ask -> resume)

### Detect
`prepare` (SINK) navigates to the target and probes for an AUTHENTICATED marker via the
accessibility snapshot - the message composer or the account avatar, as named in
`selectors.json` (`auth_marker`). It never reads cookies/tokens to decide auth; the
rendered authed marker is the only signal. `bin/browser-probe.sh` detects the transport
(persistent Playwright MCP profile -> CDP `http://127.0.0.1:9222` -> extension ->
browser-use) and writes the winner to `state.output.browser`.

- Marker present -> set `output.browser.authed = true`, capture
  `dest_account_email_hash`, continue.
- Marker absent -> NOT authed -> go to Block.

### Block
STOP. Set `status=blocked` with `blocked_reason=login`. Do NOT advance the state machine.
Do NOT attempt to fill any login form. The byte-exact copy page is already built and
verified, so the user can always migrate by hand; the browser accelerator simply waits.

### Ask (via `confirm` / `resume`, NOT via `run`)
`run` never calls `AskUserQuestion`; it blocks and names the gate skill. The user-facing
skill prints G-LOGIN with NO silent default:

> Log into the NEW Claude account in the connected browser, then run
> `/claude-migrate:resume <run>`.
>
> I will never enter your password, a 2FA code, or solve a captcha. Once you are logged
> in, I detect the authenticated session and continue automatically.

If the browser endpoint itself is unreachable (port closed), additionally print the macOS
CDP launch command from `bin/browser-probe.sh` so the user can start a debuggable browser.

### Resume
On `/claude-migrate:resume`, re-run `prepare` -> re-probe the authed marker. Authed ->
clear the block, capture `dest_account_email_hash`, continue from the recorded
`current_step`. Still not authed -> stay blocked with the same message (idempotent;
never re-asked as a fresh question, never escalated to scripting).

### Mid-run browser loss (circuit breaker, Edge H-6)
If, mid-`apply`, the breaker fires (`breaker_threshold` consecutive
`error_class in {transport, auth}` failures), `apply` stops claiming, sets
`status=blocked` with `blocked_reason=browser-lost`, re-probes, and fires G-BROWSER - the
same detect -> block -> ask -> resume loop. Auth-class loss is treated exactly like
"never authed": ask the user to re-establish the session, never re-authenticate for them.

### Demote rules at the AUTO boundary (UX H-3 - no silent demote)
- **Hit-Enter-on-default AUTO + no reachable browser** (`user_chose_auto=false`): demote to
  copy-page mode and SAY SO, printing the CDP launch command and a resume hint. The copy
  page is the deliverable; this is success, not failure.
- **Explicitly chose AUTO + no reachable browser** (`user_chose_auto=true`): do NOT demote.
  `status=blocked` (like G-LOGIN), show the launch command, block-and-resume.

The word "silently" appears nowhere in this flow: every demote or block is announced.

## Rule 2 - destination != source identity guard (H-1, GATE 3 invariant)

Both account email hashes are SHA-256 of the lowercased-trimmed email (clear value never
stored - see `references/pii-policy.md`):
- `input.source_account_email_hash` - captured by SOURCE `account_check`.
- `output.browser.dest_account_email_hash` - captured by SINK `prepare` at login.

GATE 3 (pre-apply, browser only) enforces:

| Condition | Outcome |
|---|---|
| Both hashes exist AND are EQUAL | **HARD-STOP.** Print: "Source and destination appear to be the SAME account. Migration into the same account would duplicate every chat. Aborting before seeding." `status=blocked`; refuse `apply`. |
| Both hashes exist AND differ | PASS the identity invariant; continue GATE 3. |
| One or both hashes missing | SOFT WARNING at the filter-gate / pre-apply (cannot verify identity); not a stop. Proceed only with the other GATE 3 invariants satisfied. |

`bin/state.sh`'s in-lock gate consult refuses to advance to `apply` unless GATE 3 is PASS
(exit 8), so a same-account run can never reach seeding.

## Maintenance note
This file is the single source of truth for the login policy and the identity guard.
Skills/templates that reference it: `templates/sinks/browser.md` (`prepare` auth probe),
`bin/browser-probe.sh` (transport detect + CDP launch command), `skills/apply-unit/SKILL.md`
(breaker -> block), `skills/confirm/SKILL.md` (G-LOGIN / G-BROWSER + GATE 3), and
`skills/resume/SKILL.md` (re-probe). When editing a rule or message, edit HERE; those files
link to this file rather than duplicating text.
