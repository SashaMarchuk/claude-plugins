# Connector: jsonl
Source type: JSON Lines file(s) — one JSON object per line (`.jsonl`, `.ndjson`, or `.log` with JSON events).
Authentication: None — direct file access.

## enumerate
Glob over `config.source.root` with `include: ["**/*.jsonl", "**/*.ndjson"]` (or custom).
Return: JSON array of absolute paths to `.jsonl` files.

## sample_schema
```bash
head -n <N> "$file" | jq -s 'map(to_entries | map(.key)) | flatten | unique'
```
For each key, sample the type via `jq 'map(.[<key>] | type) | unique'`.
Compute null rate: proportion of sampled lines where the key is missing or null.
Return: `{"unit": "<path>", "line_count_sampled": N, "fields": {"<key>": {"types": ["string","null"], "null_rate": 0.12, "samples": [...]}}}`.

## execute_query
Query-spec shape: `{op: "filter|aggregate|count", file: "<path>", jq_filter: "<expression>", limit?: N}`.

Dispatch:
- `filter` → `jq -c '<expression>' <file> | head -n <limit>`.
- `aggregate` → `jq -s '<expression>' <file>` (slurps entire file — limit by topic budget).
- `count` → `jq -c 'select(<predicate>)' <file> | wc -l`.

Each line of output = one row. Compute `result_hash = sha256` over the concatenated output.
Return: `{"rows": [...], "row_count": N, "result_hash": "..."}`.

## resolve_refs
JSONL events are typically self-contained. Default: pass-through.
Optional: if events contain `ref_id` fields pointing to another event's `id`, build an in-memory index on first resolve call and look up on subsequent calls.

## citation_anchor
Format: `[ROW:<relative-path>:<line-num>]`.
Example: `[ROW:events-2026-04.jsonl:1234]`.
Line numbers are 1-based.

## forbidden_fields
From config.yaml `source.forbidden_fields`.
Adapter-detected via key-name heuristic:
- `(?i)(email|password|token|api_key|session|authorization|phone|ssn)`
Return: `[{"path_or_pattern": "user.email", "disposition": "redact"}, ...]`.

## Budget constraints
- Max file size for aggregation: 500 MB (anything larger → split before analysis).
- Per-query `jq` timeout: 60s (`timeout 60 jq ...`).
- Row cap per filter result: 10,000 (use tighter jq predicates to narrow).

## Known limitations
- Multi-line JSON values (pretty-printed across lines) are NOT supported — this connector assumes one object per line.
- Malformed lines: adapter logs a warning to stderr and skips them; does not halt the query.
- Compressed `.jsonl.gz` support: add `zcat "$file" | jq ...` variant in a derived connector if needed.
