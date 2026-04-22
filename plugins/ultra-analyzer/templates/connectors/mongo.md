# Connector: mongo
Source type: MongoDB database (or DocumentDB / Cosmos DB compatible).
Authentication: `$MONGO_URI` env var contains a full connection string including credentials. Never hardcode the URI in this file.

> **Before copying this template**: replace every `mcp__<your-mongo-mcp>__*` placeholder with the actual tool name exposed by the MongoDB MCP server you have installed in Claude Code (e.g. `mcp__mongo__list_collections`, `mcp__atlas__find`). The fallback `mongosh` path works without any MCP if `$MONGO_URI` and `mongosh` are available on your PATH.

## enumerate
Primary: use `mcp__<your-mongo-mcp>__list_collections` if the MCP tool is available in this session.
Fallback: `mongosh "$MONGO_URI" --quiet --eval 'JSON.stringify(db.getCollectionNames())'`.
Filter: if the run's config.yaml declares `source.collections: [list]` (not `[all]`), intersect with it.
Return: JSON array of collection names, e.g. `["users", "orders", "products"]`.

## sample_schema
Primary: `mcp__<your-mongo-mcp>__get_schema` with `collection=<unit-id>` and `sample_size=<N>`.
Fallback:
```bash
mongosh "$MONGO_URI" --quiet --eval "JSON.stringify(db.<unit>.aggregate([{\$sample:{size:<N>}}]).toArray())"
```
Then derive field list, types, null rates from the sample.
Return: `{"unit": "<name>", "sample_size": N, "fields": {"<fieldname>": {"type": "string|number|bool|array|object", "null_rate": 0.0-1.0, "samples": [top-5-non-null-values]}}}`.

## execute_query
Query-spec shape: `{op: "find|aggregate|count|denormalized", collection: "...", filter?: {...}, pipeline?: [...], projection?: {...}, limit?: N}`.
Dispatch:
- `find` → `mcp__<your-mongo-mcp>__find`
- `aggregate` → `mcp__<your-mongo-mcp>__aggregate`
- `count` → `mcp__<your-mongo-mcp>__count`
- `denormalized` → `mcp__<your-mongo-mcp>__get_denormalized_view` (if your MCP exposes it; otherwise use a manual `$lookup` pipeline)
Fallback (if MCP fails twice): `mongosh "$MONGO_URI" --quiet --eval "JSON.stringify(db.<coll>.<op>(<args>).toArray())"`.
Default limit if not in spec: 1000.
Return: `{"rows": [...], "row_count": N, "result_hash": "<sha256>"}`.

## resolve_refs
MongoDB uses ObjectId references. When a query result contains ObjectId or array-of-ObjectId fields pointing to other collections:
1. Collect all referenced IDs grouped by target collection.
2. Batch-fetch: `mcp__<your-mongo-mcp>__find` with `{_id: {$in: [...ids]}}` per collection.
3. Replace refs inline with fetched documents.
4. For known denormalized patterns (configured per run), prefer a denormalized-view MCP call if available.
Return: resolved payload with no unresolved refs.

## citation_anchor
Format: `[DOC:<collection>._id=<hex-objectid>]`.
Example: `[DOC:orders._id=507f1f77bcf86cd799439011]`.

## forbidden_fields
Derive from two sources, merged and deduplicated:
1. User-declared in config.yaml: `source.forbidden_fields: [users.email, users.password, ...]`.
2. Adapter-detected during schema sampling:
   - Any field with >99% null rate in the sample (likely redacted by upstream anonymization).
   - Any field whose name matches a known-PII pattern: `(?i)(email|password|token|ssn|phone|address|firstname|lastname|dob)`.
Return: `[{"path_or_pattern": "users.email", "disposition": "filter"}, ...]`.

## Budget constraints
- Default per-query timeout: 30 seconds.
- Max rows per `find` response: 1000 (pipeline caller must paginate for larger needs).
- Result payload cap: 2 MB (adapter refuses to return larger — caller must add `$limit` or `$project`).
- If the topic budget (from `## Complexity:`) exceeds these defaults, the adapter enforces the MINIMUM of topic budget and adapter defaults.

## Known limitations
- `mongoimport`-style bulk extraction is NOT in scope — use dedicated tooling before analysis if you need full exports.
- Transactions are NOT used — adapter does single-query reads only.
- If `$MONGO_URI` is missing AND no MCP is configured, every operation exits 4 with a clear diagnostic.
