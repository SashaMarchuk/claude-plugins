# Config schemas

## Shared-contract constants

```python
# SHARED between /gevent and /clickup. Keep in sync with the clickup helper.
# Cross-plugin contract: both plugins MUST define these identically.

SCHEMA_VERSION_DEPRECATION_DAYS = 90
# After this many days past `schemaVersion_bumped_at`, readers warn on
# N-1 payloads and prompt a migration. Before the window expires, N-1
# is silently accepted (zero-touch migration-on-next-mutation).
#
# Back-compat window for the current bump (v1 → v2):
#   start: 2026-04-24  (schemaVersion_bumped_at)
#   end:   2026-07-23  (start + 90 days)
# Writers ALWAYS emit schemaVersion: 2 during and after the window.
# Readers accept {1, 2} during the window; {2} only after the window.

CURRENT_SCHEMA_VERSION = 2
PREVIOUS_SCHEMA_VERSION = 1  # supported for SCHEMA_VERSION_DEPRECATION_DAYS
```

The gevent skill reads **two** JSON files on every invocation:

1. `~/.claude/shared/identity.json` — user profile + teammate roster, shared with `/clickup`.
2. `~/.claude/gevent/config.json` — gevent-specific calendar defaults + always-include attendees.

## Non-negotiable file rules

These apply to BOTH JSON files, whenever the skill writes them:

1. **Atomic write** — write to `<file>.tmp` in the same dir, `fsync`, then `os.replace(tmp, file)`. Never edit in place.
2. **`fcntl.flock`** — take an exclusive lock on a sibling sentinel file (`<file>.lock` — NO leading dot on the sibling; e.g. `identity.json` → `identity.json.lock`). For the SHARED `identity.json` file the canonical cross-plugin lock path is **`~/.claude/shared/identity.json.lock`** (matches `/clickup`'s helper exactly — deviation breaks mutual exclusion). Hold the lock for the entire read-modify-write. The kernel releases the lock when the process dies, so stale locks are impossible.
3. **Preserve unknown keys** — when rewriting, round-trip any top-level or nested keys the skill does not recognize. `/clickup` may have added fields to a teammate record that this version of `/gevent` does not know about; they must survive a rewrite.
4. **`schemaVersion: 2`** — integer at the top of every file. Writers ALWAYS emit the current version (`CURRENT_SCHEMA_VERSION = 2`). Readers accept both v1 and v2 during the 90-day back-compat window (2026-04-24 → 2026-07-23 — see `SCHEMA_VERSION_DEPRECATION_DAYS`). On read: if `schemaVersion == 1`, fill in v2 defaults silently (migration-on-next-mutation — no eager write). On write: upgrade in place to v2 atomically (single `atomic_update` pass). Quarantine if `"schemaVersion" not in data` OR `not isinstance(data["schemaVersion"], int)`. If the reader sees a HIGHER version it does not understand, refuse to write (read-only fallback) rather than downgrade.
4a. **`schemaVersion_bumped_at`** — ISO8601 timestamp next to `schemaVersion`. Set once by the writer that performs the N-1 → N upgrade; never overwritten on later writes at the same N.
4b. **`schemaVersionHistory[]`** — append-only log of version transitions: `[{from: 1, to: 2, at: "<ISO>"}, …]`. Added by the writer on every version bump. Preserved by both plugins on round-trip (unknown-keys rule applies).
5. **On corrupt JSON** — move the file to `<file>.corrupt-<epoch>` and start fresh from skeleton, with a banner to the user.

### Reference write helper (Python, stdlib only)

**Platform support**: tested on macOS and Linux. Windows is not supported — `fcntl` is POSIX-only. A Windows user would need a `msvcrt.locking` fallback.

```python
import fcntl, json, os, tempfile, time

# Keep identical in /gevent and /clickup — this is the cross-plugin contract.
CURRENT_SCHEMA_VERSION = 2
PREVIOUS_SCHEMA_VERSION = 1
SCHEMA_VERSION_DEPRECATION_DAYS = 90  # back-compat window for N-1 readers

class SchemaVersionTooNew(Exception):
    """Raised when on-disk file declares schemaVersion > what this helper understands."""

def atomic_update(path, mutate):
    path = os.path.expanduser(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lock_path = path + ".lock"
    dir_ = os.path.dirname(path)
    with open(lock_path, "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                data = json.load(f)
        except FileNotFoundError:
            data = {}
        except json.JSONDecodeError:
            os.replace(path, path + f".corrupt-{int(time.time())}")
            data = {}
        # Quarantine gate: the schemaVersion field MUST exist and MUST be an int.
        # Anything else — string ("999"), float (1.0), null, missing key, list,
        # dict — is corruption or a forged payload. Quarantine to
        # `<file>.corrupt-<epoch>` and refuse write. This closes the silent-
        # downgrade vector where a non-int schemaVersion fell through the
        # isinstance() guard and got rewritten as CURRENT_SCHEMA_VERSION, losing
        # newer-format data.
        if data and ("schemaVersion" not in data or not isinstance(data.get("schemaVersion"), int)):
            os.replace(path, path + f".corrupt-{int(time.time())}")
            raise SchemaVersionTooNew(
                f"{path} has missing or non-integer schemaVersion "
                f"(got {type(data.get('schemaVersion')).__name__}={data.get('schemaVersion')!r}); "
                "quarantined. Refusing write."
            )
        # Refuse to write if on-disk schema is newer than this code understands.
        # Prevents a newer writer from being silently downgraded by older reader.
        # Back-compat window (90 days per SCHEMA_VERSION_DEPRECATION_DAYS):
        # readers accept schemaVersion in {CURRENT_SCHEMA_VERSION - 1, CURRENT_SCHEMA_VERSION}.
        on_disk_version = data.get("schemaVersion", CURRENT_SCHEMA_VERSION)
        if on_disk_version > CURRENT_SCHEMA_VERSION:
            raise SchemaVersionTooNew(
                f"{path} has schemaVersion={on_disk_version}, this helper supports {CURRENT_SCHEMA_VERSION}. "
                "Update the plugin and retry."
            )
        mutate(data)  # caller supplies closure
        with tempfile.NamedTemporaryFile("w", dir=dir_, delete=False) as tmp:
            json.dump(data, tmp, indent=2, ensure_ascii=False, sort_keys=False)
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = tmp.name
        os.replace(tmp_path, path)
        # Parent-dir fsync so the rename is durable across crashes (POSIX rename
        # metadata lives in the directory entry — without this, power loss between
        # replace and dir journal flush can lose the file).
        try:
            dfd = os.open(dir_, os.O_RDONLY)
            os.fsync(dfd)
            os.close(dfd)
        except OSError:
            pass  # non-POSIX filesystems may not support dir fsync
```

Every write path in this skill must go through `atomic_update` (or a Bash equivalent with `flock(1)` + `mv`).

**Contract for caller-supplied `mutate` closures**: perform all mutation logic BEFORE any file operation, so if the closure raises, we abort before writing the tempfile. The helper catches nothing — exceptions propagate up with the lock held through the `with` block, then released on context exit.

---

## `~/.claude/shared/identity.json` (SHARED — /clickup + /gevent)

Written the first time either skill's onboarding runs. Read on every invocation of either skill.

```json
{
  "schemaVersion": 2,
  "schemaVersion_bumped_at": "2026-04-24T00:00:00Z",
  "schemaVersionHistory": [
    {"from": 1, "to": 2, "at": "2026-04-24T00:00:00Z"}
  ],
  "onboarding_complete": true,
  "updated_at": "2026-04-22T12:15:00Z",
  "user": {
    "name": "Sashko Marchuk",
    "email": "sasha.marchuk@speedandfunction.com",
    "external_ids": {
      "clickup": "100682233"
    }
  },
  "trusted_domains": ["speedandfunction.com"],
  "teammates": [
    {
      "first_name": "Misha",
      "latin_alias": "Misha",
      "full_name": "Misha Skripkovsky",
      "email": "misha.skripkovsky@speedandfunction.com",
      "external_ids": {
        "clickup": "106686024"
      },
      "active": true,
      "sources": ["clickup-workspace", "clickup-tasks", "google-calendar"],
      "last_validated_at": "2026-04-22T12:15:00Z"
    }
  ]
}
```

See `plugins/clickup/skills/clickup/references/config-schema.md` for the full identity schema documentation — this plugin reads the same file and follows the same field rules.

### Back-compat reader (v1 → v2, zero-touch)

Readers in BOTH plugins MUST accept `schemaVersion ∈ {1, 2}` for the
90-day window `2026-04-24 → 2026-07-23`. A v1 file is upgraded IN MEMORY
on read — no eager disk write — so a stale plugin that can still only
read v1 never trips over a v2 file it didn't create. Writers ALWAYS
write `schemaVersion: 2` and append `{from: <old>, to: 2, at: <ISO>}` to
`schemaVersionHistory` on the first v1 → v2 transition.

On-read fill-in defaults for v1 files:
- `teammates[].active` — default `false` when missing (NEVER `true`;
  missing means "never validated", which MUST be treated as inactive
  until `/clickup` workspace-sync verifies the record).
- `trusted_domains[]` — default `[]` when missing. `/gevent` uses this
  to gate silent-allow on attendee invites; without it, every external
  domain falls through to the homoglyph + IDN gate for prompt.
- `schemaVersionHistory[]` — default `[]` when missing; the writer
  appends the v1 → v2 transition row on next mutation.
- `schemaVersion_bumped_at` — default to the reader's current UTC time
  when missing; persisted by the writer on v1 → v2 upgrade.

After 2026-07-23, readers on plugin versions that have passed the
deprecation window MUST warn the user on a v1 payload ("identity.json
is still on schemaVersion 1 — run `/gevent:onboard identity` or
`/clickup:onboard identity` to upgrade") and refuse auto-migration, to
surface stale-plugin mixes.

### `teammates[].sources` vocabulary

A single teammate can carry multiple tags (union across discovery passes during onboarding). Reserved values:

- `"clickup-workspace"` — pulled from ClickUp workspace members via `mcp__clickup__clickup_get_workspace_members`
- `"clickup-tasks"` — pulled from ClickUp task collaborators via `mcp__clickup__clickup_filter_tasks` (assignees on user's tasks — catches contractors not in the workspace roster)
- `"google-calendar"` — pulled from Google Calendar event attendees in the last 14 days where the user participated AND total attendees ≤ 15 (filters out all-hands noise)
- `"custom:<label>"` — user-supplied during onboarding (paste JSON, name an MCP tool, etc.). `<label>` is free-form.
- `"manual"` — user typed name + email directly (during onboarding or lookup-miss upsert).
- `"seed-from-contacts"` — legacy import from `~/.claude/skills/create-call/contacts.json` (one-shot).
- `"clickup"` — **deprecated** alias for `"clickup-workspace"`. Still recognized on read.
- `"create-call"` — **deprecated** alias for `"manual"`. Still recognized on read.

### What `/gevent` uses from identity.json

- `user.email` — the organizer (auto-excluded from attendee arrays).
- `user.name` — shown in preview headers.
- `teammates[].first_name`, `latin_alias`, `email`, `active`, `full_name` — the attendee resolver input.
- `teammates[].external_ids.google` — if present, not strictly required (email is enough for Calendar invites). Future Google People API integration can populate this.

### What `/gevent` writes to identity.json

- **Upserts a new teammate** when the resolver sees zero matches and the user provides a valid full email (see SKILL.md → Resolution rules for validation regex + IDNA mixed-script rejection). Record shape: `{first_name: <typed>, latin_alias: <typed or ASCII>, full_name: <typed if provided>, email: <confirmed>, external_ids: {}, active: true, sources: ["manual"], last_validated_at: null}`.
- **Never touches `user.*`** — identity wizard owns that slice.
- **Never modifies `teammates[].active`** — that's `/clickup`'s responsibility via its workspace-member sync.
- **Preserves unknown keys** — if a teammate has fields this plugin doesn't recognize, they survive the rewrite.

---

## `~/.claude/gevent/config.json` (gevent-only)

Written by `--onboard calendar`. Read on every invocation.

```json
{
  "schemaVersion": 2,
  "schemaVersion_bumped_at": "2026-04-24T00:00:00Z",
  "schemaVersionHistory": [
    {"from": 1, "to": 2, "at": "2026-04-24T00:00:00Z"}
  ],
  "onboarding_complete": true,
  "updated_at": "2026-04-22T12:15:00Z",
  "defaults": {
    "timezone": "America/New_York",
    "duration_minutes": 30,
    "calendar": "primary",
    "send_updates": "all",
    "conference_type": "hangoutsMeet"
  },
  "behavior": {
    "confirm_before_create": true,
    "check_conflicts": true,
    "past_time_check": true,
    "notes_bot_decided": true
  },
  "always_include": [
    {
      "email": "notes.bot@speedandfunction.com",
      "tag": "notes_bot",
      "optional": true
    }
  ],
  "calendars": [
    {
      "id": "primary",
      "name": "Sashko Marchuk",
      "timezone": "America/New_York"
    }
  ]
}
```

### Field rules

- `schemaVersion` — integer. **Current: `2`.** Writers ALWAYS emit `2`. Readers accept `{1, 2}` during the 90-day back-compat window (2026-04-24 → 2026-07-23); after the window, v1 payloads read-but-warn.
- `schemaVersion_bumped_at` — ISO8601 UTC. Set by the writer that performs the v1 → v2 upgrade; never overwritten on later same-version writes.
- `schemaVersionHistory[]` — append-only log of version transitions, each entry `{from: <int>, to: <int>, at: "<ISO8601>"}`. Preserved verbatim on round-trip.
- `defaults.timezone` — IANA name. Never an offset like `-04:00`.
- `defaults.duration_minutes` — integer. Used when the user doesn't specify a duration.
- `defaults.calendar` — the active calendar ID (`primary` for the user's own Google calendar, or any other ID they have write access to).
- `defaults.send_updates` — `"all" | "externalOnly" | "none"`. Controls whether Google emails invitations.
- `defaults.conference_type` — `"hangoutsMeet"` for Google Meet; no other values currently supported.
- `behavior.confirm_before_create` — if `true`, always show the preview + confirm in interactive mode. Never honored under `--auto`.
- `behavior.check_conflicts` — if `true`, run the conflict query before creating.
- `behavior.past_time_check` — if `true`, guard against past-start times (interactive: ask; `--auto`: refuse).
- `behavior.notes_bot_decided` — boolean (JSON `true` / `false` ONLY — strict type check, NOT a prose truthiness read). **Load-bearing for `onboarding_complete`.** Default `false` on fresh install. Set to `true` ONLY when the `--onboard calendar` wizard explicitly recorded a user decision (either "yes, use bot <email>" OR explicit "no bot"). Pre-flight step 3a (see `SKILL.md`) HALTs every invocation until `isinstance(notes_bot_decided, bool) and notes_bot_decided is True`. Stringified `"true"` (chezmoi/yadm/dotbot dotfile-sync re-encoding), integer `1`, float `1.0`, list, dict, or null all HALT — only the JSON literal `true` is accepted. **`always_include[]` semantics hinge on this flag, AND `always_include` itself MUST be a JSON array (`isinstance(value, list)`) — non-array values (object, string, null) HALT at pre-flight 3a even if the bool flag is correct**:
  - `notes_bot_decided: true` (bool) + `always_include: [{…}]` (array) → user opted in (use the listed bot).
  - `notes_bot_decided: true` (bool) + `always_include: []` (array) → user explicitly chose "no bot" (valid).
  - `notes_bot_decided: false` / missing / wrong type → NEITHER state is valid; the wizard has not recorded a decision yet.
  - `always_include` non-array (e.g. `"[]"` string, `{}`, `null`) → HALT regardless of `notes_bot_decided`.
- `always_include[]` — array of attendee objects always prepended to the attendee array:
  - `email` — required.
  - `tag` — semantic tag (e.g., `"notes_bot"`) for human readability. Optional.
  - `optional` — if `true`, sets `"optional": true` on the attendee in the Google API call (they're invited but not counted in response status).
- `calendars[]` — registry of known calendars for the `--calendar` switch. Optional (populated on first `--calendar` run).

### What `/clickup` should NOT do with this file

`/clickup` must NOT read or write `~/.claude/gevent/config.json`. It's gevent-private. The boundary: shared state lives in `identity.json`; everything else is plugin-local.

### Validation on load

- Missing `schemaVersion` OR non-integer `schemaVersion` → quarantine to `<file>.corrupt-<epoch>`, refuse write (see the `atomic_update` helper gate above).
- `schemaVersion > CURRENT_SCHEMA_VERSION` (i.e. > 2) → refuse to write; run read-only fallback (older plugin saw a file written by a newer plugin; user must upgrade).
- `schemaVersion == 1` during the 90-day back-compat window → accept, fill v2 defaults in memory, upgrade on next mutation.
- `schemaVersion == 1` AFTER the back-compat window (past 2026-07-23) → read-only + warn banner "run `/gevent:onboard identity` to migrate".
- Missing `defaults` or `always_include` → treat as incomplete onboarding.
- Missing OR `false` `behavior.notes_bot_decided` → treat as incomplete onboarding (SKILL.md pre-flight step 3a HALTs; interactive mode redirects to `--onboard calendar`).
- Corrupt JSON → rename to `config.json.corrupt-<epoch>`, surface banner, re-onboard.

---

## Legacy user-level skill detection

The shadow check uses a broadened glob (see `SKILL.md` step 1) covering the canonical path AND backup-dir variants produced by Migration Assistant / Time Machine restores, chezmoi/yadm/dotbot dotfile sync, and common user renames:

- `~/.claude/skills/create-call/` (canonical)
- `~/.claude.backup-*/skills/create-call/` and `~/.claude.backup-*/skills-create-call/`
- `~/.claude.bak/skills/create-call/` and `~/.claude.bak/skills-create-call/`
- `~/.claude.old*/skills/create-call/` and `~/.claude.old*/skills-create-call/`
- `~/.claude-backup-*/skills/create-call/` and `~/.claude-backup-*/skills-create-call/`
- `~/.claude-plugins-backup-*/skills-create-call/` and `~/.claude-plugins-backup-*/skills/create-call/`

If any of those globs match a directory, the plugin emits a banner on every invocation enumerating every hit:

```
⚠ Legacy user-level create-call skill detected at: <hit_1>, <hit_2>, … — this plugin is now called gevent. Remove with: rm -rf <each path>. Backups under ~/.claude.backup-*, ~/.claude.bak, ~/.claude.old*, ~/.claude-backup-* are caught here too.
```

The plugin does NOT auto-delete the legacy directory. The user may still have `contacts.json` data there they want to copy over. Removal is their decision.

### Seeding from legacy `contacts.json` (one-time, on first `--onboard` only)

If `~/.claude/skills/create-call/contacts.json` exists AND `~/.claude/shared/identity.json` does NOT exist, the identity wizard offers:

> "Found a legacy contacts.json with N entries. Import them as a thin seed for your teammate roster? (Each becomes `{first_name, latin_alias, email, sources: [\"seed-from-contacts\"], last_validated_at: null}`. Clickup MCP can enrich them later.)"

User says yes → upsert each `{alias: email}` as a teammate with `first_name = alias`, `latin_alias = alias`. User says no → skip.

The legacy file is never written to and never deleted by this skill.
