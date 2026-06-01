# claude-migrate: Node + Playwright runtime preflight

## Purpose
`claude-migrate` ships two Node scripts that run under a local Node runtime, NOT as
shebang+exec-bit binaries (Repo M-4 - there is no `.cjs` precedent in this repo, so
they are always invoked as `node ${CLAUDE_PLUGIN_ROOT}/bin/<x>.cjs ...`):

- `bin/parse-export.cjs` - deterministic `conversations.json` / `projects` /
  `memories` / `users` parser (needs **Node only**).
- `bin/verify-copy-page.cjs` - headless Chromium byte-exact copy-page verification
  (needs **Node + Playwright + a Chromium browser binary**).

Without Node, neither script can run: `parse-export.cjs` powers the `split` step, so a
missing Node runtime blocks the whole pipeline. Without Playwright (and its Chromium
download), `verify-copy-page.cjs` cannot run the GATE 2 byte-exact verification, so the
copy page cannot be certified and the run cannot reach `ready`.

The optional `browser` SINK reuses the SAME Playwright runtime over CDP
(`connectOverCDP('http://127.0.0.1:9222')`), but browser automation is gated and
degradable; the hard floor is `parse-export.cjs` (Node) and `verify-copy-page.cjs`
(Node + Playwright + Chromium).

## When this check runs
- `skills/init/SKILL.md` - first-touch, BEFORE any setup work, so the user installs the
  runtime before investing time in connector choice and `config.yaml`. A missing Node
  runtime here is a HARD halt (parser cannot run). A missing Playwright/Chromium is a
  WARNING at `init` (the user can install it before GATE 2) but a HARD halt at `verify`.
- `skills/verify/SKILL.md` - BEFORE invoking `node bin/verify-copy-page.cjs`. A missing
  Node OR Playwright OR Chromium here is a HARD halt: GATE 2 cannot certify the page.

On any HARD halt: print the matching message below verbatim, set `status=blocked`
(`blocked_reason=node-missing` or `playwright-missing`), and do NOT advance the state
machine. Re-running the skill after the user installs the runtime re-runs this check and,
on success, clears the block.

## Preflight detection

```bash
# Node runtime (required by both .cjs scripts)
command -v node >/dev/null 2>&1 || node_missing=1

# Playwright + a Chromium browser (required by verify-copy-page.cjs and the browser sink)
node -e "require.resolve('playwright')" >/dev/null 2>&1 \
  || node -e "require.resolve('@playwright/test')" >/dev/null 2>&1 \
  || playwright_missing=1
```

If `node` resolves and a `playwright` (or `@playwright/test`) module resolves, continue.
A successful module resolution does not guarantee the Chromium binary is downloaded;
`verify-copy-page.cjs` surfaces a clear "browser not installed - run
`npx playwright install chromium`" error if `chromium.launch()` fails, which `verify`
maps to the Playwright halt below.

## Halt message - Node missing (verbatim)

> `claude-migrate` needs a local **Node.js** runtime to parse the Claude export.
> `bin/parse-export.cjs` is invoked as `node bin/parse-export.cjs ...`.
>
> Install Node 18+ (e.g. from https://nodejs.org or via your package manager), then
> retry your command:
>
> ```
> node --version    # expect v18 or newer
> ```
>
> The run is paused (status=blocked); re-run `/claude-migrate:init <run>` or
> `/claude-migrate:resume <run>` once Node is on your PATH.

## Halt message - Playwright / Chromium missing (verbatim)

> `claude-migrate` needs **Playwright** with a **Chromium** browser to run the
> byte-exact copy-page verification (`node bin/verify-copy-page.cjs`) and the optional
> browser accelerator. Install both, then retry:
>
> ```
> npm i -D playwright
> npx playwright install chromium
> ```
>
> The run is paused (status=blocked). The byte-exact copy page is the reliable floor of
> this migration, so it MUST be verified before the run can reach `ready`. Re-run
> `/claude-migrate:verify <run>` once Playwright + Chromium are installed.

## Requires (README "## Requires" copy)
- `ultra` plugin (same marketplace) - see `references/ultra-dep-preflight.md`.
- **Node.js 18+** - runs `bin/parse-export.cjs` and `bin/verify-copy-page.cjs`.
- **Playwright + Chromium** - `npm i -D playwright && npx playwright install chromium`
  - byte-exact verification (always) and the optional browser sink (over CDP).

## Maintenance note
This file is the single source of truth for the Node + Playwright runtime halt.
Skills that reference it: `skills/init/SKILL.md` (first-touch) and
`skills/verify/SKILL.md` (before `verify-copy-page.cjs`). When editing a halt message,
edit HERE; those SKILL.md files link to this file rather than duplicating text.
