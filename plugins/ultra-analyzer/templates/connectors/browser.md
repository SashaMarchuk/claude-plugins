# Connector: browser
Source type: Live web pages accessed via a headless browser (playwright-persistent or browsermcp MCP).
Authentication: session-based. Expect the user to have a live browser session already authenticated to the target site. Never automate login flows in this connector.

## enumerate
Accepts a seed URL list in config.yaml (`source.seed_urls`) OR a sitemap URL (`source.sitemap_url`).
If sitemap: `WebFetch` the sitemap.xml, parse URLs.
If seed URLs: return as-is.
Optional: BFS expand up to `source.crawl_depth` by following same-origin links on each fetched page.
Return: JSON array of URLs.

## sample_schema
For one representative URL:
1. Navigate via `mcp__playwright-persistent__browser_navigate` (or `mcp__browsermcp__browser_navigate`).
2. Capture DOM snapshot: `mcp__playwright-persistent__browser_snapshot` or `browser_take_screenshot` + text extraction.
3. Identify repeating structures (product cards, result items, article tiles) via heuristic: look for parent elements with ≥3 siblings of similar structure.
Return: `{"unit": "<url>", "structure": "article|listing|form|mixed", "key_selectors": ["<css>", ...], "text_length": N}`.

## execute_query
Query-spec shape: `{op: "navigate|extract|screenshot|click_and_extract", url: "...", selector?: "<css>", action?: "...", wait_for?: "<selector>"}`.

Dispatch:
- `navigate` → load URL, return status + final URL (tracks redirects).
- `extract` → `browser_snapshot` + CSS-selector extraction of matched elements' text.
- `screenshot` → `browser_take_screenshot`, return relative path to saved image.
- `click_and_extract` → click selector → wait → extract from post-click DOM (e.g. expand "more details" panels).

Return: `{"rows": [{url, selector, content, screenshot_path?}], "row_count": N, "result_hash": "..."}`.

## resolve_refs
For extracted content containing relative links (`<a href="...">`), optionally follow them up to `config.source.follow_depth` (default 0 = no follow).
If follow enabled: ensure same-origin, dedupe against already-visited URLs in this run (persist visited set in `<run-path>/state/visited-urls.json`).

## citation_anchor
Format: `[URL:<full-canonical-url>]` for page-level citations.
Format: `[URL:<full-canonical-url>#<selector>]` for selector-scoped citations (unique CSS path).
Example: `[URL:https://example.com/page#article>h1]`.

## forbidden_fields
Static list from config.yaml:
- Any logged-in user's session cookies (pipeline never writes cookies to findings).
- Personal account info visible only to logged-in user (unless explicitly allowed).
- Third-party ad/tracking pixel payloads.
Return: patterns to redact in extracted text (e.g. credit card numbers, SSN format, email addresses if PII-sensitive).

## Budget constraints
- Max pages per run: `config.source.max_pages` (default 200).
- Per-page wait: 5s max for idle (`networkidle`) before extracting.
- Screenshot cap: 50 per run (expensive both in storage and LLM vision cost).
- Respect `robots.txt` at the seed-URL origin.

## Known limitations
- Requires a user-authenticated browser session. The connector does NOT log in.
- JavaScript-heavy sites may need extended wait_for selectors — tune per site.
- Infinite-scroll pages: handle explicitly via `scroll_and_extract` query op (user extends if needed).
- Do not scrape content you lack permission to access — legal compliance is the user's responsibility.
