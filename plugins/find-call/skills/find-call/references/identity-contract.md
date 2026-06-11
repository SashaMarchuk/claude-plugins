# Identity contract — what `/find-call` reads (read-only)

`/find-call` is a **read-only consumer** of the shared identity file. Unlike `/clickup` and `/gevent`, it **never writes** `~/.claude/shared/identity.json` (or any other config). It therefore does not carry the atomic-write / `flock` / schema-version-migration machinery those plugins use — there is no write path to protect.

## Files read

### 1. `~/.claude/shared/identity.json` (shared — written by `/clickup` and `/gevent`)

Read on every invocation. Fields consumed:

| Field | Use in `/find-call` |
|---|---|
| `user.name` | Substituted for `{user.name}` in sub-agent prompts and output ("the user's commitments"). |
| `user.email` | The organizer — auto-excluded from attendee lists. Its domain is the implicit internal domain. |
| `teammates[].first_name`, `latin_alias`, `full_name`, `email`, `active` | Attendee-name resolver input — when the user names someone by first name, match against these before falling back to event attendee `displayName`/`email`. |
| `trusted_domains[]` | Label attendees internal vs external in output. No security gate here (read-only skill). |

**Schema version:** this reader accepts any `schemaVersion` it can read (`{1, 2}` and forward). Because it never writes, it does not migrate, quarantine, or bump the version — it just reads what's there and ignores fields it doesn't recognize. See `plugins/gevent/skills/gevent/references/config-schema.md` for the authoritative shared-file schema; this plugin follows it as a reader only.

**Missing file:** degrade gracefully. Calendar search still works against `primary`; name resolution falls back to literal matching against event attendees. Surface a one-line banner pointing the user at `/clickup:onboard identity` or `/gevent:onboard identity` (either one writes the shared file). Never HALT.

### 2. `~/.claude/gevent/config.json` (optional — soft dependency on `/gevent`)

Read only if present. `/find-call` does NOT require `/gevent` to be installed.

| Field | Use in `/find-call` |
|---|---|
| `defaults.calendar` | Calendar ID to search instead of `primary`. |
| `always_include[]` (the `notes_bot` entry) | Tells the skill which bot email appends the "Meeting Resources" block, to help locate it. |

If the file is absent: default the calendar to `primary` and treat the notes bot as unknown. Both are optional.

### 3. `~/.claude/find-call/config.json` (optional, plugin-local)

Read on every invocation if present. Holds the `sources` block that sets the *preferred* provider order per source (`auto`/`cli`/`mcp`/`off`) — preference + fallback, not a hard restriction (the skill always falls back to a working provider; `off` is the only value that disables a source). No file → every source is `auto` (universal). Full model + schema + examples: `references/sources.md`.

This is the **only file `/find-call` writes**, and only through the `--config` wizard (via `scripts/config_io.py`, guarded atomic write). You can also edit it by hand. The investigation flow never writes it.

## What `/find-call` never touches

- It never writes `identity.json`, `gevent/config.json`, or `clickup/config.json` — shared/other-plugin state owned by `/clickup` and `/gevent`.
- It never writes Calendar events, Drive docs/folders, or transcript/meeting records.
- It never writes time logs.
- The **only** file it writes is its own plugin-local `~/.claude/find-call/config.json`, and only via the `--config` wizard (guarded atomic write through `scripts/config_io.py`). The plugin-local `references/aliases.md` write path remains disabled (v1.1).
