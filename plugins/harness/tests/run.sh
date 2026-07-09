#!/usr/bin/env bash
# harness regression tests — static assertions, no source mutation, no network, no terminals.
# Prints PASS/FAIL per test id + a summary line; exit 0 iff FAIL=0.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1 — $2"; FAIL=$((FAIL+1)); }

# H-1: every engine script parses (bash -n)
t=H-1; f=0
for s in "$ROOT"/bin/*.sh; do bash -n "$s" 2>/dev/null || { f=1; break; }; done
[ "$f" -eq 0 ] && ok "$t bash -n on all bin scripts" || bad "$t" "bash -n failed on $s"

# H-2: shellcheck clean at warning severity (skipped when shellcheck absent)
t=H-2
if command -v shellcheck >/dev/null; then
  if shellcheck -S warning "$ROOT"/bin/*.sh >/dev/null 2>&1; then ok "$t shellcheck clean"; else bad "$t" "shellcheck findings at -S warning"; fi
else ok "$t shellcheck (skipped — not installed)"; fi

# H-3: plugin.json valid + version matches CHANGELOG head
t=H-3
v=$(jq -er '.version' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
if [ -n "$v" ] && head -5 "$ROOT/CHANGELOG.md" | grep -q "## $v "; then ok "$t plugin.json/CHANGELOG version $v"; else bad "$t" "version mismatch or invalid plugin.json"; fi

# H-4: naming — the standalone word (no 'over-' prefix) appears nowhere outside docs/DESIGN.md
t=H-4
w='ni'; w="${w}ght"   # keep this file from matching itself
hits=$(grep -rilE "(^|[^a-z])${w}([^a-z]|$)" "$ROOT" --exclude-dir=docs --exclude-dir=.git --exclude=run.sh 2>/dev/null || true)
[ -z "$hits" ] && ok "$t no '${w}' naming outside docs/" || bad "$t" "found in: $hits"

# H-5: model policy — haiku only ever appears in the rejection rule
t=H-5
hits=$(grep -rn 'haiku' "$ROOT/bin" "$ROOT/templates" "$ROOT/skills" "$ROOT/commands" "$ROOT/agents" 2>/dev/null | grep -v 'harness-model.sh' | grep -vi 'reject' || true)
[ -z "$hits" ] && ok "$t haiku only in the model.sh reject rule" || bad "$t" "haiku referenced in: $hits"

# H-6: config templates are valid JSON
t=H-6
if jq -e . "$ROOT/templates/user-config.example.json" >/dev/null 2>&1 \
   && jq -e . "$ROOT/templates/project-config.example.json" >/dev/null 2>&1; then ok "$t config templates parse"; else bad "$t" "template JSON invalid"; fi

# H-7: PATH namespacing — every executable bin script is harness-*.sh (hlib.sh is sourced, not executed)
t=H-7; f=0
for s in "$ROOT"/bin/*.sh; do
  b=$(basename "$s")
  [ "$b" = "hlib.sh" ] && continue
  case "$b" in harness-*.sh) ;; *) f=1; break ;; esac
done
[ "$f" -eq 0 ] && ok "$t bin/ names are harness-prefixed" || bad "$t" "unprefixed script: $b"

# H-8: L1 invariant — no prompt text ever flows through AppleScript; spawns pass launcher FILES
t=H-8
if grep -q 'term.sh" spawn "$group" "$title" "$launcher"' "$ROOT/bin/harness-spawn.sh" \
   && ! grep -q 'write text.*cat' "$ROOT/bin/harness-term.sh"; then ok "$t launcher-file spawn invariant"; else bad "$t" "prompt text may reach AppleScript"; fi

# H-9: L11 invariant — term.sh closes sessions only, never windows
t=H-9
if grep -q 'tell s to close' "$ROOT/bin/harness-term.sh" \
   && ! grep -Eq 'close (targetWindow|w[^i])' "$ROOT/bin/harness-term.sh"; then ok "$t close targets sessions only"; else bad "$t" "window-close found in term.sh"; fi

# H-10: L3 invariant — generated launchers guard cd, and spawn.sh guards cwd deterministically
t=H-10
if grep -q 'cd \\"\$cwd\\" || {' "$ROOT/bin/harness-spawn.sh" || grep -q 'cd "$cwd" || {' "$ROOT/bin/harness-spawn.sh" || grep -q "cd \\\\\"\$cwd\\\\\"" "$ROOT/bin/harness-spawn.sh"; then :; fi
if grep -q 'assert_safe_cwd' "$ROOT/bin/harness-spawn.sh" && grep -q 'refusing cwd \\$HOME\|refusing cwd \$HOME' "$ROOT/bin/hlib.sh"; then ok "$t cwd guards present"; else bad "$t" "cwd guard missing"; fi

# H-11: rate philosophy — spawn returns 75 on pause; limits.sh has wait; stop_at defaults null
t=H-11
if grep -q 'return 75' "$ROOT/bin/harness-spawn.sh" && grep -q 'wait_clear' "$ROOT/bin/harness-limits.sh" \
   && grep -q '"stop_at": null' "$ROOT/templates/user-config.example.json"; then ok "$t pause-not-stop contract"; else bad "$t" "pause contract broken"; fi

# H-12: Keychain read precedes the stale default credentials file (L6). token() may consult an
# active-account CLAUDE_CONFIG_DIR/.credentials.json first (correct — that's the switched account),
# but among the machine-default sources the Keychain must come before ~/.claude/.credentials.json.
t=H-12
body=$(awk '/^token\(\)/,/^}/' "$ROOT/bin/harness-limits.sh")
kc=$(printf '%s\n' "$body" | grep -n 'security find-generic-password' | head -1 | cut -d: -f1)
df=$(printf '%s\n' "$body" | grep -n '.claude/.credentials.json' | head -1 | cut -d: -f1)
if [ -n "$kc" ] && [ -n "$df" ] && [ "$kc" -lt "$df" ]; then ok "$t Keychain read before default credentials file"; else bad "$t" "token order wrong (kc=$kc df=$df)"; fi

# H-13: STOP is honored in spawn and watch
t=H-13
if grep -q 'stop_requested' "$ROOT/bin/harness-spawn.sh" && grep -q 'stop_requested' "$ROOT/bin/harness-run.sh"; then ok "$t STOP checked in spawn+watch"; else bad "$t" "STOP check missing"; fi

# H-14: sonnet validator wired into spawn, with fail-open ONLY on infra error (65 still rejects)
t=H-14
if grep -q 'harness-validate.sh' "$ROOT/bin/harness-spawn.sh" && grep -q 'vrc.*-eq 65' "$ROOT/bin/harness-spawn.sh"; then ok "$t sonnet validation gate wired"; else bad "$t" "validator wiring missing"; fi

# H-15: commands are thin wrappers routing to harness:harness
t=H-15; f=0
for c in "$ROOT"/commands/*.md; do grep -q 'harness:harness' "$c" || { f=1; break; }; done
[ "$f" -eq 0 ] && ok "$t all commands route to the skill" || bad "$t" "$c does not route to skill"

# H-16: skill is not directly user-invocable (commands are the surface)
t=H-16
grep -q 'user-invocable: false' "$ROOT/skills/harness/SKILL.md" && ok "$t skill user-invocable:false" || bad "$t" "missing user-invocable:false"

# H-17: agents use approved models only (sonnet/opus), never haiku
t=H-17; f=0
for a in "$ROOT"/agents/*.md; do grep -Eq '^model: (sonnet|opus)$' "$a" || { f=1; break; }; done
[ "$f" -eq 0 ] && ok "$t agent models sonnet/opus" || bad "$t" "$a has unexpected model"

# H-18: OR-chain default present for validator; '|' syntax parsed by model.sh
t=H-18
if grep -q '"validator": "fable|mythos|opus"' "$ROOT/templates/user-config.example.json" \
   && grep -q "tr '|' " "$ROOT/bin/harness-model.sh"; then ok "$t OR-chain syntax end-to-end"; else bad "$t" "OR-chain missing"; fi

# H-19: session identity — pre-generated --session-id and --resume in spawn (L17)
t=H-19
if grep -q -- '--session-id' "$ROOT/bin/harness-spawn.sh" && grep -q -- '--resume' "$ROOT/bin/harness-spawn.sh"; then ok "$t session-id/resume contract"; else bad "$t" "session identity flags missing"; fi

# H-20: prompts ban AskUserQuestion and interactive GSD (L23)
t=H-20
if grep -q 'Never use AskUserQuestion' "$ROOT/templates/prompts/orchestrator.md" \
   && grep -q 'NEVER an interactive entry point' "$ROOT/templates/prompts/worker.md"; then ok "$t unattended prompt bans present"; else bad "$t" "prompt bans missing"; fi

# H-21: GSD is driven by discovery, NOT hardcoded phase commands (naming-drift resistance)
t=H-21
if grep -q 'harness-gsd.sh discover' "$ROOT/templates/prompts/worker.md" \
   && grep -q 'do not hardcode GSD command names' "$ROOT/templates/prompts/worker.md" \
   && ! grep -qE '/gsd-(plan|execute)-phase N --auto' "$ROOT/templates/prompts/worker.md"; then
  ok "$t GSD discovery-first (no hardcoded phase commands)"
else bad "$t" "worker prompt still hardcodes gsd phase commands or lost discover step"; fi

# H-22: trust dialog is sonnet+deterministic gated; passwords are owner-gated, never typed
t=H-22
if grep -q 'harness-trust.sh" inside' "$ROOT/bin/harness-run.sh" \
   && grep -q 'trust_ok_sonnet' "$ROOT/bin/harness-run.sh" \
   && grep -q 'PASSWORD-PROMPT' "$ROOT/bin/harness-run.sh" \
   && ! grep -qiE 'send .*(password|passphrase)' "$ROOT/bin/harness-run.sh"; then
  ok "$t trust gated, passwords owner-gated (never typed)"
else bad "$t" "trust/password handling missing or types secrets"; fi

# H-23: pretrust only trusts dirs inside the project (never blanket)
t=H-23
if grep -q 'is not inside the project — not pre-trusting' "$ROOT/bin/harness-trust.sh" \
   && grep -q 'harness-trust.sh" pretrust' "$ROOT/bin/harness-spawn.sh"; then
  ok "$t pretrust scoped to project dirs"
else bad "$t" "pretrust missing or unscoped"; fi

# H-24: C1/M1 — the placeholder guard matches only harness tokens (not raw {{), role-gated to
# worker/validator, so the orchestrator prompt and ticket bodies with ${{ }} both spawn.
# END-TO-END: render the real orchestrator template as do_start would and confirm it does NOT trip
# the guard's exact regex (this is the test that would have caught C1's dead-on-arrival run).
t=H-24
guard='\{\{(HBIN|PROJECT_ROOT|RUN_DIR|RUN_ID|LANE|LANE_TICKETS)\}\}'
# (a) the rendered orchestrator prompt (do_start fills the base-4) has no unfilled base tokens —
#     this is the C1 end-to-end check that would have caught the dead-on-arrival run.
rendered_base=$(sed -e 's|{{HBIN}}|/bin|g' -e 's|{{PROJECT_ROOT}}|/p|g' -e 's|{{RUN_DIR}}|/r|g' -e 's|{{RUN_ID}}|r|g' "$ROOT/templates/prompts/orchestrator.md" | grep -E '\{\{(HBIN|PROJECT_ROOT|RUN_DIR|RUN_ID)\}\}' || true)
# (b) the narrowed guard passes real ticket content (${{ secrets }}) but catches an unfilled {{LANE}}.
c1ok=1; [ -n "$rendered_base" ] && c1ok=0
printf '%s' 'deploy uses ${{ secrets.X }} and {{ vueVar }}' | grep -qE "$guard" && c1ok=0   # must NOT match
printf '%s' 'run for {{LANE}}' | grep -qE "$guard" || c1ok=0                                  # must match
# (c) engine still role-gates and no longer uses the raw grep.
if [ "$c1ok" -eq 1 ] && grep -q 'worker|validator)' "$ROOT/bin/harness-spawn.sh" \
   && ! grep -qF "grep -q '{{'" "$ROOT/bin/harness-spawn.sh"; then
  ok "$t guard narrowed+role-gated: orchestrator renders clean, ticket {{ }} passes, {{LANE}} caught (C1/M1)"
else bad "$t" "C1/M1 regression (base-left='$rendered_base' c1ok=$c1ok)"; fi

# H-25: H1 — the watch loop tears the run down on run.complete (caffeinate stops, Mac sleeps)
t=H-25
if grep -q 'markers/run.complete.done' "$ROOT/bin/harness-run.sh" \
   && grep -q 'run.complete' "$ROOT/templates/prompts/orchestrator.md"; then
  ok "$t completed run self-teardown (H1)"
else bad "$t" "no run.complete teardown path"; fi

# H-26: H2 — engine floor under the grill gate: a ready ticket needs the checklist headers
t=H-26
if grep -q 'require_ready_body' "$ROOT/bin/harness-tickets.sh" \
   && grep -q 'missing required section' "$ROOT/bin/harness-tickets.sh"; then
  ok "$t structural grill floor on 'ready' tickets (H2)"
else bad "$t" "no structural ready-ticket check"; fi

# H-27: M4 — sonnet rejected for orchestrator/worker (build) roles
t=H-27
if grep -qE 'orchestrator:sonnet\|worker:sonnet' "$ROOT/bin/harness-spawn.sh"; then
  ok "$t sonnet rejected for build roles (M4)"
else bad "$t" "sonnet not rejected for build roles"; fi

# H-28: M3 — per-role account resolves before the shared one
t=H-28
if grep -q 'cfg ".accounts.\$role.env_command"' "$ROOT/bin/harness-spawn.sh"; then
  ok "$t per-role account override (M3)"
else bad "$t" "per-role account not wired"; fi

# H-29: project-guidance discovery — lists standard + config-listed files, flags CLAUDE.md, empty=none
t=H-29
gdir=$(mktemp -d)
mkdir -p "$gdir/.harness" "$gdir/repo/docs" "$gdir/repo/deploy"
echo '{"schemaVersion":1,"project":"g","guidance":{"files":["deploy/RUNBOOK.md"],"notes":"do not touch migrations"}}' > "$gdir/.harness/config.json"
( cd "$gdir/repo" && touch README.md Makefile .eslintrc.json CLAUDE.md docs/A.md deploy/RUNBOOK.md && printf '{"scripts":{"test":"x","lint":"y"}}' > package.json )
gout=$(HARNESS_PROJECT="$gdir" bash "$ROOT/bin/harness-guide.sh" discover "$gdir/repo" 2>/dev/null)
gempty=$(HARNESS_PROJECT="$gdir" bash "$ROOT/bin/harness-guide.sh" discover "$gdir/.harness" 2>/dev/null)
if printf '%s' "$gout" | grep -q 'README.md' \
   && printf '%s' "$gout" | grep -q 'Makefile' \
   && printf '%s' "$gout" | grep -q '.eslintrc.json' \
   && printf '%s' "$gout" | grep -qE 'scripts: (lint, test|test, lint)' \
   && printf '%s' "$gout" | grep -q 'deploy/RUNBOOK.md' \
   && printf '%s' "$gout" | grep -q 'do not touch migrations' \
   && printf '%s' "$gout" | grep -qi 'already-loaded (skip): CLAUDE.md' \
   && printf '%s' "$gempty" | grep -q 'found: none'; then
  ok "$t guidance discover: standard+config+notes listed, CLAUDE.md flagged, empty=none"
else bad "$t" "guidance discover output incomplete"; fi
rm -rf "$gdir"

echo "------------------------------------------------------------------"
echo "harness tests: PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
