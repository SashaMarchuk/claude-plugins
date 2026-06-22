# /clickup changelog

## 1.5.0 — 2026-06-22

### Added — configurable connection layer (MCP / clickup-cli / REST)

`/clickup` no longer hardcodes the ClickUp MCP. Every ClickUp side-effect now goes
through a named **capability operation** (`op.probe`, `op.create_task`,
`op.find_tasks`, …) whose per-transport realization lives in ONE new reference
file, `skills/clickup/references/connection.md` — the only file in the plugin that
names a transport primitive. Which transport runs is whatever your config says.

- **One source-of-truth config.** A new additive `connection` block inside the
  existing `~/.claude/clickup/config.json` (not a new file, not `identity.json`):
  chosen `primary` transport, `fallback_order`, `auto_borrow`, probe cache, and a
  REST `rest_token_ref` **pointer** (`env:<NAME>` or `cli-config`) — never a token
  value. No `schemaVersion` bump (additive, like `lists_archive[]` in 1.4.0).
- **First use investigates → asks → remembers (never silent).** New
  `/clickup:connect` (and preflight Step 2.5) probes all three transports
  read-only, shows what's available, and asks via `AskUserQuestion` which to use
  first (plus an optional fallback order). The choice is written to config. A
  transport is **never** picked silently — even when only one is available, the
  choice is recorded as yours.
- **Capability-aware degradation.** When the active transport can't satisfy a
  field (e.g. `clickup-cli` cannot set `task_type` or multiple assignees on
  create), the resolver transparently borrows a more-capable available transport
  for that one operation with a visible banner (and a `Degrades:` row in the
  interactive preview) — it never silently drops a field. `--auto` never borrows
  across transports silently: it refuses unless you opt in via
  `connection.auto_borrow`.
- **Cross-transport-safe idempotency.** `op.find_by_marker` is a first-class
  operation; a create error is treated as "outcome unknown" and the marker /
  draft-recorded task id is searched before any retry or fallback create, so a
  fallback can never double-create.
- **Status + secrets.** `/clickup:status` gains a Connection block (live probe per
  transport, where it resolves to, REST-token presence — never the value or the
  env-var name). `/clickup:connect show` renders just that block. Token handling:
  pointer-not-value, curl header via stdin (never argv), `clickup-cli` args
  single-quoted, REST URLs percent-encoded.
- **Tests:** `tests/run.sh` re-points F7 + WSR-5 and adds CONN-1..CONN-14 locking
  in the de-hardcode (no hardcoded MCP/CLI/REST transport literal outside
  `connection.md`), the capability contract, the never-silent connect flow, the
  secret invariants, and the no-schema-bump guarantee.

### Migration

**Registry-visible change** (the marketplace description now mentions the
connection layer), but **no reinstall and zero data loss.** Update with:

```
/plugin update clickup@sashamarchuk-plugins
```

Your `~/.claude/clickup/config.json` (workspace, lists, aliases, defaults) and the
shared `~/.claude/shared/identity.json` (62-teammate roster) are **never touched**
by the update — the new `connection` block is added on first use.

**One-time setup on first use, by design.** Because nothing about the transport is
hardcoded anymore, your existing config has no `connection` block yet, so the
plugin treats the connection as "not configured" until you choose a transport once:

- **Interactive** (`/clickup:create`, `/clickup:connect`, etc.): your first run
  opens a one-question connect prompt with your previously-used transport
  (**MCP**) pre-selected — a one-tap confirm. Existing MCP behaviour is byte-identical
  afterward.
- **Scripted `--auto`**: the first `--auto` invocation **halts** with
  `connection not configured — run /clickup:connect first` (it never silently
  picks a transport). Run `/clickup:connect` once interactively after updating,
  then your `--auto` automation resumes unchanged.

This is the only post-update friction, and it happens exactly once.
