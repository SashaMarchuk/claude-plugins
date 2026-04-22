# Connector: http-api
Source type: HTTP REST API (any JSON-over-HTTP service — GitHub, Jira, custom internal APIs, etc.).
Authentication: bearer token or API key via env var (`$API_TOKEN` by convention — rename per service). NEVER hardcode credentials in this file.

## enumerate
Call the listing endpoint declared in config.yaml (`source.list_endpoint`). Use WebFetch or `curl -s -H "Authorization: Bearer $API_TOKEN" <url>`.
Paginate if the API uses cursor or page-number pagination (respect `source.pagination_style`).
Return: JSON array of resource identifiers (e.g. repo full-names, issue numbers, record IDs).

Example for GitHub:
```bash
gh api --paginate "users/$GH_USER/repos" --jq '[.[].full_name]'
```

## sample_schema
Call the detail endpoint for ONE representative unit (`source.detail_endpoint_pattern` with the unit id substituted). Inspect the response JSON:
- Field names and types (via `jq 'map_values(type)'`)
- Null rates (sample N units, count nulls per field)
- Nested structures flagged as `object` or `array`

Return: `{"unit": "<id>", "fields": {...}, "sample_size": N}`.

## execute_query
Query-spec shape: `{op: "get|list|filter", endpoint: "<path-template>", params?: {...}, jq_filter?: "<expression>", limit?: N}`.

Dispatch:
- `get` → call the templated endpoint, return full response.
- `list` → call a listing endpoint with query params (`?state=open&labels=bug`), paginate if needed.
- `filter` → `list` + apply `jq_filter` client-side on the aggregated response.

Rate limiting: respect `X-RateLimit-Remaining` headers. If below 10, sleep 30s. If hit `429`, exponential backoff (10s, 30s, 60s) up to 3 attempts.

Return: `{"rows": [...], "row_count": N, "result_hash": "<sha256>", "pagination_info": {...}}`.

## resolve_refs
API responses often contain URL refs (`author_url`, `related_issues_url`, etc.). If topic query explicitly requests ref resolution:
1. Extract all `*_url` fields from rows.
2. Batch-fetch up to `config.source.max_ref_fetches` (default 50).
3. Inline resolved objects under a `__resolved` sibling key.
Otherwise pass-through unchanged.

## citation_anchor
Format: `[URL:<canonical-endpoint-path>]`.
Example: `[URL:repos/anthropics/claude-code/issues/42]`.
Use the API's canonical path (not full URL) for portability across environments (staging/prod).

## forbidden_fields
Static list from config.yaml `source.forbidden_fields` (e.g. `access_token`, `api_key`, `client_secret`, user PII fields).
Adapter-detected:
- Any header value starting with `Bearer ` or `Basic ` must be redacted before logging.
- Fields matching `(?i)(token|secret|key|password|authorization)` by name.
Return: `[{"path_or_pattern": "access_token", "disposition": "redact"}, ...]`.

## Budget constraints
- Per-request timeout: 15 seconds (most APIs).
- Total requests per run cap: `config.source.max_api_calls` (default 5,000).
- Pagination depth cap: 50 pages (use tighter filters if exceeded).
- Respect Retry-After headers unconditionally.

## Known limitations
- GraphQL endpoints are not directly supported — if source is GraphQL, pre-transform queries via `gh api graphql` or a custom wrapper before passing to execute_query.
- OAuth flows with PKCE must complete BEFORE the pipeline starts — this connector expects a ready-to-use token in env.
- Webhook/streaming APIs are not in scope — use the http-api connector for REST poll endpoints only.
