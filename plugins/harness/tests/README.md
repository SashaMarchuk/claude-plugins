# harness tests — coverage map

Static regression assertions (`run.sh`): no mutation, no network, no terminals spawned.
Each test pins an invariant from `docs/DESIGN.md`; the L-numbers reference its lessons ledger.

| Invariant | Origin | Test ID |
|---|---|---|
| Engine scripts parse / lint clean | quality bar | H-1, H-2 |
| Version discipline (plugin.json ↔ CHANGELOG) | house convention | H-3 |
| No banned legacy run-name user-visible | naming requirement | H-4 |
| haiku never used; sonnet/opus-only agents | model policy | H-5, H-17 |
| Config templates valid JSON | onboarding | H-6 |
| PATH-collision-proof `harness-` script names | multi-plugin machines | H-7 |
| Prompt text never flows through AppleScript | L1 | H-8 |
| Close sessions, never windows | L11 | H-9 |
| cwd guards: absolute, exists, not $HOME//, cd-or-die | L2, L3 | H-10 |
| Pause-not-stop: spawn→75, wait-on-API, stop_at:null | L8, L13 | H-11 |
| Keychain-first token read | L6 | H-12 |
| STOP honored in spawn + watch | lifecycle | H-13 |
| Sonnet spawn-validation gate (reject ≠ infra-error) | user requirement | H-14 |
| Thin commands route to `harness:harness` | house convention | H-15, H-16 |
| `\|` OR-chains parsed and defaulted | model requirement | H-18 |
| Pre-generated session ids; exact resume | L17 | H-19 |
| AskUserQuestion / interactive-GSD bans in prompts | L23 | H-20 |
| Placeholder guard narrowed+role-gated; orchestrator renders clean | C1, M1 | H-24 |
| Completed run self-teardown (caffeinate stops) | H1 | H-25 |
| Structural floor under the grill gate | H2 | H-26 |
| sonnet rejected for build roles | M4 | H-27 |
| Per-role account override | M3 | H-28 |
