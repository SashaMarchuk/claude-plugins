# Extending: Add a New Source

The pipeline is source-agnostic. Adding support for a new data source (a proprietary API, a custom on-disk format, a browser-driven extraction, etc.) does NOT require modifying plugin code. Instead, you write a `connector.md` file that tells the universal `skills/connector/SKILL.md` how to talk to your source.

Two paths: **copy-and-edit a shipped template**, or **generate one interactively**.

## Path A: Copy a shipped template

If your source is close to one we already ship a template for, this is fastest.

```bash
# In your cwd, assuming you already ran /ultra-analyzer:init <run-name>
cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/mongo.md     .planning/ultra-analyzer/<run-name>/connector.md
# or fs.md, http-api.md, browser.md, sqlite.md, jsonl.md
```

Then edit `.planning/ultra-analyzer/<run-name>/connector.md`:
- Replace placeholders (URLs, env var names, collection/table names) with your specifics
- Tune budget constraints to your rate limits
- Add source-specific forbidden patterns

Finally smoke-test:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh .planning/ultra-analyzer/<run-name> enumerate
```
A non-empty JSON array means the connector is viable.

## Path B: Generate interactively

If no template fits:

```bash
/ultra-analyzer:connector-init .planning/ultra-analyzer/<run-name>
```

The skill interviews you through 10 questions (source category, access mechanism, unit of analysis, schema introspection, query execution, refs, citation format, forbidden data, rate limits, auth secrets) and writes a tailored `connector.md`. Then it smoke-tests `enumerate` automatically.

## Connector contract — the 6 operations

Every `connector.md` MUST define six sections. The universal `skills/connector/SKILL.md` reads your file and dispatches the requested operation.

| Operation | Args | Return shape |
|---|---|---|
| `enumerate` | run config (JSON block) | JSON array of unit identifiers |
| `sample_schema` | unit id, sample_size (int) | `{"unit": "...", "fields": {"<name>": {"type": "...", "null_rate": 0.0, "samples": [...]}}}` |
| `execute_query` | topic query spec (JSON) | `{"rows": [...], "row_count": N, "result_hash": "<sha256>"}` |
| `resolve_refs` | raw result (JSON) | `{"resolved": <payload>}` or pass-through if N/A |
| `citation_anchor` | unit id | plain string (e.g. `[DOC:coll._id=hex]`, `[FILE:path:line]`, `[URL:...]`, `[ROW:file:N]`, `[PAGE:pdf:n]`) |
| `forbidden_fields` | run config | `[{"path_or_pattern": "...", "disposition": "filter|redact"}]` |

## connector.md template structure

```markdown
# Connector: <short-name>
Source type: <free-form description>
Authentication: <env var name, OAuth flow, API key, none, etc.>

## enumerate
<concrete, runnable instructions — what CLI, what MCP tool, what HTTP call>

## sample_schema
<how to probe a single unit for field shape without loading it all>

## execute_query
<how to execute a JSON query spec from a topic file — this is the 80%>

## resolve_refs
<how to follow cross-references, or "Not applicable — return input unchanged.">

## citation_anchor
<exact format the anchor must take — must be unique AND parseable>

## forbidden_fields
<how to derive the list — static from config + adapter-detected patterns>

## Budget constraints
<rate limits, pagination requirements, per-query caps>

## Known limitations
<any operation that's approximated, any edge case your spec doesn't cover>
```

See `templates/connectors/mongo.md` for the most complete example.

## Checklist before shipping a new connector

- [ ] All 6 operation sections present
- [ ] Smoke-tested: `enumerate` returns non-empty list on a known-good corpus
- [ ] Schema sampling handles nulls without crashing
- [ ] Query execution respects budget caps
- [ ] Ref resolution handles circular refs without infinite loop (or explicitly opts out)
- [ ] Citation anchors are unique AND parseable (validator checks them)
- [ ] `forbidden_fields` is non-empty for any source with PII/sensitive data
- [ ] Auth uses env vars — no secrets hardcoded in connector.md
- [ ] Tiny-corpus end-to-end test: `/ultra-analyzer:run` → Gate 1 PASS → 1 topic analyzed → synthesize

## Contributing a template upstream

If the connector is general-purpose enough that others would benefit, contribute the tested `connector.md` as a new template:

```bash
cp .planning/ultra-analyzer/<run-name>/connector.md ${CLAUDE_PLUGIN_ROOT}/templates/connectors/<type>.md
```

Then update `README.md` directory layout to list the new template.

## Hard rules

- The universal `skills/connector/SKILL.md` is NEVER modified to support a new source. All source-specific logic lives in per-run `connector.md` files and per-type templates.
- Never add a source-type enum to `config.yaml` or `state.json` — the connector file is authoritative.
- Never leak auth tokens into `connector.md` content, topic files, findings, or the report. Tokens must resolve from env at invocation time.
- Gate 1 (`/ultra` pre-discover) reviews your `connector.md` for completeness — if it flags missing sections, fix them before running discover.
