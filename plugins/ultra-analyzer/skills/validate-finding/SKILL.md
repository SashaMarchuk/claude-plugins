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

### Step 3a — Non-empty `## Contradictions` (closes M-5)

Section presence is necessary but NOT sufficient. The `## Contradictions
with hypothesis` section MUST contain non-trivial body text. Refuse the
finding with `schema-violation: empty-contradictions` if any of the
following holds:

1. The body between `## Contradictions with hypothesis` and the next `##`
   heading is whitespace-only (zero non-blank lines).
2. The body is exactly one of the placeholder strings: `(none)`, `none`,
   `N/A`, `n/a`, `TBD`, `tbd`, `pending`, `-`.
3. The body is shorter than 20 characters of stripped, non-whitespace
   content.

The honest "no contradiction" form `None — hypothesis supported by
evidence` is permitted because it (a) exceeds 20 chars, (b) is not a bare
placeholder, (c) explicitly attests that the worker considered the
question. Workers may still write a multi-sentence contradiction
discussion; the floor is "≥20 chars and not a placeholder".

```bash
# Reference extractor:
contradictions=$(awk '
  /^## Contradictions with hypothesis/ {grab=1; next}
  /^## / && grab {grab=0}
  grab {print}
' "$FINDING_PATH" | sed 's/^[[:space:]]*$//' | grep -v '^$' || true)
stripped=$(printf '%s' "$contradictions" | tr -d '[:space:]')
case "$(printf '%s' "$stripped" | tr 'A-Z' 'a-z')" in
  ''|'none'|'(none)'|'n/a'|'tbd'|'pending'|'-')
    echo "FAIL: schema-violation: empty-contradictions" >&2
    exit_with_fail "schema-violation: empty-contradictions"
    ;;
esac
if [[ ${#stripped} -lt 20 ]]; then
  exit_with_fail "schema-violation: empty-contradictions"
fi
```

This check runs BEFORE Step 6 (contradiction-honesty heuristic). An empty
or placeholder section short-circuits the verdict to FAIL — the report
writer cannot mark a finding PASS without a substantive contradiction
discussion.

## Step 4: Anti-hallucination check
Read `<RUN_PATH>/state/schemas.json` (written by discover-topics).

For every field name referenced in the findings' Queries executed section:
- It must appear in the sampled schema for the collection/unit touched.
- EXCEPTION (deterministic late-schema rescue — closes M-6): if a field is
  NOT in schemas.json but IS in the topic's `Fields used`, call:

  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <RUN_PATH> sample_schema <unit> 500
  ```

  with TWO determinism constraints the adapter MUST honor:

  1. **Deterministic ordering.** The adapter sorts the source records by
     primary key (`_id` for Mongo, `rowid` for sqlite, mtime+path for fs)
     BEFORE taking the first 500. No `$sample`, no `ORDER BY RAND()`, no
     random shuffling. Same N + same source state = same 500 records.
  2. **Pinned cache.** First call writes the resampled schema to
     `<RUN_PATH>/state/schemas.late.json` keyed by `<unit>`. Subsequent
     calls on the SAME field+unit return the cached schema rather than
     re-sampling. The cache is invalidated only when the source's
     enumerate count changes (or `state/schemas.json` is regenerated).

  Verdict rule:
  - Field present in late-resample → check PASS-with-warning
    (`late-schema-hit`). The `late_schema_hits` array in the verdict JSON
    is sorted lexicographically so two reruns produce byte-identical
    output.
  - Field still absent → FAIL with `hallucinated-field: <name>`.

  Same inputs (same finding, same source state) → same verdict on every
  invocation. No LLM-feel scoring, no probabilistic rescue.

For every unit (collection/file/URL/page) referenced: it must appear in the adapter's enumeration. If not → FAIL with `hallucinated-unit: <id>`.

## Step 5: Forbidden-fields check
Read `<RUN_PATH>/state/forbidden_fields.json`.
Parse each Query in the findings to identify fields in filter/match/group/sort positions. Any forbidden field in a disqualifying position → FAIL with `forbidden-field-used: <name>`.

### Step 5a — Alias resolution (closes H-5)

Naive name-match is insufficient. A query can introduce an alias for a
forbidden field via a computed projection, then reference the alias in a
disqualifying position. The validator MUST track aliases and treat the alias
as equivalent to its source expression for the duration of the query.

**MongoDB pipeline DSL.** Build an alias table by walking pipeline stages in
order:
- `{$addFields: {<alias>: "$<expr>"}}` → record `<alias> -> <expr>`.
- `{$set: {<alias>: "$<expr>"}}` → same as `$addFields`.
- `{$project: {<alias>: "$<expr>"}}` → record alias when value is a `$`-prefixed field reference.
- `{$group: {_id: "$<expr>", <alias>: {<accumulator>: "$<expr>"}}}` → record `<alias> -> <expr>` for each accumulator value.
- `{$lookup: {as: "<alias>", localField: "<f>", foreignField: "<g>"}}` → alias resolves to a join with the foreign collection's documents; do NOT mark the join target as a free pass.

After building the alias table, when checking `$match`, `$group._id`, or
`$sort` keys: if a key matches an alias, REPLACE it with the alias's source
expression and re-check the substituted expression against the forbidden
list. Repeat until fixed point (alias chains are allowed).

EXAMPLE (MUST FAIL):
```
[
  {$addFields: {e: "$users.email"}},
  {$group: {_id: "$e"}}
]
```
Even though `_id` literally references `$e`, alias resolution maps
`e -> users.email`, and `users.email` is in `forbidden_fields.json`. FAIL
with `forbidden-field-used: users.email (via alias 'e')`.

**SQL DSL** (sqlite, postgres, etc.). Build alias table from `SELECT`
clause:
- `SELECT <expr> AS <alias>, ...` → record `<alias> -> <expr>`.
- `SELECT <col>, ...` (no AS) → no alias entry, column resolves to itself.
- Subqueries / CTEs introduce a nested scope; alias tables stack.

When checking `WHERE`, `GROUP BY`, `HAVING`, `ORDER BY`: if the referenced
identifier is an alias, substitute its source expression and re-check.

EXAMPLE (MUST FAIL):
```
SELECT email AS x FROM users GROUP BY x
```
`x` is an alias for `email`; if `users.email` is forbidden, FAIL with
`forbidden-field-used: users.email (via alias 'x')`.

**Other DSLs** (jsonl jq filters, http-api response paths, browser DOM
selectors). Use the same general principle: any computed projection that
re-binds a forbidden source under a new name must be resolved and the
substituted source re-checked. If the connector lacks a defined alias
syntax, the absence-of-alias is itself a check that MUST be documented in
the connector spec — otherwise the validator treats any `as` / `AS` /
`addFields` / `set` keyword in the query string as a flag for manual review.

### Step 5b — Forbidden-field check fixed-point loop

```
forbidden = load_set(<RUN_PATH>/state/forbidden_fields.json)
aliases   = build_alias_table(query, dsl)
for key in disqualifying_positions(query):
    expr = key
    while expr in aliases:
        expr = aliases[expr]
    if expr in forbidden or any_forbidden_substring(expr, forbidden):
        FAIL: forbidden-field-used: <expr> (via alias '<key>') if key != expr
        FAIL: forbidden-field-used: <expr>                       otherwise
```

The `any_forbidden_substring` step also catches dotted refs (e.g.
`users.email` substring in `$users.email`) so the dollar-prefix or table-
qualified forms still match. Document any false-positives the rule produces
in the run's `state/forbidden_fields_review.md` for human triage rather
than silently bypassing the check.

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
