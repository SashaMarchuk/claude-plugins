---
name: validate-finding
description: Validate a single findings file against grounding, schema, anti-hallucination, forbidden-fields, and contradiction-honesty checks. Runs on a DIFFERENT model than the worker to prevent hallucination capture.
model: haiku
allowed-tools: Bash, Read, Write
---

# Role
Verify one findings file. Never re-runs queries — checks internal consistency and cross-references against the topic spec and run-level schema dictionary.

# Invocation
  /ultra-analyzer:validate-finding <absolute-path-to-findings-file>

# Protocol

## Step 1: Resolve paths
FINDING_PATH = `<arg>`
TNNN = basename without extension
RUN_PATH = resolve by walking up from findings/TNNN.md to the run root
TOPIC_PATH = `<RUN_PATH>/topics/in-progress/<name-pattern-matching-TNNN>.md` (or done/ if already released)

## Step 2: Grounding check
For every numeric claim in the Answer section, require a `[DATA:...]`, `[DOC:...]`, `[FILE:...]`, `[URL:...]`, `[PAGE:...]`, `[AGENT:...]`, or `[HYPOTHESIS: no evidence located]` anchor within the same sentence or the immediately following parenthetical.

Unanchored numeric claim → check FAILED with reason `ungrounded-number`.

For quotes: require a citation anchor adjacent to each quote.

## Step 3: Schema check
Required sections in order:
Topic, Queries executed, Answer, Top 3 quotes, Contradictions with hypothesis, Confidence, Metadata.

Missing or out-of-order section → check FAILED with reason `schema-violation: <section>`.

## Step 4: Anti-hallucination check
Read `<RUN_PATH>/state/schemas.json` (written by discover-topics).

For every field name referenced in the findings' Queries executed section:
- It must appear in the sampled schema for the collection/unit touched.
- EXCEPTION: if a field is NOT in schemas.json but IS in the topic's `Fields used`, call `bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <RUN_PATH> sample_schema <unit> 500` to re-sample. If field appears in re-sample → check PASS-with-warning (`late-schema-hit`). If still absent → FAIL with `hallucinated-field: <name>`.

For every unit (collection/file/URL/page) referenced: it must appear in the adapter's enumeration. If not → FAIL with `hallucinated-unit: <id>`.

## Step 5: Forbidden-fields check
Read `<RUN_PATH>/state/forbidden_fields.json`.
Parse each Query in the findings to identify fields in filter/match/group/sort positions (adapter-specific DSL — use the same parser as discover-topics). Any forbidden field in a disqualifying position → FAIL with `forbidden-field-used: <name>`.

## Step 6: Contradiction-honesty check
If the Answer section directly contradicts the Hypothesis (sign flipped, magnitude >2x off, etc.) AND the Contradictions section says "None" → FAIL with `dishonest-contradiction`.

Simple heuristic: if Hypothesis claims "X is high" and Answer reports X <threshold, or Hypothesis claims a positive correlation and Answer reports negative, the Contradictions section must acknowledge the contradiction explicitly.

## Step 7: Write verdict JSON
`<RUN_PATH>/validation/findings/TNNN.json`:

```json
{
  "topic_id": "TNNN",
  "verdict": "PASS" | "FAIL",
  "checks": {
    "grounding":              {"passed": true|false, "notes": "..."},
    "schema":                 {"passed": true|false, "missing_sections": []},
    "hallucination":          {"passed": true|false, "unknown_fields": [], "late_schema_hits": []},
    "forbidden_fields":       {"passed": true|false, "violations": []},
    "contradiction_honesty":  {"passed": true|false, "notes": "..."}
  },
  "reasons_on_fail": ["<slug>", ...],
  "validator": "haiku",
  "validated_at": "<ISO>"
}
```

Verdict is PASS only if all five checks pass (late_schema_hits are warnings, not failures).

## Step 8: Exit
Print the verdict to stdout (worker parses it). Exit 0 regardless of PASS/FAIL — only exit non-zero on IO errors.

# Hard rules
- NEVER re-run queries. Validator is check-only.
- NEVER use the same model as the worker. Frontmatter hard-codes Haiku — do not change.
- Every FAIL must include a reason slug the worker can use for requeue-tagging.
- When in doubt, FAIL. A PASS that should have been FAIL contaminates downstream synthesis.
