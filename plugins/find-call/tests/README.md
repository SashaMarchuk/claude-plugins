# /find-call tests

Contract regression harness for the `find-call` plugin.

```bash
bash plugins/find-call/tests/run.sh      # this plugin only
bash tests/run-all.sh                    # all plugins (find-call included)
```

The runner is grep-based and verifies the published source still honors the
plugin's contract. It does **not** make live Calendar/Drive/Sembly calls — it
asserts on prose and config invariants, the same way the other plugins'
harnesses do.

## What it checks

- **Files present** — SKILL.md, both reference docs, manifest, command shim.
- **Manifest** — valid JSON, `name == find-call`.
- **Config-driven** — reads `~/.claude/shared/identity.json` (Step 0), uses
  `{user.name}` placeholders, degrades gracefully (no HALT) when the file is
  missing, treats `~/.claude/g-event/config.json` as an optional soft dependency.
- **Read-only contract** — declares read-only; never writes `identity.json`,
  Calendar/Drive/Sembly, or time logs.
- **Universal source model (preference + fallback)** — calendar/docs/transcripts
  are provider-resolved (`auto`/`cli`/`mcp`/`off`); universal auto-detect by
  default; the optional `~/.claude/find-call/config.json` sets a *preferred*
  provider order, and the skill always falls back to a working provider (the
  goal is to get the data) — `off` is the only value that disables a source.
  Tests also guard against the old "hard pin / do not fall back" wording
  regressing back in. `WebFetch` on Google URLs stays banned under every
  provider; `transcripts: off` gives a notes-only path.
- **Tooling constraints** — transcript sub-agents are sonnet-only; transcripts
  are optional (degrade if not connected).
- **Direct output** — Step 7 answers the user's actual question and drops
  irrelevant sections, instead of always emitting a generic templated report.
- **Config / status modes** — `--status` (read-only resolution health check) and
  `--config` (interactive provider wizard) exist with matching command shims;
  `--config` is the single write path, routed through `scripts/config_io.py`.
- **`config_io.py`** — valid Python, guarded atomic write (`flock` + tmp +
  `fsync` + `os.replace`), value validation for all three sources. Functional
  checks run against a throwaway `$HOME` so the real
  `~/.claude/find-call/config.json` is never touched: `--show` on an empty home,
  rejection of bad calendar/docs/transcripts values, a good write of both keys,
  `--show` on a populated home, and wrong-shape-JSON quarantine (no crash).
- **Anti-slop** — cite-every-claim and never-invent rules survive.
- **NO-LEAK gate** *(load-bearing)* — scans the user-facing prose files (skill +
  references + all three command shims) and fails if any personal identifier
  (real name, org email-domain, hardcoded local path, real attendee/project
  codename like `MNB` or an `[AUT]` event tag) survived the generalization from
  the original personal skill. The manifest author field is legitimate
  attribution and is intentionally not scanned.
- **Repo wiring** — registered in `marketplace.json` with the correct source,
  added to `tests/run-all.sh`, and listed in the root `README.md`.
