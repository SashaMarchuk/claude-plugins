> **This is a shipped template.** **Copy it to your run directory before editing** — direct edits to this file will be wiped on `/plugin update`. To copy:
> ```bash
> cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/<type>.md .planning/ultra-analyzer/<run-name>/connector.md
> ```

# Connector: sqlite
Source type: Local SQLite database file (.db, .sqlite, .sqlite3).
Authentication: None — direct file access via `sqlite3` CLI.

## enumerate
```bash
sqlite3 "$DB_PATH" ".tables" | tr ' ' '\n' | grep -v '^$' | jq -R -s 'split("\n") | map(select(length>0))'
```
Filter by config.yaml `source.tables` if declared (intersect with the full list).
Return: JSON array of table names.

## sample_schema
```bash
sqlite3 "$DB_PATH" "PRAGMA table_info(<table>)"
sqlite3 "$DB_PATH" "SELECT * FROM <table> LIMIT <N>"
```
Combine: column types from PRAGMA + null rates + sample values from LIMIT query.
Return: `{"unit": "<table>", "fields": {"<col>": {"type": "INTEGER|TEXT|REAL|BLOB", "null_rate": 0.0, "samples": [...]}}}`.

## execute_query
Query-spec shape: `{op: "select|count|aggregate", sql: "<full-sql-statement>"}`.
Safety: the adapter REFUSES any SQL containing `INSERT|UPDATE|DELETE|DROP|ALTER|CREATE` keywords. Read-only only.
```bash
sqlite3 -json "$DB_PATH" "<sql>"
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
- Read-only mode enforced: adapter opens with `?mode=ro` via URI filename if SQLite version supports it.

## Known limitations
- FTS (full-text search) extensions: if present, can be used in execute_query; if absent, fall back to `LIKE` which is slow on large tables.
- ATTACH DATABASE is disallowed (safety — would bypass read-only mode).
- Blob columns (BLOB type) are returned as base64 strings.
