> **This is a shipped template.** **Copy it to your run directory before editing** - direct edits to this file will be wiped on `/plugin update`. To copy:
> ```bash
> cp ${CLAUDE_PLUGIN_ROOT}/templates/sinks/browser.md .planning/claude-migrate/<run-name>/sink-connector.md
> ```

# Sink connector: browser (optional accelerator)
Sink type: A live, pre-authenticated Claude.ai session in the NEW account, driven through a browser MCP (`mcp__playwright-persistent__*` preferred; CDP-over-9222, `browsermcp`, or `browser-use` as fallbacks).
Authentication: session-based. Expect a browser already logged into the NEW account. This connector NEVER automates login - no credentials, no 2FA, no captcha. If the session is not authenticated, STOP and hand off per `${CLAUDE_PLUGIN_ROOT}/references/login-policy.md`.

This is the OPTIONAL accelerator, run only in `output.mode == "browser"` and only after the copy page has already been built and verified (the floor is never skipped). It consumes the SAME `briefs/` the copy page shows. In v0.1.0 apply runs IN the user's interactive session, serially, paced by `seed_delay_ms` (`seed_parallelism` defaults to 1; >1 is reserved future work). All UI-coupled facts are read from `selectors.json` as ARIA name/role/text locators (resilient), NEVER CSS paths; the accessibility snapshot is the primary locator and degradation order on locator failure is: accessibility-snapshot retry -> `browser-use` agentic -> the always-emitted copy page floor.

The non-negotiable per-chat order is `seed -> await first turn -> rename` (`${CLAUDE_PLUGIN_ROOT}/references/auto-title-gotcha.md`): claude.ai auto-titles from the first exchange AFTER the first reply, so renaming before the reply loses the name.

## prepare
Connect to the pre-authenticated session, run the auth probe, and capture the destination identity hash.

1. Navigate to the target URL from `selectors.json`.
2. Probe for an authenticated marker (composer present / account avatar) via `mcp__playwright-persistent__browser_snapshot`. Authed -> set `authed=true`. Not authed -> STOP, `status=blocked`, `blocked_reason=login`, fire G-LOGIN; never script credentials (`references/login-policy.md`).
3. Read the signed-in email from the account surface and capture `dest_account_email_hash` (SHA-256; clear email never stored or logged).

Return shape:
```json
{ "ready": true, "authed": true, "dest_account_email_hash": "<sha256 hex>" }
```

Identity guard (H-1): GATE 3 HARD-STOPS if `dest_account_email_hash` and `source_account_email_hash` both exist and are EQUAL ("source and destination appear to be the SAME account"). A missing hash is a soft warning, not a stop.

## dedupe_probe
Search the destination for a chat whose FIRST user message matches a given normalized brief opening - the resume-safety probe used before re-seeding an `opened` (ambiguous) unit, so a crash mid-apply never duplicates a chat.

1. Within the project scope when `project_handle` is given, otherwise across standalone chats.
2. Snapshot the chat list / open candidates and compare the first human turn's normalized text (lowercase, collapse whitespace, strip punctuation, first 500 chars) to `brief_opening_normalized`.

Input: `{ "brief_opening_normalized": "...", "project_handle": "P01__alpha | null" }`.

Return shape:
```json
{ "exists": true, "dest_chat_url": "<url>" }
```
or `{ "exists": false, "dest_chat_url": null }`. When `exists`, the controller ADOPTS the existing chat (records the URL, marks the unit seeded) and does NOT re-submit.

## create_project
Probe-then-adopt-or-create, so re-runs are idempotent and never produce duplicate projects.

1. FIRST probe the destination for an existing project whose name matches `name` (accessibility snapshot of the projects list). If found, adopt its handle and return `adopted: true` - do NOT create a duplicate.
2. Otherwise create a new project (Projects -> New project -> enter `name`) and open it.
3. Set the project's Custom Instructions to `instructions_migration` (the migration-mode variant, containing the OK protocol) and record `instructions_mode=migration`.

Per-project creation is serialized by `project/<PNN__slug>/.create.lock.d` (a per-project mkdir lock, not one global lock). Only projects with at least one kept assigned chat reach this op.

Input: `{ "name": "Project Alpha", "instructions_migration": "<text>" }`.

Return shape:
```json
{ "project_handle": "P01__alpha", "adopted": false }
```

## seed_unit
Open a new chat and paste the brief as the FIRST message. Verify the project is in migration mode before its FIRST seed (the OK protocol must be live so the first reply is a small, fast `OK` that triggers the auto-title predictably).

1. GROUPED -> open a new chat INSIDE the project (`project_handle`) so it inherits the Custom Instructions. STANDALONE / REFERENCE -> open a top-level new chat (no project).
2. Focus the composer and PASTE the brief body (never type char-by-char - paste avoids IME/typing flakiness on long briefs).
3. Write-ahead: the controller atomically records `seed/UNNN.json status=opened` BEFORE submit; the FIRST action after a successful submit is the atomic write `status=seeded` + `dest_chat_url`.

Input: `{ "brief": "<body>", "target_name": "<title>", "project_handle": "P01__alpha | null" }`.

Return shape:
```json
{ "status": "seeded", "dest_chat_url": "<url>" }
```

## finalize_unit
Await the first assistant turn, then rename - in that order.

1. Wait on STATE ("first assistant turn rendered") via `browser_wait_for`, bounded by `ok_wait_ms` (default 45000). The literal `OK` is a confirmation only, NEVER the blocking condition. On timeout: leave the unit `seeded` + `last_error=ok_timeout` (never `failed`; resume re-polls).
2. Capture `first_reply`. If it is not a bare OK (trim, strip trailing punctuation, case-insensitive, length <= 5) -> set `ok_protocol_miss=true`, increment the counter, but STILL rename.
3. Rename the chat to `target_name` (from `briefs/UNNN.name.txt`): open the chat title options -> Rename -> type the name -> confirm. Rename is idempotent and retryable - a seeded-but-mis-titled chat is fully recoverable by re-running ONLY the rename.

Input: `{ "dest_chat_url": "<url>", "target_name": "<title>" }`.

Return shape:
```json
{ "status": "renamed", "ok_protocol_miss": false }
```

## finalize_run
After the seed queue drains, swap EVERY created project from the migration-mode to the steady-state Custom Instructions (OK protocol removed) and mark it finalized.

1. For each created project: open its instructions, replace with `instructions-steady.md`, save, set `instructions_mode=steady`, and increment `projects_finalized`.
2. On any per-project failure -> `status=blocked` (NOT done), report the un-stripped project list + the steady file path; the run is resumable. Hard rule: never reach `done` with any project still in migration mode (invariant `projects_created == projects_finalized` before `status=passed`).

Return shape:
```json
{ "projects_finalized": 1, "blocked_projects": [] }
```

## rate_limit_check
Detect the destination plan's rate-limit / message-cap state from the cap marker defined in `selectors.json` (M-7). Seeding consumes the NEW account's own message cap (each seeded chat's `OK` reply counts), so this is checked between submissions.

Return shape:
```json
{ "rate_limited": false }
```

When `rate_limited` is true, the controller moves the unit back to `pending` with exponential backoff and NEVER marks it `failed`; a capped unit stays re-claimable.

## Budget constraints
- Browser seeding is $0 in API tokens (UI automation, not model calls) - but it consumes the destination account's message cap; pace with `seed_delay_ms` (default 1500ms) between submissions.
- Serial in v0.1.0 (`seed_parallelism=1`). N > 75 chats -> a long browser run; recommend resumable batches.
- Circuit breaker (H-6): >= `breaker_threshold` (default 3) consecutive `transport`/`auth`-class failures -> stop claiming, `status=blocked` (`blocked_reason=browser-lost`), re-probe, fire G-BROWSER. `content`/`selector` failures do not trip the breaker.

## Known limitations
- Requires a user-authenticated NEW-account session. The connector does NOT log in (`references/login-policy.md`).
- Selectors drift: all UI facts live in `selectors.json` as ARIA name/role/text. A UI change is a config edit; total locator failure degrades to the copy-page floor, not a dead end.
- Auto-title race: rename ONLY after the first reply renders; rename is idempotent/retryable.
- This sink never deletes anything in the destination; it only creates projects/chats and renames.
