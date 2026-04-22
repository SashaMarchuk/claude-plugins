---
name: progress
description: Show current analyzer run status in a human-readable format. Reads state.json and prints the pipeline step, counters, gate verdicts, and what the user should do next.
allowed-tools: Bash, Read
---

# Role
Read-only. Display state.json nicely. No mutations.

# Invocation
  /ultra-analyzer:progress [run-name]

If run-name omitted: auto-detect single run or list available.

# Protocol

## Step 1: Locate run
Same rules as /ultra-analyzer:run Step 1.

## Step 2: Read state
```bash
cat <RUN_PATH>/state.json | jq .
```

## Step 3: Format output

```
analyzer run: <run-name>
  created: <created_at>   updated: <updated_at>
  source:  <connector_hint>
  status:  <status>       step: <current_step>

Ultra gates:
  pre-discover:   <verdict>  [<report-path-if-any>]
  pre-synthesize: <verdict>  [<report-path-if-any>]

Counters:
  topics   total=<N>  done=<D>  failed=<F>  pending=<P>  in-progress=<IP>
  findings passed=<FP> failed=<FF>

Last checkpoint: <path>

Next action:
  <step-specific guidance — see below>
```

## Next-action guidance by current_step

| current_step | status | next action |
|---|---|---|
| init | pending | Edit config.yaml + seeds.md, then /ultra-analyzer:run |
| pre-discover-gate | pending | /ultra-analyzer:run (will invoke /ultra Gate 1) |
| pre-discover-gate | blocked | Edit config/seeds per remediation in validation/gate1-*.md, then /ultra-analyzer:run |
| discover | running | Wait for discover to complete, then /ultra-analyzer:run |
| analyze | running | Open terminals: bash ${CLAUDE_PLUGIN_ROOT}/bin/launch-terminal.sh <RUN_PATH> |
| analyze | blocked | Low PASS rate. Inspect validation/findings/*.json for patterns. Fix worker or seeds. |
| pre-synthesize-gate | pending | /ultra-analyzer:run (will invoke /ultra Gate 2) |
| pre-synthesize-gate | blocked | Revise flagged topics per validation/gate2-*.md, re-run workers, then /ultra-analyzer:run |
| synthesize | running | Wait for REPORT.md generation |
| done | passed | Read synthesis/REPORT.md |
| failed | failed | Inspect run.log |

## Step 4: Optional detail flags
- If `$ARGUMENTS` contains `--verbose`, also print:
  - last 20 lines of run.log
  - list of failed topics (names only)
  - list of findings with FAIL verdict (names + reason)

# Hard rules
- Never mutate state. Read-only.
- Always show the "next action" line — user should never have to guess what to do.
