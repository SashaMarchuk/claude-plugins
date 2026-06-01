# claude-migrate: PII policy + the canonical `[REDACTED:*]` regex set

## Purpose
This file is the SINGLE SOURCE OF TRUTH for what `claude-migrate` may read, what it may
NEVER copy or write, and the exact redaction regex set applied at three points (Edge C-3,
Edge M-2):

1. **Live extraction** (`skills/extract/SKILL.md` + `templates/sources/browser.md`) - the
   mandatory secret-strip pass after every snapshot, before writing any normalized unit.
2. **Logging** (`bin/release.sh`) - every `reason` / `last_error` string is passed through
   this set before it is appended to `run.log` (JSONL) or written into any `*.json`.
3. **The hook** (`hooks/hooks.json`) - the last-resort `PostToolUse`/`Write` tripwire that
   counts matches over the written content and emits a warning notice (never blocks).

In-skill redaction is the PRIMARY defense; the hook is a tripwire, not the gate. The
acceptance test AC-PII asserts that, after a full fixture run, NO match of these patterns
exists anywhere under `<run>/` (including `run.log` and every `*.json`).

## Source-file rules (export mode)

| File | Rule |
|---|---|
| `conversations.json` | Read for unit content. Message text is migrated; see the canonical-text rule in `templates/sources/export-file.md`. |
| `projects/*.json` | Read for `prompt_template` + knowledge docs. Migrated. |
| `memories.json` | **Read ONLY if it exists AND the user opts in at G-MEMORIES** (default = Skip). Both opt-in routes (paste-to-memory / fold-into-project) MUST redact via this set AND size-check AND preview before writing (Edge M-2). Never auto-migrated. |
| `users.json` | **NEVER copied, NEVER written, NEVER logged.** Read in memory ONLY to compute the SHA-256 email hash for `account_check` (`input.source_account_email_hash`). The clear email/account fields never touch disk under `<run>/`. |

## Account hashing (identity, not PII storage)
- `source_account_email_hash` (export) and `dest_account_email_hash` (browser sink) are
  `sha256(lowercased-trimmed-email)` - a one-way fingerprint, never the clear value.
- They exist only to power the GATE 3 identity guard (`dest_hash != source_hash`, see
  `references/login-policy.md`). The clear email is never persisted.

## Isolation
Read ONLY the pointed-at source (`input.export_path` / the live account). Write ONLY to the
fresh `<run>/` directory. NEVER read a prior run's directory. The run-dir `.gitignore`
(written by `init`) excludes `source/`, `seed/`, `apply/`, `out/payloads/`, `*.png`,
`run.log`, `state.json`, and `checkpoints/` so transient PII-bearing artifacts are never
committed.

## Screenshots (Edge C-3)
Per-attempt screenshots are OFF by default (`capture_screenshots: false`). When the user
turns them on, the skill MUST print a banner warning that screenshots may capture
on-screen PII, and the `*.png` files stay under `apply/` (already `.gitignore`d).

## The canonical `[REDACTED:*]` regex set

Each pattern maps to a single replacement token so logs and stripped text remain readable.
Patterns are POSIX-ERE / PCRE-compatible; apply them in the order listed (most-specific
first) so an `Authorization: Bearer <jwt>` header redacts as one token, not three. All
matching is case-insensitive unless noted.

| Token | Class | Pattern (ERE / PCRE) | Notes |
|---|---|---|---|
| `[REDACTED:JWT]` | JSON Web Token | `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | three base64url segments; redact before Bearer so a bearer-wrapped JWT is one token. |
| `[REDACTED:BEARER]` | Bearer token | `[Bb]earer\s+[A-Za-z0-9._~+/=-]{8,}` | OAuth/API bearer credentials. |
| `[REDACTED:AUTH]` | Authorization header | `(?i)\bauthorization\b\s*[:=]\s*\S+` | full header value. |
| `[REDACTED:APIKEY]` | API key | `(?i)\b(?:api[_-]?key|secret|token|access[_-]?token|client[_-]?secret)\b\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{8,}["']?` | generic `key=value` secrets. |
| `[REDACTED:ANTHKEY]` | Anthropic API key | `sk-ant-[A-Za-z0-9_-]{16,}` | provider key prefix. |
| `[REDACTED:COOKIE]` | Cookie / Set-Cookie | `(?i)\b(?:set-)?cookie\b\s*[:=]\s*\S+` | session cookies. |
| `[REDACTED:CSRF]` | CSRF / session token field | `(?i)\b(?:csrf[_-]?token|xsrf[_-]?token|session[_-]?id|sessionid)\b\s*[:=]\s*\S+` | hidden form fields / storage keys. |
| `[REDACTED:EMAIL]` | Email address | `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}` | any clear email. |
| `[REDACTED:PHONE]` | Phone number | `(?<!\d)(?:\+?\d[\d ()-]{7,}\d)(?!\d)` | E.164 / common groupings; the lookarounds avoid eating long digit runs. |

### Browser-only additions (live extraction secret-strip - `templates/sources/browser.md`)
The live secret-strip pass redacts the above PLUS clears these wholesale (they are never
content): `document.cookie`, all `localStorage` / `sessionStorage` entries, any hidden CSRF
input values, and `Authorization` request/response headers. A connector that returns raw
HTML containing un-stripped storage/cookies is NON-CONFORMANT and the controller refuses it.

## Reference implementation note (single source for callers)
`bin/release.sh` and the live-extract pass apply this set as an ordered `sed -E` (or `perl`)
chain over the `reason` / `last_error` / stripped-text string. The hook
(`hooks/hooks.json`) does NOT redact in place (it is `PostToolUse`, the write already
happened); it `grep -c`s the union of these patterns over `.tool_input.content` and emits
`[hook] WARNING: possible PII in <path>` via `printf %q`. Keep the regex set here in sync
with all three callers - when you change a pattern, change it HERE and the callers read it
from this file.
