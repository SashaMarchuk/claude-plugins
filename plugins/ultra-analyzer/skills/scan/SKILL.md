---
name: scan
description: Quick assessment of a data source BEFORE committing to a full run. Estimates unit count, size, field inventory, and suggests a connector template. Use to decide "is this worth analyzing" or "which connector fits".
allowed-tools: Bash, Read, Glob, Grep, WebFetch
---

# Role
Pre-init reconnaissance. Reads a source, produces a structured report, does NOT create a run or write persistent state.

# Invocation
  /ultra-analyzer:scan <target>

Target can be:
- A filesystem path: `/path/to/corpus` → fs-style scan
- A mongo URI or collection list: `$MONGO_URI` or `mongodb://...` → mongo scan
- An HTTP URL: `https://api.example.com/v1/things` → http-api scan
- A SQLite file: `/path/to/db.sqlite` → sqlite scan
- A glob: `**/*.jsonl` → jsonl scan
- `--auto` with cwd: detect source type from current directory contents

# Protocol

## Step 1: Detect target type
Heuristics:
- Path exists + is a directory → fs
- Path exists + is a file with .sqlite/.db/.sqlite3 → sqlite
- Path exists + is a file with .jsonl/.ndjson → jsonl
- Target starts with `mongodb://` or equals `$MONGO_URI` → mongo
- Target starts with `http://` or `https://` → http-api
- Target contains wildcards (`*`, `**`) → glob (fs)
- `--auto` → inspect cwd: if has mongo MCP configured → mongo; if has .sqlite files → sqlite; if has many .jsonl → jsonl; else fs

If ambiguous: ask the user (AskUserQuestion).

## Step 2: Run type-specific probes

### fs scan
- Count files by extension (`find <path> -type f | awk -F. '{print $NF}' | sort | uniq -c | sort -rn`)
- Total size (`du -sh <path>`)
- Largest files (`find <path> -type f -printf '%s %p\n' | sort -n | tail -10` — macOS: use `stat -f '%z %N'`)
- Sample filenames per extension
- Flag potential secrets: grep for `AKIA|sk_live|BEGIN .*PRIVATE KEY` across text files (respecting .gitignore if present)

### mongo scan
Requires a MongoDB-capable MCP server (any `mcp__*` that exposes list/count/schema operations) OR `mongosh` on PATH with `$MONGO_URI` set. If neither is available, emit a clear diagnostic naming what's missing and exit without writing.
- List collections (via the configured MCP's `list_collections` tool, or `mongosh "$MONGO_URI" --quiet --eval 'JSON.stringify(db.getCollectionNames())'`) → count
- For each collection: `count` + `sample_schema` with sample_size=50
- Flag heavy collections (>100K docs)
- Flag collections with suspected nulled/anonymized fields (>80% null rate)

### sqlite scan
- `sqlite3 <file> ".tables"` → list
- Per table: `COUNT(*)` + column list via `PRAGMA table_info`
- Flag tables with potential PII columns (column names matching PII regex)

### jsonl scan
- `wc -l` per file → total events
- `head -100 <file> | jq -s 'map(keys) | flatten | unique'` → key inventory
- Estimated schema homogeneity (fraction of sampled lines with all-expected keys)

### http-api scan
- Authenticated GET on the target URL (if `$API_TOKEN` env var set).
- Inspect response status, pagination headers, rate-limit headers, response schema.
- Flag: auth failures, rate limit exhaustion, schema version info.

## Step 3: Produce the report

Print to stdout (do NOT write files):

```
ultra-analyzer scan: <target>
Detected type: <type>
Suggested connector: ${CLAUDE_PLUGIN_ROOT}/templates/connectors/<type>.md

=== Size ===
Units (collections/files/tables/etc.): N
Total size: <human-readable>
Largest units: [...]

=== Schema inventory ===
<type-specific details>

=== Flagged concerns ===
<any concerning findings: PII, secrets, rate limits, schema drift>

=== Feasibility verdict ===
<one of: GREEN (ready to analyze) / YELLOW (analyze with caveats) / RED (preprocess first)>
Rationale: <one paragraph>

=== Suggested next steps ===
1. <concrete action>
2. <concrete action>
```

## Step 4: Offer follow-up
End with:
```
To start an analysis of this source:
  /ultra-analyzer:init <your-run-name>
  cp ${CLAUDE_PLUGIN_ROOT}/templates/connectors/<type>.md .planning/ultra-analyzer/<run>/connector.md
  # then edit config.yaml + seeds.md
```

# Hard rules
- NEVER mutate the source. scan is READ-ONLY.
- NEVER write files outside of stdout (no artifacts created — keep this skill lightweight).
- NEVER exfiltrate full content. Samples only (first N lines, first N docs). Respect forbidden_patterns when showing samples.
- If secrets are detected in an fs scan, do NOT print the literal match — print only the file:line and the classification (e.g. "AWS key pattern").
- If the source requires auth and auth is missing, stop and report clearly — do NOT prompt for credentials or store them.
