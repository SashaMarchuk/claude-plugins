# /claude-migrate regression tests

Acceptance-criteria coverage map for `/claude-migrate`. Every AC-* ID in SPEC §10 maps to one or more
assertions in `run.sh`, or, for the behavioral IDs, to a recorded manual UAT procedure documented below. This
README is the AC -> test mapping the root master runner (`tests/run-all.sh`) references.

## Run

```
bash plugins/claude-migrate/tests/run.sh
```

Exit 0 = all PASS. Exit 1 = at least one FAIL. The plugin is registered in the root master runner
(`tests/run-all.sh` `PLUGINS=(clickup gevent ultra ultra-analyzer claude-migrate)`); the master harness must
stay green with `claude-migrate` included.

## Why this runner exercises real binaries

`/claude-migrate` ships actual shell binaries (`bin/state.sh`, `bin/claim.sh`, `bin/release.sh`,
`bin/requeue.sh`, `bin/launch-worker.sh`, `bin/launch-seed.sh`, `bin/adapter.sh`, `bin/sink-adapter.sh`,
`bin/browser-probe.sh`) plus two Node scripts (`bin/parse-export.cjs`, `bin/verify-copy-page.cjs`). The runner
exercises them functionally against a `mktemp -d` sandbox: it initializes fresh runs, claims and releases work
on both queues, attempts path traversal and jq injection, parses the synthetic fixture export, and drives the
golden copy page through headless Chromium. SKILL.md / references / template prose contracts are verified by
grep where the assertion is a documented invariant rather than executable code.

The harness follows the repo convention: `set -uo pipefail`; resolve `PLUGIN_DIR` from the script's own
location; one `mktemp -d` SANDBOX with `trap 'rm -rf "$SANDBOX"' EXIT`; `report_pass` / `report_fail` /
`assert_eq` helpers incrementing PASS/FAIL counters; one `PASS  <id>` or `FAIL  <id> -- <msg>` line per
assertion; a summary line; non-zero exit on any failure.

## Automated coverage map (run by `run.sh`)

### State machine / counters

| AC ID | Assertion in run.sh | SPEC ref |
|---|---|---|
| AC-ENUM | `state.sh set <run> .current_step bogus` exits 7; each valid enum value is accepted. | §3.1, §8 |
| AC-GATE | Advancing to a gated step (`split`, `apply`) while the required `gates.*.verdict` is not `PASS` exits 8; flipping the verdict to `PASS` under the lock then permits the advance. | §3.1, §6.6 |
| AC-INV-1 | After init + a batch of `claim.sh units` / `release.sh ... done|failed`, `chats_total == preflight_pending + preflight_in_progress + preflight_done + preflight_failed`. | §3.3 |
| AC-INV-2 | `kept == distill_pending + distill_in_progress + distill_done + distill_failed` holds across claim/release on the distill phase of the units queue. | §3.3 |
| AC-INV-3 | `kept == seeded_units + doc_only_units` after a doc_only overflow is recorded; doc_only units never appear in the seed queue. | §3.3 |
| AC-INV-4 | (browser sink) `seeded_units == seed_pending + seed_in_progress + seed_done + seed_failed`; the seed queue is sized to `seeded_units`, not `kept`. | §3.3 |
| AC-INV-5 | Concurrent `claim`/`release` stress on each queue preserves its sum invariant (per-queue concurrent stress, mirroring ultra-analyzer AC6). | §3.3, §8 |
| AC-PROJ-INV | `projects_total == projects_pending + projects_created` at all times; `projects_created == projects_finalized` is required before `status=passed` is permitted. | §3.3, §6.4 |

### Security

| AC ID | Assertion in run.sh | SPEC ref |
|---|---|---|
| AC-INJ | A jq-injection dot-path (containing `[ ] | , ( ) ; = whitespace`) is rejected by `state.sh`; run-name `../x` is rejected by the `^[A-Za-z0-9_-]+$` allowlist; a symlinked queue dir AND a symlinked item are both refused by `claim.sh`. | §3.2, §8 |
| AC-PII | After a full fixture run, NO email / phone / Bearer / JWT / cookie regex matches anywhere under `<run>/` (including `run.log` and every `*.json`). `users.json` content never appears under `source/` or in any output. | §3.8, §7.5, Edge C-3 |
| AC-REDACT | `release.sh <item> failed "<token-bearing reason>"` writes a `[REDACTED:*]` line to `run.log`, not the token. | §8, Edge C-3 |

### Parser determinism

| AC ID | Assertion in run.sh | SPEC ref |
|---|---|---|
| AC-PARSE | `node bin/parse-export.cjs` on `fixtures/` reproduces every edge byte-for-byte (assistant `.text` canonical, `thinking`/`tool_use`/`tool_result` skipped, attachment `extracted_content` folded, image ref noted, empty turn `[no text]`); `UNNN` is sorted-uuid order and stable across two runs; `est_tokens` is deterministic (chars/4 EN, chars/3 Cyrillic/CJK). | §5.3, §7.3, M1, H2 |
| AC-DEDUP | The duplicate-cluster representative is the lowest `idx` and is stable across two runs; duplicates are surfaced, not auto-dropped. | §7.5, M2 |

### Copy page (the reliable floor)

| AC ID | Assertion in run.sh | SPEC ref |
|---|---|---|
| AC-VERIFY | `node bin/verify-copy-page.cjs` exits 0 on the golden page (all N cards copy byte-exact against `out/payloads/<id>.json`, plus counter / progress / persistence-across-reload / reset / name-button-does-not-mark / search) and exits 1 on the byte-mismatch fixture. | §5.6, §8 |
| AC-ESCAPE | A fixture brief containing `</SCRIPT >`, `</script\n>`, and `<!--` renders without breaking the page and copies byte-exact (escape regex `/<\/(script)/gi`, parsed via `textContent` + `JSON.parse`). | §5.6, §7.5, H-4 |
| AC-COPYFAIL | The `file://` (non-granted clipboard) assertion confirms a copy failure does NOT falsely mark the card copied; the card shows the error state and the brief text is auto-selected. | §5.6, H-5 |

### Determinism of the whole transform

| AC ID | Assertion in run.sh | SPEC ref |
|---|---|---|
| AC-DETERMINISM | Two `init -> build-page` runs over the same fixture export produce identical `briefs/`, `out/payloads/`, and `project/<PNN__slug>/` (modulo timestamps); no iteration-order dependence. | §7.6, C1/C2/H2/M1/M2 |

### Compliance

| AC ID | Assertion in run.sh | SPEC ref |
|---|---|---|
| AC-COMPLY | `marketplace.json` author is name-only and `plugin.json` author carries `url` (repo asymmetry); `plugin.json` has no `$schema`; exactly one skill (`run`) carries `user-invocable: false`; no `--print`-launched skill (`source`, `sink`, `preflight-value`, `distill-brief`, `apply-unit`) carries it; the `resume` dir name, frontmatter `name`, and `commands/resume.md` target are all the string `resume`; internal worker descriptions carry no "Use when ..." phrase. | §2.1, §2.3, §2.4, Repo H-1/H-3/M-2 |

## Behavioral coverage map (manual UAT)

These IDs assert interactive behavior that cannot be exercised headlessly in `run.sh`. Each is verified by the
recorded procedure below against a real session, and the observable result is checked. Record the date and the
observed result when run.

### AC-BLOCK -- the controller never prompts

SPEC: §3.1, §4, UX C-1.

1. `/claude-migrate:init uat-block` and accept the G-INPUT / G-OUTPUT defaults.
2. Let `run` advance through GATE 1 -> `split` -> `preflight`.
3. **Expected:** at `filter-gate`, `run` does NOT call AskUserQuestion. It sets `status=blocked`,
   `blocked_reason=filter-gate`, and prints "run /claude-migrate:confirm uat-block".
4. Inspect `state.json`: `status == "blocked"`, `blocked_reason == "filter-gate"`.

### AC-DEMOTE -- AUTO + no browser demote rules

SPEC: §6.6, UX H-3.

1. With NO reachable pre-authenticated browser, run a migration to `ready` where the user hit Enter on the
   AUTO default (so `decisions ... user_chose_auto == false`).
2. **Expected (Enter-on-default):** the run demotes to the copy-page floor AND says so explicitly, printing the
   macOS CDP launch command and a resume hint. The copy page is still built and verified.
3. Repeat with `user_chose_auto == true` (AUTO actively selected).
4. **Expected (explicit AUTO):** NO silent demote. `status=blocked` (`blocked_reason=browser-lost`), the launch
   command is shown, and the run is resumable. The copy page is still built either way.

### AC-COST -- G-COST fires before distill, both modes

SPEC: §4, §6.6, §7.3, UX H-4.

1. Run with a fixture export whose deterministic `est_tokens` cross a cost threshold (`usd_high >= 10`, or
   `chats_total > 75`, or any chat `est_tokens > 80000`), in BOTH `output.mode == auto` and
   `output.mode == copy-page`.
2. **Expected:** G-COST is presented during the `filter-gate` round, BEFORE the `distill` step, in both modes,
   driven by the deterministic estimate. `> $25` is a hard-stop requiring an explicit Proceed; below `$10`
   proceeds without a prompt. `decisions ... cost_acknowledged` flips to true on Proceed.

### AC-FINALIZE -- finalize failure blocks, does not complete

SPEC: §6.4, §7.1, UX H-5.

1. In a browser-sink run, force a `finalize_run` per-project failure (for example, make one project's steady
   instruction swap fail).
2. **Expected:** `status=blocked` (NOT done), `blocked_reason=finalize`, and the printed message lists the
   un-stripped project(s) plus the steady file path. `projects_created != projects_finalized`, so
   `status=passed` is refused. Re-running `/claude-migrate:resume` retries only the failed swap.

### AC-RESUME -- per-seed resume rules

SPEC: §3.5, §6.5, Edge C-2.

1. Interrupt a browser-sink apply leaving one unit at `seed/UNNN.json status=seeded` (not `renamed`) and
   another at `status=opened`.
2. Run `/claude-migrate:resume`.
3. **Expected (`seeded` unit):** ONLY the rename runs; the brief is NOT re-seeded.
4. **Expected (`opened` unit):** the SINK `dedupe_probe` runs BEFORE any re-seed. If a matching destination chat
   exists it is adopted (`status=seeded`, URL recorded) and not re-submitted; otherwise the unit is re-seeded
   cleanly. `seed/UNNN.json` is the sole resume authority; `apply/UNNN.result.json` is treated as a report only.

### AC-KEPT-ZERO -- zero kept chats is a loud terminal, not a silent success

SPEC: §4, §6.1, §6.6, M-6.

1. Run with a fixture export where every chat ends up `DROP` (empty / starter / tool / near-duplicate).
2. **Expected:** `verify` / `done` emits a prominent "0 chats kept -- nothing to migrate; review the DROP list"
   message. The run never reports a silent empty success.

## What tests do NOT cover

- Live claude.ai browser traffic (real login, seeding, renaming). The browser SINK is exercised only through
  its contract prose and the headless copy-page verifier; real-account automation is manual UAT.
- `/ultra` gate verdicts. The pipeline invokes `/ultra` at the three machine gates; those gates are tested by
  `/ultra`'s own harness, not here.
- Multi-terminal race tests beyond the per-queue concurrent stress in AC-INV-5.
- Real ZIP download from Settings -> Export data (the live-source preferred path); the fixture stands in for an
  already-unzipped export.

These are explicitly out of scope; they are the documented manual-UAT surface above.
