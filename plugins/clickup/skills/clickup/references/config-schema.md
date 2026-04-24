# Config + memory schemas

## Shared-contract constants

```python
# SHARED between /clickup and /gevent. Keep in sync with the gevent helper.
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

The clickup skill reads **two** JSON files on every invocation:

1. `~/.claude/shared/identity.json` — user profile + teammate roster, shared with `/gevent`.
2. `~/.claude/clickup/config.json` — clickup-specific state (workspace, lists, preferences).

Plus a human-editable `~/.claude/clickup/memory.md` (learned rules) and a `drafts/` subdir for idempotency snapshots.

## Non-negotiable file rules

These apply to BOTH JSON files, whenever the skill writes them:

1. **Atomic write** — write to `<file>.tmp` in the same dir, `fsync`, then `os.replace(tmp, file)`. Never edit in place.
2. **`fcntl.flock`** — take an exclusive lock on a sibling sentinel file (`<file>.lock` — NO leading dot on the sibling; e.g. `identity.json` → `identity.json.lock`). For the SHARED `identity.json` file the canonical cross-plugin lock path is **`~/.claude/shared/identity.json.lock`** (matches `/gevent`'s helper exactly — deviation breaks mutual exclusion). Hold the lock for the entire read-modify-write. The kernel releases the lock when the process dies, so stale locks are impossible.
3. **Preserve unknown keys** — when rewriting, round-trip any top-level or nested keys the skill does not recognize. `/gevent` may have added fields to a teammate record that this version of `/clickup` does not know about; they must survive a rewrite.
4. **`schemaVersion: 2`** — integer at the top of every file. Writers ALWAYS emit the current version (`CURRENT_SCHEMA_VERSION = 2`). Readers accept both v1 and v2 during the 90-day back-compat window (2026-04-24 → 2026-07-23 — see `SCHEMA_VERSION_DEPRECATION_DAYS`). On read: if `schemaVersion == 1`, fill in v2 defaults silently (migration-on-next-mutation — no eager write). On write: upgrade in place to v2 atomically (single `atomic_update` pass). Quarantine if `"schemaVersion" not in data` OR `not isinstance(data["schemaVersion"], int)`. If the reader sees a HIGHER version it does not understand, refuse to write (read-only fallback) rather than downgrade.
4a. **`schemaVersion_bumped_at`** — ISO8601 timestamp next to `schemaVersion`. Set once by the writer that performs the N-1 → N upgrade; never overwritten on later writes at the same N.
4b. **`schemaVersionHistory[]`** — append-only log of version transitions: `[{from: 1, to: 2, at: "<ISO>"}, …]`. Added by the writer on every version bump. Preserved by both plugins on round-trip (unknown-keys rule applies).
5. **On corrupt JSON** — move the file to `<file>.corrupt-<epoch>` and start fresh from skeleton, with a banner to the user.

### Reference write helper (Python, stdlib only)

**Platform support**: tested on macOS and Linux. Windows is not supported — `fcntl` is POSIX-only. A Windows user would need a `msvcrt.locking` fallback.

```python
import fcntl, json, os, tempfile, time

# Keep identical in /clickup and /gevent — this is the cross-plugin contract.
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
    },
    {
      "first_name": "Михайло",
      "latin_alias": "Mykhailo",
      "full_name": "Михайло Іваненко",
      "email": "m.ivanenko@speedandfunction.com",
      "external_ids": {"clickup": "..."},
      "active": true,
      "sources": ["clickup-workspace", "clickup-tasks", "google-calendar"],
      "last_validated_at": "2026-04-22T12:15:00Z"
    }
  ]
}
```

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
  until `/clickup` workspace-sync verifies the record — closes
  PLG-clickup-13).
- `trusted_domains[]` — default `[]` when missing. `/gevent` uses this
  to gate silent-allow on attendee invites.
- `schemaVersionHistory[]` — default `[]` when missing; the writer
  appends the v1 → v2 transition row on next mutation.
- `schemaVersion_bumped_at` — default to the reader's current UTC time
  when missing; persisted by the writer on v1 → v2 upgrade.

After 2026-07-23, readers on plugin versions that have passed the
deprecation window MUST warn the user on a v1 payload ("identity.json
is still on schemaVersion 1 — run `/clickup:onboard identity` to
upgrade") and refuse auto-migration, to surface stale-plugin mixes.

### Field rules

- `schemaVersion` — integer. **Current: `2`.** Writers ALWAYS emit `2`. Readers accept `{1, 2}` during the 90-day back-compat window (2026-04-24 → 2026-07-23); after the window, v1 payloads read-but-warn.
- `schemaVersion_bumped_at` — ISO8601 UTC. Set by the writer that performs the v1 → v2 upgrade; never overwritten on later same-version writes.
- `schemaVersionHistory[]` — append-only log of version transitions, each entry `{from: <int>, to: <int>, at: "<ISO8601>"}`. Preserved verbatim on round-trip by both plugins.
- `trusted_domains[]` — array of ASCII domain strings (e.g. `["speedandfunction.com"]`). Consumed by `/gevent` to classify attendee emails as internal vs external; consumed by `/clickup` for the same purpose on ticket assignees. Default `[]` when missing (v1 migration). No leading dot; subdomain-matching semantics.
- `user.external_ids` — open map. Reserved keys: `clickup`, `google`, `slack`, `jira`. Add more as new plugins need them. Plugin-agnostic key.
- `teammates[].first_name` — the teammate's first name as they use it (Cyrillic ok). Used by the NFC-fallback branch of the resolver.
- `teammates[].latin_alias` — ASCII-only short form. Required for every teammate (even if Latin-scripted name = alias). Primary key for the resolver.
- `teammates[].email` — canonical identity. Upserts are keyed on email.
- `teammates[].external_ids` — same open map as user. Optional per teammate. `/clickup` populates `clickup`; `/gevent` populates `google` when it has it.
- `teammates[].active` — boolean. **v2 MUST be present**; missing is treated as `false` on read (blocks assignment until `/clickup` workspace-sync validates — closes PLG-clickup-13). `/clickup` flips to `false` when a teammate disappears from workspace members. `/gevent` still allows scheduling with inactive teammates but surfaces a banner.
- `teammates[].sources` — array of origins. A single teammate can carry multiple tags (union across discovery passes). Reserved values:
  - `"clickup-workspace"` — pulled from `mcp__clickup__clickup_get_workspace_members` (current workspace members)
  - `"clickup-tasks"` — pulled from `mcp__clickup__clickup_filter_tasks` assignees on the user's open tasks (catches contractors/external collaborators not in the workspace roster)
  - `"google-calendar"` — pulled from Google Calendar event attendees in the last 14 days where the user participated AND attendees ≤ 15 (filters out all-hands noise)
  - `"custom:<label>"` — user-supplied during onboarding (paste JSON, name an MCP tool, etc.). `<label>` is free-form.
  - `"manual"` — user typed name + email directly (during onboarding or lookup-miss upsert).
  - `"seed-from-contacts"` — legacy import from `~/.claude/skills/create-call/contacts.json` (one-shot, supported for backward-compat with the pre-plugin skill).
  - `"clickup"` — **deprecated** alias for `"clickup-workspace"`. Still recognized on read; new writes should use `"clickup-workspace"`.
  - `"create-call"` — **deprecated** alias for `"manual"` via create-call's zero-match path. Still recognized.
- `teammates[].last_validated_at` — ISO8601. `/clickup` refreshes this on 7-day TTL. `null` for entries never validated against a source of truth.

### Dual-key teammate resolver (pure function)

When matching a user-typed name to a teammate:

1. NFC-normalize the typed name, strip leading/trailing whitespace.
2. **First pass** — case-insensitive match against `teammates[].latin_alias`. Most names go here; Latin-only users hit this path every time.
3. **Second pass** — case-insensitive + NFC match against `teammates[].first_name`. Cyrillic users typing their own name in Cyrillic hit this path.
4. **Third pass** — exact case-insensitive match on `teammates[].email` (for when user types an email directly).
5. Multiple hits → prompt disambiguation with full name + email.
6. Zero hits → prompt for full email, then upsert new record with `sources: ["manual"]`.

### Validation on load

- Missing `schemaVersion` OR non-integer `schemaVersion` → quarantine to `<file>.corrupt-<epoch>`, refuse write (see the `atomic_update` helper gate above).
- `schemaVersion > CURRENT_SCHEMA_VERSION` (i.e. > 2) → refuse to write; run read-only fallback (older plugin saw a file written by a newer plugin; user must upgrade).
- `schemaVersion == 1` during the 90-day back-compat window → accept, fill v2 defaults in memory, upgrade on next mutation.
- `schemaVersion == 1` AFTER the back-compat window (past 2026-07-23) → read-only + warn banner "run `/clickup:onboard identity` to migrate".
- Missing `user` or `teammates` → treat as incomplete onboarding.
- Corrupt JSON → rename to `identity.json.corrupt-<epoch>`, surface banner, re-onboard.

---

## `~/.claude/clickup/config.json` (clickup-only)

Written by `--onboard workspace`. Read on every invocation.

```json
{
  "schemaVersion": 1,
  "onboarding_complete": true,
  "updated_at": "2026-04-22T12:15:00Z",
  "workspace": {
    "id": "90151491867",
    "name": "Speed&Functions"
  },
  "lists": [
    {
      "id": "901522761229",
      "name": "[Meetings Bot] Project",
      "aliases": ["MNB", "MN Service", "MN", "meetings bot", "notes bot"],
      "space_id": "…",
      "folder_id": "…",
      "archived": false,
      "last_validated_at": "2026-04-22T12:15:00Z"
    }
  ],
  "defaults": {
    "language": "en",
    "priority": "normal",
    "status": "backlog",
    "task_type": "task"
  },
  "behavior": {}
}
```

### Field rules

- `workspace` — the active ClickUp workspace. Switched via `--workspace`.
- `lists[].aliases` — lowercase matching; stored as-typed.
- `defaults` — values (what to use when user doesn't specify). Replaces the older `preferences` bag.
- `behavior` — boolean flags that gate UX. Empty in v1; reserved for future toggles.

**Removed from older schemas:** `user`, `teammates[]`, `preferences` (split into `defaults` + `behavior`).

### Validation

Same invariants as identity.json: integer schemaVersion, preserve unknown keys, atomic writes, flock. On corrupt JSON → rename + re-onboard.

---

## memory.md

Path: `~/.claude/clickup/memory.md`. Human-editable. Markdown. Read on every invocation.

```markdown
# /clickup memory

Last updated: 2026-04-22

## rule-001
**Rule:** Assign auth-related tickets to Andy.
**Pattern:** source mentions "auth", "login", "password", "oauth", "sso"
**Action:** set assignee = Andy Rozhylo
**Added:** 2026-03-15
**Last applied:** 2026-04-18
**Applied count:** 7
```

### Rule file rules

- One rule per `## rule-<id>` section. Monotonically increasing IDs; removed rules leave gaps.
- **Rule**: one-line human description.
- **Pattern**: keyword match or field-equals. Simple.
- **Action**: imperative, one ticket field.
- **Added / Last applied / Applied count**: maintained by the skill.

### Application order (4-tier precedence — load-bearing)

Resolve every ticket field using EXACTLY these four tiers, highest wins.
This precedence is pinned so "memory rule says X, but keyword in the
current turn says Y" resolves deterministically — closes PLG-clickup-F10.

1. **Explicit CLI flag / field-set in the current turn** (strongest).
   The user typed `--priority=high` or explicitly wrote "assign to Misha"
   as a direct imperative. Always wins; never overridden by anything below.
2. **Keyword-in-turn from source text** (second strongest).
   The current turn's source includes a priority-keyword (e.g.
   "low priority typo for Daria" → priority=low per the keyword table at
   SKILL.md → Defaults → Priority). Keyword-in-turn explicitly WINS over
   any memory rule that says otherwise. Example: memory rule
   "Daria = P1" + source "low priority typo for Daria" → priority resolves
   to `low` (keyword beats memory). Without this tie-break, a noisy old
   memory rule would override a clear operator signal in the current turn.
3. **Memory rule** (third).
   Stored `## rule-<id>` matches the source text's Pattern AND the target
   field is not set by tier 1 or tier 2. Apply Action; increment
   `Applied count`; update `Last applied`. Subject to staleness gate
   below (rules auto-demoted at 90 days advisory-only).
4. **Default** (weakest).
   Whatever the Defaults table in SKILL.md pins (priority=normal,
   status=backlog, task_type=task, etc.).

Resolution loop (pseudocode):

```
for field in (priority, assignee, list, task_type, tag, status):
    if tier1_match(field, turn): value = tier1_match(field, turn); continue
    if tier2_match(field, turn): value = tier2_match(field, turn); continue
    if tier3_match(field, memory, turn): value = tier3_match(...); continue
    value = tier4_default(field)
```

**No tie-break ambiguity**: tiers are strictly ordered. Two memory rules
competing at tier 3 are resolved by monotonic rule-id (older wins —
established patterns beat new-arrival overrides).

### Staleness + auto-demotion

- **`last_applied_at` > 60 days ago** → flag as stale (banner in `--status`; rule still auto-applies at tier 3).
- **`last_applied_at` > 90 days ago** → **auto-demote to `advisory` tier**. An advisory rule does NOT auto-apply at tier 3 of the 4-tier precedence above. It is ONLY surfaced as a suggestion in interactive `--memory list` output (format: `⚠ advisory: rule-<id> (last applied <N> days ago)`). A 120-day-old rule is explicitly NOT applied — the resolver skips it at tier 3 and falls through to tier 4 (default) unless the operator re-promotes it via `/clickup --memory add` (which resets `last_applied_at` to now). This closes PLG-clickup-F15: the previous "banner but still apply" behaviour let noisy old rules fire indefinitely. The auto-demote is mechanical — the 90-day threshold is measured from `last_applied_at` at each pre-flight run; no human decision required.
- **`Applied count` > 20** → flag as confirmed-useful (leave alone, even if stale).

Implementation note: auto-demotion is a read-time determination, not a persistent mutation. The rule's on-disk record is unchanged; only the resolver treats it as advisory. A rule re-promoted by matching current-turn source text (re-application resets `last_applied_at`) returns to tier 3 automatically on the NEXT invocation.

---

## drafts/

Path: `~/.claude/clickup/drafts/`. Per-invocation JSON snapshots keyed by UUID. Created BEFORE calling `clickup_create_task`.

```json
{
  "uuid": "e7f3a1…",
  "created_at": "2026-04-22T12:30:00Z",
  "invocation": "/clickup --auto",
  "source_text": "<first 500 chars>",
  "resolved": {
    "list_id": "901522761229",
    "assignee_user_ids": ["106686024"],
    "priority": "normal",
    "status": "backlog",
    "task_type": "task",
    "tags": ["mn service"],
    "title": "…",
    "description": "…"
  },
  "api_response": null,
  "task_url": null
}
```

After successful create, `api_response` and `task_url` populate. On retry, search the list for the UUID marker (hidden in description as `<!-- ck:<uuid> -->`) before re-creating.

### Cleanup

- Drafts with `task_url` populated + older than 7 days → auto-delete on next `--status` or `--memory` run.
- Drafts with `task_url: null` + older than 1 hour → surface as "orphan drafts" in `--status` for manual review.
