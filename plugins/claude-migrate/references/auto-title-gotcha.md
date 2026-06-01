# claude-migrate: the auto-title gotcha (seed -> await first turn -> rename)

## Purpose
This file is the SINGLE SOURCE OF TRUTH for the non-negotiable seed ordering law (Edge
C-1). It is shared verbatim by `skills/apply-unit/SKILL.md` (the in-session browser seed
loop) and by `out/README.md` (the manual copy-page instructions, emitted by
`skills/build-copy-page/SKILL.md`).

## The gotcha
claude.ai AUTO-TITLES a new chat from the first exchange, and it does so only AFTER the
first assistant reply renders. If you rename the chat to its intended title BEFORE that
first turn completes, claude.ai's auto-title OVERWRITES your rename. The chat ends up
named by the model's summary of the brief, not by the target name you set.

## The law: seed -> await first turn -> rename
For every chat, in this exact order:

1. **Seed** - paste the brief as the first message (never type char-by-char) and submit.
2. **Await first turn** - wait until the FIRST ASSISTANT TURN has rendered. This is the
   blocking condition, NOT the literal text `OK`.
3. **Rename** - set the chat title to the target name (from `briefs/UNNN.name.txt`). The
   auto-title has already fired, so your rename sticks.

Never rename before the first assistant turn renders. Never re-seed a chat that already
has a first turn - just rename it.

## The await contract (bounded - Edge C-1)
- The await blocks on **"first assistant turn present"** in the rendered transcript,
  bounded by `ok_wait_ms` (default 45000). It waits on STATE, never on a fixed sleep.
- The literal `OK` is a CONFIRMATION, never the blocking condition. When the project uses
  the OK-protocol, the assistant is asked to reply exactly `OK` to the first (brief)
  message; but the rename trigger is "a first turn exists", whatever its text.
- **Non-bare-OK first reply** (after trim, strip trailing punctuation, case-insensitive,
  length > 5) -> set `ok_protocol_miss = true`, increment the counter, and STILL rename.
  A chatty first reply is not an error; the rename must still happen.
- **Await timeout** (`ok_wait_ms` elapsed with no first turn) -> stay `status=seeded`,
  set `last_error = ok_timeout`. NEVER mark `failed`. Resume re-polls the same chat; a
  seeded chat is never silently dropped.

## Write-ahead order in `apply-unit` (Edge C-1 + C-2, crash safety)
`seed/UNNN.json` is the SOLE resume authority (`apply/UNNN.result.json` is a report only).
Writes are atomic (same-dir mktemp + rename(2)). The ordering:

1. Write `seed/UNNN.json` with `status = opened` **BEFORE** clicking submit.
2. The FIRST action after a successful submit = atomic write `status = seeded` +
   `dest_chat_url`.
3. After the first turn renders -> `status = awaited_ok` (record `first_reply`,
   `ok_protocol_miss`).
4. After the rename succeeds -> `status = renamed` -> `done`.

### Resume rules (gotcha-safe)
- `done` -> skip.
- `in-progress` (crashed) -> re-claim.
- `opened` -> **AMBIGUOUS** (we may have submitted before crashing). Run SINK
  `dedupe_probe` BEFORE any re-seed. If a matching destination chat exists, ADOPT it
  (`status = seeded`, record its URL) and do NOT re-submit - this is the duplicate-factory
  fix (C-2).
- `seeded` not `awaited_ok` -> poll for the first turn (bounded by `ok_wait_ms`); on
  timeout stay `seeded` + `last_error = ok_timeout`.
- `awaited_ok` not `renamed` -> **just rename** (never re-seed).
- `rate_limited` -> `status = pending`, re-claimable, never `failed` (M-7).
- Rename is idempotent and retryable.

## Copy-page (manual) corollary (`out/README.md`)
The same law applies when migrating by hand: paste the brief, wait for the assistant's
first reply, THEN rename the chat to the target title. Renaming before the first reply
lets claude.ai's auto-title overwrite your name. The copy page surfaces each target name
via a "Copy name" button precisely so you can rename AFTER the first turn.

## Project onboarding tie-in (OK-protocol lifecycle - H-5)
The OK-protocol lives in the PROJECT custom instructions (a separate trust boundary from
the pasted brief, which is DATA). A project is created with the `migration` instruction
variant (asks for `OK` on the first message of each chat); after every chat in that
project is seeded and renamed, `finalize_run` swaps the project to the `steady` variant
(the OK line removed). Never reach `done` with a project still in `migration` mode.

## Maintenance note
This file is the single source of truth for the seed-ordering law and the await contract.
Files that reference it: `skills/apply-unit/SKILL.md` (the in-session seed loop) and
`out/README.md` (emitted by `skills/build-copy-page/SKILL.md`). When editing the law or the
await bound, edit HERE; those files link to this file rather than duplicating text.
