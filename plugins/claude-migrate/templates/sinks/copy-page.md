> **This is a shipped template.** **Copy it to your run directory before editing** - direct edits to this file will be wiped on `/plugin update`. To copy:
> ```bash
> cp ${CLAUDE_PLUGIN_ROOT}/templates/sinks/copy-page.md .planning/claude-migrate/<run-name>/sink-connector.md
> ```

# Sink connector: copy-page (the reliable floor)
Sink type: A single self-contained `out/index.html` page the human uses to migrate by hand - one copy-button per deliverable, byte-exact, zero tooling, no browser automation.
Authentication: none. This sink writes only to the run dir's `out/` tree; it never touches a live account.

This sink is ALWAYS emitted, in BOTH `auto` and `copy-page` output modes - it is the dependable floor that guarantees the migration can complete by hand even if every automation path fails. The page is assembled once by the `build-copy-page` skill from all `briefs/` + per-project instructions, satisfying the pinned DOM/JS contract in SPEC §5.6 so `node ${CLAUDE_PLUGIN_ROOT}/bin/verify-copy-page.cjs` passes.

Because there is no live destination, several of the seven SINK ops are no-ops or render-only - but the contract is symmetric with the `browser` sink so the pipeline never branches on mode. Each op is dispatched by the universal `sink` skill via `node`/render and returns the same-shaped result the browser sink returns, so the controller's code path is identical.

## prepare
Scaffold the copy-page output: ensure `out/`, `out/payloads/`, and `out/.gitignore` exist; render the page shell from `${CLAUDE_PLUGIN_ROOT}/templates/copy-page.html.template` with `RUN` substituted (the localStorage key is `claudeMig.copied.<RUN>.v1`). There is no browser to connect to and no destination account, so there is NO `dest_account_email_hash` to capture (the identity guard applies only to the live sink).

Return shape:
```json
{ "ready": true, "out_dir": "out", "dest_account_email_hash": null }
```

## dedupe_probe
No-op for the copy page. There is no live destination to search for an already-seeded chat, so a duplicate can never have been created by this sink. Always report "does not exist" so the controller proceeds to render the card.

Input: `{ "brief_opening_normalized": "...", "project_handle": null }`.

Return shape:
```json
{ "exists": false, "dest_chat_url": null }
```

## create_project
Render a project header section on the copy page for each project that has at least one kept assigned chat. The migration-mode Custom Instructions are shown as a copy-able card (the human pastes them into the new project's instructions). No live project is created and no handle is adopted.

Input: `{ "name": "Project Alpha", "instructions_migration": "<text>" }`.

Return shape:
```json
{ "project_handle": "P01__alpha", "adopted": false }
```

`project_handle` is the deterministic `PNN__slug` used to key the section; `adopted` is always `false` (nothing exists to adopt on a static page).

## seed_unit
Render ONE card for the chat: a "Copy brief" button (copies the full first-message body byte-exact), a "Copy name" button (copies just the target title from `briefs/UNNN.name.txt` for the rename step), and a show/hide preview. GROUPED cards render under their project section; STANDALONE/REFERENCE cards render in their role section. The card body is sourced from `out/payloads/UNNN.json` (inlined into the single `<script id="data">` when under the inline threshold, lazy-`fetch`ed otherwise). No message is sent anywhere - the human does the seeding.

Input: `{ "brief": "<body>", "target_name": "<title>", "project_handle": "P01__alpha | null" }`.

Return shape:
```json
{ "status": "rendered", "dest_chat_url": null }
```

## finalize_unit
No-op (rename happens in the human's browser, not on the page). The "Copy name" button on each card already carries everything needed for the human's seed -> await first reply -> rename step. The page's `out/README.md` carries the non-negotiable order verbatim from `${CLAUDE_PLUGIN_ROOT}/references/auto-title-gotcha.md`: seed the brief, WAIT for the first assistant reply, THEN rename (renaming before the reply loses the name to the auto-title).

Input: `{ "dest_chat_url": null, "target_name": "<title>" }`.

Return shape:
```json
{ "status": "noop" }
```

## finalize_run
No live swap to perform. Instead, render a trailing "swap to steady-state instructions" card for EACH project - a copy-able card with the steady-state Custom Instructions (OK protocol removed) and the instruction: "After you finish seeding every chat in this project, open the project instructions and replace them with this steady-state version." This is the copy-page mirror of the browser sink's migration->steady swap; it ensures the human is never left with the OK-protocol line live forever.

Return shape:
```json
{ "projects_finalized_cards": 1 }
```

`out/README.md` also instructs opening the page via `python3 -m http.server` (the async Clipboard API can reject under `file://`).

## rate_limit_check
No-op. A static page submits nothing to a destination account, so there is no rate limit to hit.

Return shape:
```json
{ "rate_limited": false }
```

## Budget constraints
- $0 API and $0 destination message-cap cost - the page is static; all submissions are manual.
- Page size: cards inline their body only when N <= `inline_card_limit` (default 60) AND total payload bytes <= `inline_byte_limit` (default 1500000); above either, bodies lazy-`fetch` per-card from `out/payloads/UNNN.json` so the page stays light.

## Known limitations
- Manual: the human copies each card and pastes into the new account. The page is an aid, not an automator.
- Clipboard under `file://` can reject the async API; the page falls back to a focused-textarea `execCommand("copy")` and marks a card "copied" ONLY on a confirmed-successful copy. Serve via `python3 -m http.server` for the reliable path.
- No identity guard: there is no destination account to compare against the source hash on this sink.
