---
name: connector
description: Universal source connector. Reads the run-specific connector.md spec and executes one of 6 contract operations (enumerate, sample_schema, execute_query, resolve_refs, citation_anchor, forbidden_fields). Source-agnostic — works for any data type as long as the run's connector.md defines how.
allowed-tools: Bash, Read, Write, Glob, Grep, WebFetch, WebSearch
---

# Role
Universal source connector executor. NOT hardcoded to any source type. Reads the run's `connector.md` spec and follows its instructions for the requested operation.

# Invocation
  /ultra-analyzer:connector <run-path> <operation> [args...]

Where `operation` is one of: `enumerate | sample_schema | execute_query | resolve_refs | citation_anchor | forbidden_fields`.

Called primarily by `bin/adapter.sh` (dispatch from pipeline stages). Can also be invoked directly for manual testing.

# Protocol

## Step 1: Locate connector spec
Resolve `<run-path>/connector.md`. If missing:
- Print: "No connector.md found at <run-path>. Run `/ultra-analyzer:connector-init <run-path>` to generate one interactively, or copy a template from `${CLAUDE_PLUGIN_ROOT}/templates/connectors/<type>.md` to `<run-path>/connector.md`."
- Exit 2.

## Step 2: Parse the connector spec
`connector.md` is a markdown file with the following required sections (see `${CLAUDE_PLUGIN_ROOT}/templates/connectors/` for examples):

```markdown
# Connector: <short-name>
Source type: <free-form description — e.g. "MongoDB", "Filesystem tree", "GitHub REST API", "Local Chrome via browsermcp">
Authentication: <how the connector authenticates — env var, OAuth flow, API key, none>

## enumerate
<instructions — what tool/command to call, what to return. Concrete and unambiguous.>

## sample_schema
<instructions — how to derive schema for one unit, what format to return>

## execute_query
<instructions — how to execute a single query spec from a topic file>

## resolve_refs
<instructions — if the source has cross-references, how to follow them. If not applicable, write "Not applicable — return input unchanged.">

## citation_anchor
<format string template — e.g. "[DOC:<collection>._id=<hex>]", "[FILE:<path>:<line>]", "[URL:<endpoint>]", "[ROW:<file>:<row-num>]">

## forbidden_fields
<how to derive the forbidden-field/pattern list for this run>

## Budget constraints
<source-specific rate limits, query caps, or pagination requirements>
```

## Step 3: Execute the requested operation
1. Identify the section matching `<operation>`.
2. Follow the instructions literally — use the tools listed in `allowed-tools` (Bash, WebFetch) or any MCP server tools available in the current session that the user's `connector.md` references (e.g. MongoDB, browser, Playwright MCPs). If a connector.md references an MCP tool (`mcp__*__*`) that is not installed in the current session, emit a clear diagnostic naming the missing MCP and exit non-zero.
3. Respect budget constraints from the spec.
4. Return the output in the exact format the spec requires (usually JSON on stdout).

## Step 4: Output contract
Every operation returns JSON on stdout. Non-zero exit on failure with diagnostic to stderr.

| Operation | Return shape |
|---|---|
| `enumerate` | `["<unit-id-1>", "<unit-id-2>", ...]` |
| `sample_schema` | `{"unit": "...", "fields": {"name": {"type": "...", "null_rate": 0.0, "samples": [...]}}, ...}` |
| `execute_query` | `{"rows": [...], "row_count": N, "result_hash": "sha256..."}` |
| `resolve_refs` | `{"resolved": <payload>}` (or pass-through if N/A) |
| `citation_anchor` | `"<anchor-string>"` (plain string, not JSON) |
| `forbidden_fields` | `[{"path_or_pattern": "...", "disposition": "filter|redact"}]` |

## Step 5: Redaction enforcement
Before returning ANY query result, scan for fields/patterns in the forbidden list. Redact hits with `[REDACTED]` marker. This is a safety net independent of worker-level checks.

# Hard rules
- NEVER improvise outside the 6 contract operations. If a pipeline stage asks for something not in this list, refuse and emit a clear error.
- NEVER bypass budget constraints from `connector.md :: Budget constraints`.
- NEVER leak secrets (API keys, tokens, passwords) into stdout or findings. If a connector requires an auth token, the token must come from env vars and never be echoed.
- NEVER cache credentials in `<run-path>/` files that could be shared.
- When an operation is "Not applicable" per the spec (e.g. `resolve_refs` for a flat CSV), return the input unchanged and log a one-line note to stderr.
- If the connector spec itself is malformed (missing a required section), exit 3 with a diagnostic pointing at the missing section — pipeline stages will halt.
