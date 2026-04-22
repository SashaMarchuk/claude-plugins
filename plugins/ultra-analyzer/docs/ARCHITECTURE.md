# Architecture

## Pipeline stages (linear, resume-able)

```
init → [GATE 1: /ultra] → discover → analyze (parallel) → validate (per finding)
     → [GATE 2: /ultra] → synthesize → DONE
```

Each arrow represents a state transition recorded in `state.json`. A kill at any point leaves the run resumable via `/ultra-analyzer:resume`.

## state.json contract

Single source of truth. Located at `<cwd>/.planning/ultra-analyzer/<run>/state.json`.

```json
{
  "run": "my-analysis",
  "created_at": "2026-04-16T14:00:00Z",
  "updated_at": "2026-04-16T15:23:00Z",
  "connector_hint": "mongo | fs | http-api | browser | sqlite | jsonl | custom",
  "config_path":    ".planning/ultra-analyzer/my-analysis/config.yaml",
  "seeds_path":     ".planning/ultra-analyzer/my-analysis/seeds.md",
  "connector_path": ".planning/ultra-analyzer/my-analysis/connector.md",
  "current_step": "init | pre-discover-gate | discover | analyze | pre-synthesize-gate | synthesize | done | failed",
  "status": "pending | running | blocked | passed | failed",
  "profile": {
    "tier": "large",
    "ultra_gate_tier": "--large",
    "worker_model": "sonnet",
    "worker_model_complexity_S": "haiku",
    "validator_model": "haiku",
    "synthesizer_model": "opus",
    "topic_target_min": 45,
    "topic_target_max": 70,
    "redundancy_pair_rate_p1": 0.60,
    "suggested_parallel_terminals": "3-5"
  },
  "ultra_gates": {
    "pre-discover":   {"verdict": "PASS | FAIL | pending", "report": "path/to/gate1.md"},
    "pre-synthesize": {"verdict": "PASS | FAIL | pending", "report": "path/to/gate2.md"}
  },
  "counters": {
    "topics_total":     60,
    "topics_done":      42,
    "topics_failed":    2,
    "topics_pending":   16,
    "findings_passed":  40,
    "findings_failed":  2
  },
  "last_checkpoint": ".planning/ultra-analyzer/my-analysis/checkpoints/2026-04-16T15-23-00.json"
}
```

## Connector contract (source-agnostic)

Source type is NOT hardcoded. Each run has a `connector.md` file describing how to talk to its specific data source. The universal `skills/connector/SKILL.md` reads that file and executes the 6 required operations.

Every `connector.md` MUST define six sections:

| Operation | Input | Output |
|---|---|---|
| `enumerate` | run config | JSON list of unit identifiers (collections, files, pages, endpoints) |
| `sample_schema` | unit id, sample_size | JSON schema: field names, types, null rates, sample values |
| `execute_query` | query spec from topic | `{rows, row_count, result_hash}` |
| `resolve_refs` | raw result with cross-refs | resolved payload (or pass-through if N/A) |
| `citation_anchor` | unit id | string like `[DOC:coll._id=hex]`, `[FILE:path:line]`, `[URL:...]`, `[ROW:file:line]`, `[PAGE:pdf:n]` |
| `forbidden_fields` | run config | JSON list `[{path_or_pattern, disposition: filter|redact}]` |

Six shipped templates live at `templates/connectors/`: `mongo.md`, `fs.md`, `http-api.md`, `browser.md`, `sqlite.md`, `jsonl.md`. User copies one and edits, OR generates a custom one via `/ultra-analyzer:connector-init`.

Pipeline stages call the connector via `bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter.sh <run-path> <op> <args>` which routes every operation to the universal `/ultra-analyzer:connector` skill. `adapter.sh` itself is source-agnostic — the connector.md file determines actual behavior.

## Topic file contract (unchanged from TDE)

Every topic is a self-contained markdown file workers execute without conversation history:

```markdown
## Hypothesis
(one testable statement)

## Collections touched
- ...

## Fields used — VERIFIED present
- ...

## Fields FORBIDDEN in query logic
(adapter-supplied list)

## Queries to run
- Query 1: <adapter-specific DSL>

## Expected output
(findings file schema)

## Grounding rules
(evidence anchor format, enforced by validator)

## Complexity: S | M | L
(budget tier — max runtime, max queries, max docs)
```

## Findings file contract

```markdown
# TNNN — Findings
## Topic
(copy of hypothesis)
## Queries executed
(each with exact spec + row count + result hash)
## Answer
(numeric + verbal, every number carries [DATA:...] anchor)
## Top 3 quotes
(≤200 chars each with source anchor)
## Contradictions with hypothesis
(explicit if answer contradicts)
## Confidence
(0-1 with one-sentence reason)
## Metadata
(agent, queries, runtime_s, budget_ok, redundancy_pair)
```

## Validation contract

Per-finding checks (adapter-agnostic):
1. **Grounding**: every numeric claim has evidence anchor
2. **Schema**: all required sections present in correct order
3. **Anti-hallucination**: every field/unit referenced verifiably exists (adapter-verified)
4. **Forbidden fields**: no banned field appears in filter/group/sort
5. **Contradiction honesty**: if answer contradicts hypothesis, a Contradictions section exists

Validator writes `validation/findings/TNNN.json` with verdict PASS/FAIL and per-check details.

## Synthesis contract

Opus-only. Inputs: all PASS findings + manifest. Outputs: `synthesis/REPORT.md`.

Required sections:
- §0 Evidence bases (denominator accounting per subset)
- Executive summary
- Top-N compelling findings with narrative + quotes
- P1/P2/P3 sections
- Curated quotes
- Divergent findings requiring human review
- Honest-ambiguity statement
- Audit-trail paragraph
- Appendices (topics run, failed, coverage)

Triangulation on redundancy pairs: REPLICATED / DIRECTION-CONFIRMED-MAGNITUDE-UNCERTAIN / DIVERGENT. Divergent pairs are flagged, never averaged.

## Concurrency model

Workers are launched as independent `claude --print` subprocesses via `bin/launch-terminal.sh`. Multi-terminal parallelism is user-driven: open N terminals, each runs `bash bin/launch-terminal.sh <run-path>`, claim races resolved by mkdir-based atomic lock in `bin/claim.sh` (portable, works on macOS without `flock`). Counter updates in `state.json` also use mkdir locking via `bin/state.sh inc`.

Workers are wrapped in `timeout` (or `gtimeout` on macOS with coreutils installed) to kill runaway workers. Default per-worker ceiling: 1800s, override with `ULTRA_ANALYZER_WORKER_TIMEOUT_S` env var.

No MCP-internal sub-agents inside pipeline stages. `/ultra` swarm is invoked ONLY at the two gates.

## Bash script invocation

When the plugin is loaded via `--plugin-dir` or installed, the `bin/` directory is added to the Bash tool's `PATH`. Skills invoke helpers either by bare name (`state.sh ...`) or via absolute path (`bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh ...`). Both work; bare names are preferred for portability across installation mechanisms.

## bin/ script inventory

| Script | Purpose |
|---|---|
| `state.sh` | state.json CRUD + atomic counter increments |
| `claim.sh` | atomic topic claim (pending → in-progress) |
| `release.sh` | topic outcome routing (done/failed/requeue from in-progress) |
| `requeue.sh` | Gate-2 requeue (done → pending, with counter correction and archival) |
| `launch-terminal.sh` | per-terminal worker loop with timeout wrapper |
| `adapter.sh` | dispatches every operation to the universal `/ultra-analyzer:connector` skill, which reads `<run>/connector.md` |
