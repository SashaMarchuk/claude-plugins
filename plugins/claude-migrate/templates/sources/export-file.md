> **This is a shipped template.** **Copy it to your run directory before editing** - direct edits to this file will be wiped on `/plugin update`. To copy:
> ```bash
> cp ${CLAUDE_PLUGIN_ROOT}/templates/sources/export-file.md .planning/claude-migrate/<run-name>/source-connector.md
> ```

# Source connector: export-file
Source type: Claude.ai data export folder (an unzipped `Settings -> Privacy -> Export data` archive). Top-level files: `conversations.json`, `projects/<uuid>.json`, `memories.json`, `users.json`.
Authentication: none. This is a static, on-disk read of files the user already downloaded. Read-only. The connector NEVER writes back to `input.export_path`.

This is the DEFAULT source. All seven operations are executed deterministically by `node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs <export_path> <op> [arg]`; the universal `source` skill dispatches to that parser and never invents field names. Every op below names the exact parser sub-command and its return shape. `idx`/`UNNN` are assigned by the `source` skill after `enumerate` sorts uuids ascending (Universality M1) - the parser returns uuids, not positions.

## enumerate
Read `conversations.json` (an array of chat objects). Return the `uuid` of every chat as a JSON array of strings - NOT positional indices.

```bash
node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs "$EXPORT_PATH" enumerate
```

Return shape:
```json
["<uuid-a>", "<uuid-b>", "<uuid-c>"]
```

The `source` skill sorts this array ascending and assigns `UNNN` = the 1-based position in the sorted order (`U001`, `U002`, ...). This makes `UNNN` a stable function of the source uuid, identical across re-extractions and across export/live modes (M1).

## extract_unit
For one chat uuid, read its `chat_messages[]` and produce ONE normalized unit. Apply the canonical text rule (deterministic - research §1.1) to every message, in order:

1. Prefer `message.text` when non-empty (for assistant turns the FULL reply lives here).
2. Else join `content[]` blocks where `type === "text"`, using their `.text`, in array order.
3. SKIP `thinking`, `tool_use`, and `tool_result` blocks entirely (noise for continuation).
4. Append each `attachments[].extracted_content` (uploaded-document text) as additional context.
5. For each `files[].file_name`, emit the literal note `[image existed: <file_name> - not in export]` (the bytes are not in the export; never invent image contents).
6. An empty human turn (no `text` and no `text` content block) becomes `[no text]`; never crash.

```bash
node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs "$EXPORT_PATH" extract_unit "<uuid>"
```

Return shape:
```json
{
  "idx": 1,
  "uuid": "<uuid>",
  "name": "<chat title or empty string>",
  "created_at": "2026-06-02T00:00:00+00:00",
  "messages": [ { "sender": "human", "text": "..." }, { "sender": "assistant", "text": "..." } ],
  "attachments_text": "<joined extracted_content or empty>",
  "image_refs": ["[image existed: NAME - not in export]"],
  "raw_token_est": 0
}
```

`raw_token_est` is computed deterministically by the parser: chars/4 for Latin-script text, chars/3 for Cyrillic/CJK-heavy text (Universality H2). It is copied into `value/UNNN.value.json` so `cost_estimate` is a pure function of the parsed units and never depends on a model gate.

## extract_projects
Read every `projects/<uuid>.json`. Each project file has `uuid, name, description, is_private, is_starter_project, prompt_template, docs[], creator`.

- `prompt_template` IS the project's Custom Instructions (the field the sink re-creates).
- `docs[]` is an array of `{uuid, filename, content, created_at}` - project knowledge files WITH full text content (these can be migrated).
- A project with `is_starter_project: true` is the built-in sample shipped by Anthropic. The connector returns it with `is_starter: true`; the controller DROPS starter projects and never migrates them.

```bash
node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs "$EXPORT_PATH" extract_projects
```

Return shape (sorted by `pid_uuid` ascending; the `source` skill assigns `PNN` = sorted position):
```json
[
  {
    "pid_uuid": "<project-uuid>",
    "name": "Project Alpha",
    "prompt_template": "<custom instructions text>",
    "knowledge_docs": [ { "filename": "topic-1.md", "content": "..." } ],
    "is_starter": false
  }
]
```

## unit_project_ref
A Claude.ai export carries NO foreign key from a chat to a project. The connector therefore returns `null` for every unit - the export cannot resolve a real join key.

```bash
node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs "$EXPORT_PATH" unit_project_ref "<uuid>"
```

Return: `null`.

Because this source returns `null`, every kept chat defaults to STANDALONE. A chat becomes GROUPED ONLY via the user's explicit assignment at the filter-gate (persisted in `decisions.project_assignment`); the connector never infers grouping (Universality C2). `preflight-value` may emit only `KEEP | REFERENCE | DROP`, never `GROUPED`.

## account_check
Read `users.json` (an array of length 1: `{uuid, full_name, email_address, verified_phone_number}`) for the SOLE purpose of computing a SHA-256 hash of the email address, to sanity-check that this export belongs to the source account. The clear email, name, and phone are PII: NEVER copied into `source/`, NEVER written to any output, NEVER logged.

```bash
node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs "$EXPORT_PATH" account_check
```

Return shape:
```json
{ "verified_account_email_hash": "<sha256 hex>" }
```

This hash is stored in `state.input.source_account_email_hash`. If `users.json` is absent, return `{ "verified_account_email_hash": null }` (a soft warning at the filter-gate, never a stop).

## citation_anchor
For one unit, return a stable provenance string the briefs and verify pass can cite.

```bash
node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs "$EXPORT_PATH" citation_anchor "<uuid>"
```

Return format: `[EXPORT:conversations.json#<idx>]` for the chat as a whole, or `[CHAT:<uuid>]` when the uuid is the more stable anchor. Use the `#<idx>` form for human-readable references and the `[CHAT:<uuid>]` form when stability across re-extraction matters.

## forbidden_fields
Return the redact/strip list for this source. For an on-disk export the PII is concentrated in `users.json` and may appear inside `memories.json`.

```bash
node ${CLAUDE_PLUGIN_ROOT}/bin/parse-export.cjs "$EXPORT_PATH" forbidden_fields
```

Return shape:
```json
[
  { "path_or_pattern": "users.json", "disposition": "filter" },
  { "path_or_pattern": "email_address", "disposition": "redact" },
  { "path_or_pattern": "verified_phone_number", "disposition": "redact" },
  { "path_or_pattern": "full_name", "disposition": "redact" }
]
```

`filter` = never copy the file/field into the run dir at all. `redact` = if the value reaches any captured text, replace it with the matching `[REDACTED:*]` token from `${CLAUDE_PLUGIN_ROOT}/references/pii-policy.md`. The redact regex set (email, phone, Bearer/JWT, cookie, Authorization) is owned by `references/pii-policy.md` and is the single source of truth; this connector references it, never re-defines it.

## Budget constraints
- Single pass: `conversations.json` is read once (verified on a 53 MB / 64-chat export). No per-chat re-reads of the big file.
- No network calls. No model calls in any op - the parser is pure Node.
- `est_tokens` is deterministic, so the cost estimate is reproducible across runs.

## Known limitations
- Read-only. The connector never modifies `input.export_path`.
- Image/binary bytes are NOT present in the export (`files[]` carries only `file_name`); migration can note the image existed but cannot transfer it.
- `unit_project_ref` is always `null` (no FK in the export) - grouping is a user decision, not a derived fact.
- `users.json` is consumed for the email hash only; its clear contents must never leave the parser.
