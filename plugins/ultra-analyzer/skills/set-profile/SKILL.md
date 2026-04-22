---
name: set-profile
description: Switch a run's profile tier (small/medium/large/xl). Controls /ultra gate rigor, worker model, validator model, topic target count, and suggested parallelism.
allowed-tools: Bash, Read, Write
---

# Role
Write `profile` field in state.json. Emit new profile summary.

# Invocation
  /ultra-analyzer:set-profile <tier> [run-name]

Where `tier` is one of: `small | medium | large | xl`.

# Protocol

## Step 1: Parse arguments
- First token of `$ARGUMENTS` = tier. Validate against enum {small, medium, large, xl}. Reject others with an error listing the valid options.
- Second token (optional) = run-name. If absent, auto-detect single run per standard rules.

## Step 2: Profile effects

Each tier declares downstream effects. Write them all into `state.profile` as a nested object so skills downstream can read without re-deriving:

```json
{
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
}
```

### small
```
tier: small
ultra_gate_tier: --small
worker_model: haiku (all complexities)
validator_model: haiku
synthesizer_model: sonnet
topic_target: 15-25
redundancy_pair_rate_p1: 0.20
suggested_parallel_terminals: 1-2
```

### medium
```
tier: medium
ultra_gate_tier: --medium
worker_model: sonnet (M/L), haiku (S)
validator_model: haiku
synthesizer_model: sonnet
topic_target: 25-45
redundancy_pair_rate_p1: 0.40
suggested_parallel_terminals: 2-3
```

### large (DEFAULT)
```
tier: large
ultra_gate_tier: --large
worker_model: sonnet (M/L), haiku (S)
validator_model: haiku
synthesizer_model: opus
topic_target: 45-70
redundancy_pair_rate_p1: 0.60
suggested_parallel_terminals: 3-5
```

### xl
```
tier: xl
ultra_gate_tier: --xl
worker_model: opus (M/L), sonnet (S)
validator_model: sonnet
synthesizer_model: opus
topic_target: 70-120
redundancy_pair_rate_p1: 0.80
suggested_parallel_terminals: 5-10
```

## Step 3: Write the profile
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/state.sh set <run-path> .profile <profile-json-object>
```

## Step 4: Print confirmation
```
✓ Profile set: <tier> (was: <previous-tier>)
  Ultra gate tier: <value>
  Worker model: <value>
  Topic target: <min>-<max>
  Suggested terminals: <value>

Note: profile takes effect on the NEXT step. If workers are already running, they retain the model they were started with.
If you want to re-run topics with the new profile, use /ultra-analyzer:health to identify topics eligible for re-analysis.
```

# Hard rules
- Reject tiers not in the enum with a clear error listing valid options.
- NEVER change profile mid-synthesize. If `current_step == "synthesize"`, refuse and explain: synthesizer_model is already committed for this run.
- NEVER silently alter completed work. Profile applies forward only.
- Default profile for a new run is `large` (set by state.sh init).
