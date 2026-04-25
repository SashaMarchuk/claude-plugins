> **This is a shipped template.** **Copy it to your run directory before editing** — direct edits to this file will be wiped on `/plugin update`. To copy:
> ```bash
> cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/<type>.md .planning/ultra-analyzer/<run-name>/connector.md
> ```

# Connector: sqlite
Source type: Local SQLite database file (.db, .sqlite, .sqlite3).
Authentication: None — direct file access via `sqlite3` CLI.

## Read-only connection (closes M-2)

EVERY `sqlite3` invocation in this connector MUST open the database via the
URI form with `?mode=ro` so the OS-level file handle is read-only. Refuse
to invoke the bare `sqlite3 "$DB_PATH"` form.

```bash
# Canonical read-only invocation. URI mode=ro means even a malicious SQL
# string that bypassed the keyword grep would fail at the OS layer.
SQLITE_URI="file:${DB_PATH}?mode=ro"
sqlite3 -readonly "$SQLITE_URI" "<sql>"
# Equivalent on older sqlite that lacks -readonly:
#   sqlite3 "$SQLITE_URI" "<sql>"   (URI handler picks up mode=ro)
```

## Pre-exec SQL grep (closes M-2)

Before passing ANY caller-supplied SQL to sqlite3, run the keyword grep
below. The grep is case-insensitive and matches the keyword as a word so
`iNsErT` is also caught. ALSO strip SQL comments (`-- ... \n` and
`/* ... */`) before grepping so a comment-cloaked keyword cannot bypass.

```bash
sql_is_safe() {
  local raw="$1"
  # Strip /* ... */ block comments and -- ... line comments first.
  local sql
  sql=$(printf '%s' "$raw" \
    | perl -pe 'BEGIN{undef $/;} s|/\*.*?\*/||gs' \
    | sed 's|--[^\n]*||g')
  # Word-bounded, case-insensitive grep for forbidden verbs.
  if printf '%s' "$sql" | grep -Eiq '(^|[[:space:];])(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|REPLACE|TRUNCATE|ATTACH|VACUUM|PRAGMA[[:space:]]+writable_schema|PRAGMA[[:space:]]+foreign_keys[[:space:]]*=)([[:space:]]|$|;)'; then
    echo "ERROR: refusing SQL — contains forbidden write/DDL keyword (M-2)" >&2
    return 1
  fi
  return 0
}

# Usage:
sql_is_safe "$INCOMING_SQL" || exit 11
sqlite3 -readonly "file:${DB_PATH}?mode=ro" "$INCOMING_SQL"
```

This grep MUST run on every execute_query path even though `?mode=ro` would
also block writes. Defense in depth — the grep is the primary guard,
read-only mode is the secondary backstop.

## enumerate
```bash
sqlite3 -readonly "file:${DB_PATH}?mode=ro" ".tables" | tr ' ' '\n' | grep -v '^$' | jq -R -s 'split("\n") | map(select(length>0))'
```
Filter by config.yaml `source.tables` if declared (intersect with the full list).
Return: JSON array of table names.

## sample_schema
```bash
sqlite3 -readonly "file:${DB_PATH}?mode=ro" "PRAGMA table_info(<table>)"
sqlite3 -readonly "file:${DB_PATH}?mode=ro" "SELECT * FROM <table> LIMIT <N>"
```
Combine: column types from PRAGMA + null rates + sample values from LIMIT query.
Return: `{"unit": "<table>", "fields": {"<col>": {"type": "INTEGER|TEXT|REAL|BLOB", "null_rate": 0.0, "samples": [...]}}}`.

## execute_query
Query-spec shape: `{op: "select|count|aggregate", sql: "<full-sql-statement>"}`.
Safety: invoke `sql_is_safe` on the incoming SQL FIRST and refuse with
exit 11 if it returns non-zero. Then connect with `?mode=ro` so even an
escape would still hit a read-only OS handle. The grep catches `iNsErT`,
`-- INSERT` (comment-stripped first), and nested-CTE writes.
```bash
sql_is_safe "$sql" || exit 11
sqlite3 -readonly -json "file:${DB_PATH}?mode=ro" "<sql>"
```
Parse the JSON output, compute row_count and result_hash.
Return: `{"rows": [...], "row_count": N, "result_hash": "<sha256>"}`.

## resolve_refs
SQLite foreign keys: if topic spec declares a JOIN, execute_query handles it directly via SQL.
Pass-through for this connector — the caller composes JOINs at query construction time.

## citation_anchor
Format: `[ROW:<table>:<primary-key>]`.
Example: `[ROW:orders:id=12345]`.
For tables without a primary key, use rowid: `[ROW:<table>:rowid=N]`.

## forbidden_fields
From config.yaml `source.forbidden_fields`. Typical entries for a SQLite dump:
- Columns with PII: `users.email`, `users.password_hash`, `sessions.token`
Adapter-detected:
- Columns whose name matches `(?i)(password|hash|token|secret|key)`.
Return: `[{"path_or_pattern": "users.password_hash", "disposition": "filter"}, ...]`.

## Budget constraints
- Per-query timeout: 60s (use `sqlite3` `.timeout 60000`).
- Max rows returned: 5,000 (add `LIMIT` in SQL if needed).
- Read-only mode enforced: adapter opens with `?mode=ro` via URI filename
  (M-2). All shipped invocations above use `file:$DB_PATH?mode=ro` — bare
  `sqlite3 "$DB_PATH"` is REFUSED.

## Known limitations
- FTS (full-text search) extensions: if present, can be used in execute_query; if absent, fall back to `LIKE` which is slow on large tables.
- ATTACH DATABASE is disallowed (safety — would bypass read-only mode).
- Blob columns (BLOB type) are returned as base64 strings.
