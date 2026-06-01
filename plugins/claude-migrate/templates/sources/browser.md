> **This is a shipped template.** **Copy it to your run directory before editing** - direct edits to this file will be wiped on `/plugin update`. To copy:
> ```bash
> cp ${CLAUDE_PLUGIN_ROOT}/templates/sources/browser.md .planning/claude-migrate/<run-name>/source-connector.md
> ```

# Source connector: browser (live)
Source type: A live, pre-authenticated Claude.ai session in the OLD account, read through a browser MCP (`mcp__playwright-persistent__*` preferred; CDP-over-9222, `browsermcp`, or `browser-use` as fallbacks).
Authentication: session-based. Expect a browser already logged into the OLD account. This connector NEVER automates login - no credentials, no 2FA, no captcha. If the session is not authenticated, STOP and hand off per `${CLAUDE_PLUGIN_ROOT}/references/login-policy.md`.

This is the OPTIONAL `live` source, selected at G-INPUT only when the user has no export. It has two strategies, tried in order:

1. **PREFERRED - trigger the official export.** Drive the authenticated session to `Settings -> Privacy -> Export data` and click the export button. Anthropic emails the ZIP asynchronously; the connector CANNOT wait for the email. Park the run with a handoff: "Your export was requested. When the ZIP arrives, unzip it, set `input.export_path`, and run `/claude-migrate:resume <run>`." On resume the run switches to the `export-file` source - the more reliable, lossless path.
2. **FALLBACK - live-scrape.** When the user declines or cannot use the official export, enumerate the chat/project list and snapshot the rendered turns into the SAME normalized unit shape the `export-file` source produces. This is lossier (no `extracted_content`, no token counts beyond the rendered DOM) and is the documented fallback only.

Every op is read-only against the live account. A MANDATORY secret-strip pass (below) runs after EVERY extraction and before any write - a path that returns raw HTML is non-conformant and the controller refuses its output.

## enumerate
Navigate to the chat list (and the projects list). Read the accessibility snapshot, not brittle CSS. Each chat row links to a chat URL containing the chat uuid; collect those uuids.

- `mcp__playwright-persistent__browser_navigate` to the chats URL from `selectors.json`.
- `mcp__playwright-persistent__browser_snapshot` to read the rendered list.
- Extract the uuid from each chat's href (the stable per-chat identifier).

Return: a JSON array of chat **uuids** (NOT positional indices) - MANDATORY (Universality M1), so `UNNN` is keyed identically to the export source. The `source` skill sorts ascending and assigns `UNNN`.

```json
["<uuid-a>", "<uuid-b>"]
```

## extract_unit
Open the chat by uuid, let the turns render (wait on STATE via `browser_wait_for`, not a fixed delay), snapshot the conversation, and build the normalized unit. Apply the SAME canonical text rule as `export-file`:

1. Capture each rendered human/assistant turn's visible text in order.
2. There are no `thinking`/`tool_use`/`tool_result` blocks in the rendered DOM to skip, but DO skip any collapsed tool/diagnostic UI - keep only conversational text.
3. An empty/voice/image-only turn becomes `[no text]`.
4. For any inline image, emit `[image existed: <alt-or-filename> - not in export]`; never invent its contents.
5. Run the MANDATORY secret-strip pass over the assembled text BEFORE returning.

Return the same shape as `export-file extract_unit` (`{idx, uuid, name, created_at, messages:[{sender,text}], attachments_text, image_refs, raw_token_est}`). `raw_token_est` is computed from the rendered text length (chars/4 Latin, chars/3 Cyrillic/CJK).

## extract_projects
Navigate to each project, open its instructions panel and knowledge list, snapshot them.

- `prompt_template` = the rendered Custom Instructions text.
- `knowledge_docs[]` = each project knowledge document's filename + rendered/visible content (when the content is not fully rendered, note it as truncated rather than inventing it).
- Mark any built-in starter project `is_starter: true` so the controller drops it.

Return the same shape as `export-file extract_projects`, sorted by project uuid ascending (the `source` skill assigns `PNN`). Run the secret-strip pass over instructions and docs before returning.

## unit_project_ref
The live UI DOES expose which project a chat belongs to (a chat opened inside a project shows the project handle). When that association is visible in the snapshot, return the project's `uuid`; otherwise return `null`.

```json
"<project_uuid>"
```
or `null`.

Even when a real join key is returned, GROUPED-vs-STANDALONE remains a user decision confirmed at the filter-gate (Universality C2); the connector only reports the observed association, it does not finalize grouping.

## account_check
Read the account identity surface (the account dropdown / avatar tooltip) to derive the signed-in email, hash it SHA-256, and return ONLY the hash. NEVER return or log the clear email/name/phone. Run the secret-strip pass on the snapshot before extracting.

```json
{ "verified_account_email_hash": "<sha256 hex>" }
```

If the email is not visible, return `{ "verified_account_email_hash": null }`.

## citation_anchor
Return the live URL as the provenance anchor.

Format: `[URL:<full-canonical-chat-url>]` for the chat, optionally `[URL:<url>#<turn-index>]` for a specific turn.

## forbidden_fields
A live session is the highest-PII source. The strip list MUST include every credential/secret class plus the account PII fields.

```json
[
  { "path_or_pattern": "document.cookie", "disposition": "redact" },
  { "path_or_pattern": "localStorage|sessionStorage", "disposition": "redact" },
  { "path_or_pattern": "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", "disposition": "redact" },
  { "path_or_pattern": "Bearer\\s+[A-Za-z0-9._-]+", "disposition": "redact" },
  { "path_or_pattern": "Authorization:.*", "disposition": "redact" },
  { "path_or_pattern": "csrf|_token|authenticity_token|api_key|apikey", "disposition": "redact" },
  { "path_or_pattern": "email_address|verified_phone_number|full_name", "disposition": "redact" }
]
```

The canonical `[REDACTED:*]` token set is owned by `${CLAUDE_PLUGIN_ROOT}/references/pii-policy.md`; this connector references it and never re-defines it.

## MANDATORY secret-strip pass
EVERY extraction path (`extract_unit`, `extract_projects`, `account_check`, any snapshot) MUST run this redaction pass AFTER extraction and BEFORE writing the result or returning it to the adapter. A connector that returns raw HTML without running it is non-conformant; the run controller refuses the output. The pass strips ALL of the following from any captured text or attribute:

1. **Document cookies.** Any `document.cookie =`, `document.cookie=`, `Cookie:`, `Set-Cookie:`, or `cookie=<value>;` in inline scripts, headers, or rendered text -> `[REDACTED:cookie]`. INPUT `<script>document.cookie="session=xyz123; HttpOnly"</script>` -> stored `<script>[REDACTED:cookie]</script>`.
2. **localStorage / sessionStorage.** Any `localStorage.setItem(...)`, `sessionStorage.setItem(...)`, `localStorage.<key> =`, `sessionStorage.<key> =` -> `[REDACTED:storage]`.
3. **JWT / Bearer tokens.** `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` (JWT shape) and `Bearer\s+[A-Za-z0-9._-]+` -> `[REDACTED:token]`.
4. **CSRF / API keys in hidden fields.** Any `<input type="hidden" name="(csrf|_token|authenticity_token|api_key|apikey)" value="...">` -> strip the `value` attribute.
5. **Authorization headers.** Any captured `Authorization:` header -> `[REDACTED:authz]`.
6. **Account PII.** Any signed-in email, phone, or full name -> `[REDACTED:pii]` (the hash, computed separately in `account_check`, is the only derivative allowed to persist).

Reference implementation (the connector may use a more robust DOM walker, but the SAME six categories must be stripped):

```bash
strip_secrets() {
  # `#` as the s/// delimiter so embedded `|` inside alternations does not terminate the pattern.
  perl -pe '
    s#document\.cookie\s*=\s*"[^"]*"#[REDACTED:cookie]#g;
    s#document\.cookie\s*=\s*'\''[^'\'']*'\''#[REDACTED:cookie]#g;
    s#(?:localStorage|sessionStorage)\.setItem\([^)]+\)#[REDACTED:storage]#g;
    s#(?:localStorage|sessionStorage)\.\w+\s*=\s*[^;\n]+#[REDACTED:storage]#g;
    s#eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+#[REDACTED:token]#g;
    s#Bearer\s+[A-Za-z0-9._-]+#[REDACTED:token]#g;
    s#Authorization:\s*[^\r\n]+#[REDACTED:authz]#g;
    s#Set-Cookie:\s*[^\r\n]+#[REDACTED:cookie]#g;
  '
}
```

## Budget constraints
- Per-page wait: wait on the rendered-turns state, capped, before snapshotting; do not poll forever.
- The official-export strategy is preferred precisely because live-scrape is slow and lossy; recommend it whenever an export is feasible.
- No model calls in enumeration/extraction - these are browser reads plus the deterministic strip pass.

## Known limitations
- Requires a user-authenticated session. The connector does NOT log in (`references/login-policy.md`).
- Live-scrape loses `attachments[].extracted_content` and exact token counts available only in the export; the official-export path avoids this.
- Image/binary bytes are not recoverable from the rendered DOM; the unit notes the image existed.
- Selectors drift: all UI facts live in `selectors.json` as ARIA name/role/text, never CSS paths. A UI change is a config edit.
- Do not scrape content you lack permission to access - legal compliance is the user's responsibility.
