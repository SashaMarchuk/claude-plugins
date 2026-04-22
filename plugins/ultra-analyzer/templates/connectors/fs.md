# Connector: fs
Source type: Filesystem tree (any files on disk — code, docs, logs, JSON, CSV, etc.).
Authentication: None — read-only access to local filesystem.

## enumerate
Use the Glob and find tools to expand `config.source.root` + `config.source.include` globs, subtract `config.source.exclude`, filter by `config.source.max_file_size_kb`.
Return: JSON array of absolute file paths.

Example command sketch:
```bash
for g in <include-globs>; do
  find "$root" -path "$g" -type f -size -"${max_kb}k"
done | grep -v -E "<exclude-patterns>" | jq -R -s 'split("\n") | map(select(length>0))'
```

## sample_schema
Detect content type by extension:
- `.md`, `.txt`, `.rst`: plain text. Fields: `line_count`, `avg_line_length`, `section_headers` (from `##` markdown headers).
- `.log`: line-oriented. Fields: `line_count`, `avg_line_length`, `detected_timestamp_format`.
- `.json`: `jq 'keys'` on top-level (or `.[0] | keys` if array).
- `.jsonl` / `.ndjson`: sample first K lines, merge keys.
- `.csv` / `.tsv`: header row + `csvkit` type inference on first 100 rows.
- `.yaml` / `.yml`: top-level keys.
- Binary / unknown: mark as `unknown-binary`, do not include in queries.

Return: `{"unit": "<abs-path>", "type": "<detected>", "fields": {...}, "size_bytes": N}`.

## execute_query
Query-spec shape: `{op: "grep|count|read_file|enumerate_filtered", pattern?: "<regex>", path_filter?: "<glob>", context?: N, line_range?: [start,end], file?: "<abs-path>"}`.

Dispatch:
- `grep` → use Grep tool with `output_mode: "content"`, `-n: true`, `-C: context`, `glob: path_filter`.
- `count` → Grep tool with `output_mode: "count"`.
- `read_file` → Read tool with `offset/limit` from line_range.
- `enumerate_filtered` → re-run enumerate with stricter filters.

Each match returns: `{file, line, content, context_before, context_after}`.
Compute `result_hash = sha256(JSON.stringify(matches))`.
Return: `{"rows": [...], "row_count": N, "result_hash": "..."}`.

## resolve_refs
Default: **NOT APPLICABLE** — filesystem content is usually terminal. Return input unchanged.

Optional (only if `config.source.resolve_refs: true`):
- Follow `import`/`require`/`@import`/`![[wiki-link]]` patterns to cross-include referenced file excerpts.
- Cap resolution depth at 2 hops to avoid explosion.

## citation_anchor
Format: `[FILE:<relative-path-from-root>:<line>]`.
Example: `[FILE:src/auth.ts:142]`.
Use relative paths (relative to `config.source.root`) for portability.

## forbidden_fields
For fs, "forbidden" is a list of regex patterns to redact from match content BEFORE returning.
Derive from:
1. User-declared `config.source.forbidden_patterns` in config.yaml.
2. Adapter-detected common secrets:
   - `AKIA[0-9A-Z]{16}` — AWS access key
   - `sk_live_[a-zA-Z0-9]+` — Stripe live key
   - `-----BEGIN (RSA |DSA |EC )?PRIVATE KEY-----` — PEM key block
   - `(?i)bearer\s+[a-z0-9._-]+` — Bearer tokens
   - `(?i)(password|passwd|pwd)\s*[:=]\s*['"][^'"]+['"]` — inline passwords
Return: `[{"path_or_pattern": "<regex>", "disposition": "redact"}, ...]`.

Workers must replace matched content with `[REDACTED-SECRET]` before writing findings.

## Budget constraints
- Per-file read cap: 100 KB (Grep/Read handle larger but findings should excerpt).
- Per-query match cap: 500 matches (use `head_limit` on Grep tool).
- Total enumerate result cap: 10,000 files (tighten `include`/`exclude` globs if exceeded).

## Known limitations
- Adapter is READ-ONLY. Never writes to `config.source.root`.
- Symlinks outside `config.source.root` are not followed (path sanitization).
- Binary file contents are not analyzed — only metadata (size, type).
