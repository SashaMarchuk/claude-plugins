# Config + memory schemas

## config.json

Path: `~/.claude/clickup/config.json`

Written by `--onboard`. Read on every invocation (pre-flight step 1).

```json
{
  "version": "1.0",
  "onboarding_complete": true,
  "step_1_done_at": "2026-04-22T12:00:00Z",
  "updated_at": "2026-04-22T12:15:00Z",
  "user": {
    "name": "Sashko Marchuk",
    "email": "sasha.marchuk@speedandfunction.com",
    "user_id": "100682233"
  },
  "workspace": {
    "id": "90151491867",
    "name": "Speed&Functions"
  },
  "teammates": [
    {
      "first_name": "Misha",
      "latin_alias": "Misha",
      "full_name": "Misha Skripkovsky",
      "email": "misha@speedandfunction.com",
      "user_id": "106686024",
      "active": true,
      "last_validated_at": "2026-04-22T12:15:00Z"
    },
    {
      "first_name": "Михайло",
      "latin_alias": "Mykhailo",
      "full_name": "Михайло Іваненко",
      "email": "m.ivanenko@…",
      "user_id": "…",
      "active": true,
      "last_validated_at": "2026-04-22T12:15:00Z"
    }
  ],
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
  "preferences": {
    "language": "en",
    "default_priority": "normal",
    "default_status": "backlog",
    "default_task_type": "task"
  }
}
```

### Field rules

- `onboarding_complete`: becomes `true` only after step 2 finishes cleanly.
- `teammates[].latin_alias`: always Latin-script. For Cyrillic/other scripts, onboarding asks user to confirm. Single transliteration per teammate.
- `teammates[].active`: re-validated lazily when `last_validated_at` > 7 days.
- `lists[].aliases`: lowercase matching; stored as-typed.
- `preferences.language`: forced `en`. Included for future flexibility but not overridable from UI.

### Validation on load

If schema-invalid (missing `version`, corrupted JSON, `onboarding_complete` missing), prompt re-onboard. Don't attempt repair.

---

## memory.md

Path: `~/.claude/clickup/memory.md`

Human-editable. Markdown. Read on every invocation.

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

## rule-002
**Rule:** For MN Service bugs, default priority = high.
**Pattern:** list resolves to "[Meetings Bot] Project" AND task_type = bug
**Action:** set priority = high
**Added:** 2026-03-20
**Last applied:** 2026-04-22
**Applied count:** 12

## rule-003
**Rule:** Prefer verb "Resolve" over "Fix" for bug titles.
**Pattern:** task_type = bug
**Action:** replace leading "Fix" with "Resolve" in generated title
**Added:** 2026-04-10
**Last applied:** 2026-04-21
**Applied count:** 4
```

### Rule file rules

- One rule per `## rule-<id>` section.
- `<id>` is monotonically increasing (rule-001, rule-002, …). Removed rules leave a gap — don't renumber.
- **Rule**: one-line human description of the guideline.
- **Pattern**: machine-evaluable condition. Keep it simple — keyword match or field-equals.
- **Action**: imperative, targets one ticket field.
- **Added**, **Last applied**, **Applied count**: maintained by the skill. Hand-edit only if reviewing.

### Application order

1. Extract from source → candidate ticket fields.
2. For each rule in order, if `Pattern` matches AND the field the action targets is NOT user-overridden this invocation → apply `Action`, update `Last applied` + `Applied count`.
3. Proceed to resolution + preview.

Rules don't override explicit user input in the current turn. If a user types "assign to Misha" and rule-001 says "auth → Andy", Misha wins.

### Staleness

- Rules with `Last applied` > 60 days ago → flag as stale in `--status`.
- Rules with `Applied count` > 20 → flag as confirmed-useful.

---

## drafts/

Path: `~/.claude/clickup/drafts/`

Per-invocation JSON snapshots, keyed by UUID. Created BEFORE calling `clickup_create_task`.

```json
{
  "uuid": "e7f3a1…",
  "created_at": "2026-04-22T12:30:00Z",
  "invocation": "/clickup --auto",
  "source_text": "<first 500 chars of source context>",
  "resolved": {
    "list_id": "901522761229",
    "assignee_user_ids": ["106686024"],
    "priority": "normal",
    "status": "backlog",
    "task_type": "task",
    "tags": ["mn service"],
    "title": "Detect when bot isn't allowed — alert Slack after 5 min",
    "description": "<full markdown>"
  },
  "api_response": null,
  "task_url": null
}
```

After successful create, `api_response` and `task_url` are populated. On retry search, look for `uuid` in open tickets to detect prior partial success.

### Cleanup

Drafts older than 7 days with `task_url` populated → auto-delete on next `--status` or `--memory` invocation. Drafts with `task_url: null` and >1 hour old → surface in `--status` as "orphan drafts" for manual review.
