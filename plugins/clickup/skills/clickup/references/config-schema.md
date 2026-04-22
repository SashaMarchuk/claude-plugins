# Config + memory schemas

The clickup skill reads **two** JSON files on every invocation:

1. `~/.claude/shared/identity.json` — user profile + teammate roster, shared with `/create-call`.
2. `~/.claude/clickup/config.json` — clickup-specific state (workspace, lists, preferences).

Plus a human-editable `~/.claude/clickup/memory.md` (learned rules) and a `drafts/` subdir for idempotency snapshots.

## Non-negotiable file rules

These apply to BOTH JSON files, whenever the skill writes them:

1. **Atomic write** — write to `<file>.tmp` in the same dir, `fsync`, then `os.replace(tmp, file)`. Never edit in place.
2. **`fcntl.flock`** — take an exclusive lock on a sibling sentinel file (`<file>.lock`) for the entire read-modify-write. The kernel releases the lock when the process dies, so stale locks are impossible.
3. **Preserve unknown keys** — when rewriting, round-trip any top-level or nested keys the skill does not recognize. `/create-call` may have added fields to a teammate record that this version of `/clickup` does not know about; they must survive a rewrite.
4. **`schemaVersion: 1`** — integer at the top of every file. If a reader sees a higher version it does not understand, refuse to write (read-only fallback) rather than downgrade.
5. **On corrupt JSON** — move the file to `<file>.corrupt-<epoch>` and start fresh from skeleton, with a banner to the user.

### Reference write helper (Python, stdlib only)

**Platform support**: tested on macOS and Linux. Windows is not supported — `fcntl` is POSIX-only. A Windows user would need a `msvcrt.locking` fallback.

```python
import fcntl, json, os, tempfile, time

def atomic_update(path, mutate):
    path = os.path.expanduser(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lock_path = path + ".lock"
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
        mutate(data)  # caller supplies closure
        dir_ = os.path.dirname(path)
        with tempfile.NamedTemporaryFile("w", dir=dir_, delete=False) as tmp:
            json.dump(data, tmp, indent=2, ensure_ascii=False, sort_keys=False)
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = tmp.name
        os.replace(tmp_path, path)
```

Every write path in this skill must go through `atomic_update` (or a Bash equivalent with `flock(1)` + `mv`).

**Contract for caller-supplied `mutate` closures**: perform all mutation logic BEFORE any file operation, so if the closure raises, we abort before writing the tempfile. The helper catches nothing — exceptions propagate up with the lock held through the `with` block, then released on context exit.

---

## `~/.claude/shared/identity.json` (SHARED — /clickup + /create-call)

Written the first time either skill's onboarding runs. Read on every invocation of either skill.

```json
{
  "schemaVersion": 1,
  "onboarding_complete": true,
  "updated_at": "2026-04-22T12:15:00Z",
  "user": {
    "name": "Sashko Marchuk",
    "email": "sasha.marchuk@speedandfunction.com",
    "external_ids": {
      "clickup": "100682233"
    }
  },
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

### Field rules

- `schemaVersion` — integer. Current: `1`.
- `user.external_ids` — open map. Reserved keys: `clickup`, `google`, `slack`, `jira`. Add more as new plugins need them. Plugin-agnostic key.
- `teammates[].first_name` — the teammate's first name as they use it (Cyrillic ok). Used by the NFC-fallback branch of the resolver.
- `teammates[].latin_alias` — ASCII-only short form. Required for every teammate (even if Latin-scripted name = alias). Primary key for the resolver.
- `teammates[].email` — canonical identity. Upserts are keyed on email.
- `teammates[].external_ids` — same open map as user. Optional per teammate. `/clickup` populates `clickup`; `/create-call` populates `google` when it has it.
- `teammates[].active` — boolean. `/clickup` flips to `false` when a teammate disappears from workspace members. `/create-call` still allows scheduling with inactive teammates but surfaces a banner.
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

- Missing `schemaVersion` OR `schemaVersion > 1` → refuse to write; run read-only fallback.
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

### Application order

1. Extract from source → candidate fields.
2. For each rule in order: if pattern matches AND target field is not user-overridden → apply action, update `Last applied` + `Applied count`.
3. Explicit user input in the current turn ALWAYS wins over rules.

### Staleness

- Last applied > 60 days ago → flag as stale.
- Applied count > 20 → flag as confirmed-useful.

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
