---
name: analyze-unit
description: Execute ONE already-claimed topic file. Runs its queries via the universal connector, writes findings, invokes validator, releases topic. Self-contained — no conversation history assumed. Called by launch-terminal.sh in parallel subprocesses.
allowed-tools: Bash, Read, Write, Glob, Skill
---

# Role
TOPIC ANALYZER worker. One topic, then exit. No internal loop.

# Invocation
  /ultra-analyzer:analyze-unit <absolute-path-to-claimed-topic>

The topic file is at `<run-path>/topics/in-progress/TNNN__...md` — already claimed by claim.sh.

# Protocol

## Step 1: Read the topic
Use Read tool. Verify all required sections exist:
- Hypothesis, Collections/Units touched, Fields used, Fields FORBIDDEN, Queries, Expected output, Grounding rules, Complexity, Redundancy pair.

If malformed → `release.sh <topic> requeue malformed` and exit.

## Step 2: Resolve run path and adapter
RUN_PATH = ancestor of the in-progress/ dir.
Read `<RUN_PATH>/config.yaml` for source.type. All source operations go through `bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <RUN_PATH> <op> <args>`.

## Step 3: Forbidden-field preflight
For each Query in the topic:
- Parse fields appearing in filter/match/group/sort positions (adapter-specific DSL parsing).
- Cross-check against topic's `Fields FORBIDDEN` list and the run-level `forbidden_fields.json`.
- If any forbidden field is used in a disqualifying position → `release.sh <topic> requeue forbidden-field-used` and exit.

## Step 4: Execute queries
For each query:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <RUN_PATH> execute_query '<query-spec>'
```
Respect per-complexity budget from the topic:
- S: max 3 queries, max 500 docs, max 5 min
- M: max 6 queries, max 2000 docs, max 10 min
- L: max 10 queries, max 5000 docs, max 10 min

If budget exceeded → write a PARTIAL findings file with `status: partial-budget-exceeded` and proceed to release (done). Partial findings are still usable downstream.

If adapter errors twice consecutively on the same query → release requeue with `adapter-error` and exit.

## Step 5: Resolve references
If the query result contains cross-references (IDs, paths, URLs), call:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <RUN_PATH> resolve_refs '<raw-result-json>'
```
Workers must never perform ref-chasing themselves — adapter handles it.

## Step 6: Compute the answer
Arithmetic on resolved results. Categorical bucketing by keyword-match is allowed for text analysis. NEVER assign model-based sentiment — keyword rules only. Record the rules used.

## Step 7: Write findings file
`<RUN_PATH>/findings/TNNN.md` with exact sections in order:

```markdown
# TNNN — Findings
## Topic
(copy Hypothesis line verbatim)

## Queries executed
- Query 1: <spec as executed>
  - rows: <N>
  - result hash: <sha256 of JSON-serialized result>

## Answer
<numeric + verbal. EVERY number carries [DATA:query-N returned M rows] or [DATA:<metric>=<value>] anchor>

## Top 3 quotes
1. "<≤200 chars>" [<adapter-citation-anchor>]
2. ...
3. ...

## Contradictions with hypothesis
<explicit if Answer contradicts Hypothesis; else write "None — hypothesis supported by evidence">

## Confidence
<0-1 float> — <one sentence reason>

## Metadata
- agent: <claude-model-id>
- queries_run: <N>
- docs_processed: <M>
- runtime_s: <T>
- budget_ok: <true|false>
- redundancy_pair: <paired-topic-id or none>
- status: <complete|partial-budget-exceeded>
```

Also write `<RUN_PATH>/findings/TNNN.meta.json` with the same metadata as structured JSON for later aggregation.

## Step 8: Invoke validator
Invoke via bash so the validator runs under the profile's `validator_model` (NOT a Skill-tool invocation, which would inherit the worker's model and defeat cross-model hallucination detection):

```bash
VALIDATOR_MODEL=$(jq -r '.profile.validator_model // "haiku"' <RUN_PATH>/state.json)
claude --plugin-dir ${CLAUDE_PLUGIN_ROOT} --model "$VALIDATOR_MODEL" --print "/ultra-analyzer:validate-finding <RUN_PATH>/findings/TNNN.md"
```

Wait for the validator to write `<RUN_PATH>/validation/findings/TNNN.json` with PASS or FAIL.

## Step 9: Route based on verdict
Read validator verdict. Extract retry count from topic filename (count of `__retry-N-` substrings).

- **PASS**:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/bin/release.sh <topic> done
  bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh inc <RUN_PATH> .counters.findings_passed
  ```
- **FAIL**:
  - If retry count < 3:
    ```bash
    bash ${CLAUDE_PLUGIN_ROOT}/bin/release.sh <topic> requeue <reason-from-validator>
    ```
    (findings_passed NOT incremented; topic returns to pending/ for another attempt)
  - If retry count >= 3:
    ```bash
    bash ${CLAUDE_PLUGIN_ROOT}/bin/release.sh <topic> failed
    bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh inc <RUN_PATH> .counters.findings_failed
    ```

## Step 10: Append to run.log
release.sh already appends a JSONL entry. If your path took custom routing (partial-budget, adapter-error), also emit an explicit line.

## Step 11: Exit cleanly

# Hard rules
- Never invent field or unit names. Unknown field → requeue with `hallucinated-field`.
- Never bypass the forbidden-field preflight.
- Never exceed budget — if you hit the ceiling, write partial + release.
- Every numeric claim in findings MUST carry a [DATA:...] anchor. No exceptions.
- Every quote MUST carry an adapter-specific citation anchor (e.g. [DOC:coll._id=hex], [FILE:path:line], [URL:...], [PAGE:pdf:n]).
- No conversation history assumed — the topic file + adapter is your only context.
- Never call /ultra from inside a worker. Ultra is for gates only.
