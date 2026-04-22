---
name: connector-init
description: Interactively generate a custom connector.md for a run by interviewing the user about their data source. Use when no template fits (e.g. a proprietary API, a custom on-disk format, a browser-driven extraction).
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Role
Socratic interview → generates `<run-path>/connector.md` tailored to the user's source. Use when templates in `${CLAUDE_PLUGIN_ROOT}/templates/connectors/` don't match.

# Invocation
  /ultra-analyzer:connector-init <run-path>

# Protocol

## Step 1: Pre-flight
- Verify `<run-path>/state.json` exists (run is initialized).
- If `<run-path>/connector.md` already exists, ask: overwrite, or keep existing?

## Step 2: Interview (use AskUserQuestion)

Ask these questions one at a time, in order. Each answer shapes subsequent questions.

**Q1: Source category**
- What kind of data source are you analyzing?
  Options: database (Mongo/Postgres/SQLite/etc.) | filesystem (files on disk) | HTTP API (REST/GraphQL) | browser (scraping/automation) | streaming (logs, Kafka) | archive (tarball, zip of structured files) | custom/other

**Q2: Access mechanism**
- How does the pipeline connect to this source?
  - If database: connection string (env var name?) or MCP tool name?
  - If API: base URL, auth mechanism (bearer token? OAuth? API key header?)
  - If filesystem: root path, file globs?
  - If browser: playwright-persistent MCP, or browsermcp MCP, or CLI tool?
  - If custom: describe the CLI / library / process that reads it

**Q3: Unit of analysis**
- What is a single "unit" in this source?
  - Database: a collection/table
  - Filesystem: a file (or a directory)
  - API: an endpoint or a resource collection
  - Browser: a page or a DOM subtree
  - Streaming: a log file or a time window
- Listen for: is there a natural iteration that produces discrete units?

**Q4: Schema introspection**
- How do you discover the shape of a unit without loading it fully?
  - Database: `db.<coll>.findOne()` or `get_schema` MCP tool
  - Filesystem: read first N bytes, detect format by extension
  - API: call the endpoint once and inspect response shape
  - Browser: navigate + DOM sample
  - Custom: the user's introspection approach

**Q5: Query execution**
- Given a topic's query spec (a JSON blob describing what to look for), how do you run it?
  - This is the 80% of the work. Probe for: what query DSL does the source speak? Aggregation pipeline? SQL? regex? CSS selectors? XPath?

**Q6: Cross-references**
- Does a query result typically contain references (IDs, URLs, paths) that need to be followed to get the full picture?
  - Yes → how? (`$lookup`, follow-up HTTP calls, symlink resolution)
  - No → resolve_refs is a pass-through.

**Q7: Citation format**
- When the final report quotes a datum, what's the canonical "where this came from" anchor?
  - Examples: `[DOC:users._id=abc123]`, `[FILE:src/auth.ts:42]`, `[URL:api.github.com/repos/foo]`, `[ROW:log.jsonl:1234]`.
  - The anchor must be unambiguous AND parseable (validator checks it).

**Q8: Sensitive/forbidden data**
- What fields, patterns, or values must NEVER leak into findings?
  - Examples: passwords, API keys, PII (emails, phone), PCI data.
  - Static list? Regex patterns? Config-driven?

**Q9: Rate limits / budget**
- Any per-query or per-run limits?
  - API rate limits (requests per second/minute)
  - DB query cost ceilings
  - File size limits
  - Browser page-load ceilings

**Q10: Auth secrets**
- Confirm: are secrets (tokens, passwords) stored in env vars and NEVER in committed files?
  - If the user hasn't set this up yet, stop and guide them to do so before proceeding.

## Step 3: Synthesize connector.md
Based on answers, write `<run-path>/connector.md` with:
- All 6 operation sections filled in with concrete, runnable instructions
- Source type, auth mechanism, budget constraints declared upfront
- A "Known limitations" section listing any answers that were uncertain

Reference the templates in `${CLAUDE_PLUGIN_ROOT}/templates/connectors/` as style guides — follow their section structure and specificity level.

## Step 4: Smoke-test
Immediately after writing, attempt `enumerate`:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <run-path> enumerate
```
If it returns a non-empty list → connector is viable. If it errors, show the error and offer to revise the spec.

## Step 5: Print summary
```
✓ Generated connector.md at <run-path>/connector.md
  Source: <one-line description>
  Smoke test (enumerate): <PASS/FAIL with detail>
  
Next: proceed to /ultra-analyzer:run (Gate 1 will review the connector).
```

# Hard rules
- NEVER write auth tokens into connector.md. Always reference env vars (e.g. `$MY_API_TOKEN`).
- NEVER guess answers. If the user is unsure about a question, mark the section "TODO: clarify before first real run" and flag it to the user.
- NEVER skip the smoke test. A connector that can't enumerate is useless downstream.
- If the user describes a source so exotic none of the 6 operations cleanly apply, be honest: "This source may not fit the pipeline's contract. Consider preprocessing to a supported shape (e.g. dump to JSONL first), or extending the contract via docs/EXTENDING-SOURCES.md."
