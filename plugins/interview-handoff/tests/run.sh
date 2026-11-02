#!/usr/bin/env bash
# Regression harness for the /interview-handoff plugin.
# Contract assertions over the plugin source — verifies the method-resolution
# contract, the config-layer contract and plugin agnosticism survive in the
# published files.
#
# SCOPE: these are file contracts, not behaviour tests. They cannot run a grill,
# resolve a real skill, or reproduce the two-copies incident that produced 0.4.1
# (see IH-041..IH-044 and IH-051..IH-053 in openspec/specs/interview-handoff/). What they do is stop the written contract
# from silently regressing. Behavioural coverage is still owed.
#
# Exits 0 on all-pass, 1 on any FAIL. Final line matches the master-runner
# grep: "PASS=<N>  FAIL=<M>".
#
# Usage:  bash plugins/interview-handoff/tests/run.sh
# Deps:   POSIX shell + grep + (jq if present, else python3 for JSON checks).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$PLUGIN_DIR/../.." && pwd)

SKILL="$PLUGIN_DIR/skills/interview-handoff/SKILL.md"
CONFIG_REF="$PLUGIN_DIR/references/config.md"
PROMPT_REF="$PLUGIN_DIR/references/interviewer-prompt.md"
METHOD_REF="$PLUGIN_DIR/references/interview-method.md"
ANALYSIS_REF="$PLUGIN_DIR/references/analysis.md"
RECOMMENDED="$PLUGIN_DIR/config/recommended.json"
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"
SPECS="$REPO_ROOT/openspec/specs/interview-handoff"
CMD_RUN="$PLUGIN_DIR/commands/run.md"
CMD_COLLECT="$PLUGIN_DIR/commands/collect.md"
CMD_CONFIG="$PLUGIN_DIR/commands/config.md"
MARKET="$REPO_ROOT/.claude-plugin/marketplace.json"
RUNALL="$REPO_ROOT/tests/run-all.sh"

PASS=0
FAIL=0
FAIL_MSGS=()

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

json_valid() {
  local f="$1"
  if command -v jq >/dev/null 2>&1; then jq -e . "$f" >/dev/null 2>&1; return $?; fi
  if command -v python3 >/dev/null 2>&1; then python3 -c "import json,sys; json.load(open(sys.argv[1]))" >/dev/null 2>&1 <<<"" && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; return $?; fi
  return 0
}

json_query() { # $1=file $2=jq-expr $3=python-expr
  local f="$1" jqe="$2" pye="$3"
  if command -v jq >/dev/null 2>&1; then jq -r "$jqe" "$f" 2>/dev/null; return; fi
  if command -v python3 >/dev/null 2>&1; then python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($pye)" "$f" 2>/dev/null; return; fi
  echo ""
}

# ============================================================ Files exist
for pair in \
  "SKILL:$SKILL" \
  "config.md:$CONFIG_REF" \
  "interviewer-prompt.md:$PROMPT_REF" \
  "interview-method.md:$METHOD_REF" \
  "analysis.md:$ANALYSIS_REF" \
  "recommended.json:$RECOMMENDED" \
  "plugin.json:$MANIFEST" \
  "spec plugin-shape:$SPECS/plugin-shape/spec.md" \
  "spec interview-method:$SPECS/interview-method/spec.md" \
  "commands/run.md:$CMD_RUN" \
  "commands/collect.md:$CMD_COLLECT" \
  "commands/config.md:$CMD_CONFIG" ; do
  label="${pair%%:*}"; path="${pair#*:}"
  if [[ -f "$path" ]]; then pass "file exists: $label"
  else fail "file exists: $label" "missing at $path"; fi
done

# ============================================================ recommended.json contract
if json_valid "$RECOMMENDED"; then pass "recommended.json: valid JSON"
else fail "recommended.json: valid JSON" "does not parse"; fi

STRENGTHS=$(json_query "$RECOMMENDED" '[.connectors[].strength] | join(" ")' \
  '" ".join(v.get("strength","MISSING") for v in d["connectors"].values())')
if [[ -n "$STRENGTHS" ]] && ! grep -qvE '^(weak|strong)( (weak|strong))*$' <<<"$STRENGTHS"; then
  pass "recommended.json: every source has strength weak|strong"
else fail "recommended.json: strength" "got '$STRENGTHS'"; fi

REF_KEYS=$(json_query "$RECOMMENDED" '[.connectors[] | select(.references) | .references | keys[]] | join(" ")' \
  '" ".join(k for v in d["connectors"].values() for k in (v.get("references") or {}))')
CAND=$(json_query "$RECOMMENDED" '[.connectors[].candidates[]?] | join(" ")' \
  '" ".join(c for v in d["connectors"].values() for c in v.get("candidates",[]))')
ORPHAN=""
for k in $REF_KEYS; do grep -qw -- "$k" <<<"$CAND" || ORPHAN="$ORPHAN $k"; done
if [[ -z "$ORPHAN" ]]; then pass "recommended.json: every reference key is a declared candidate"
else fail "recommended.json: reference keys" "not in candidates:$ORPHAN"; fi

NOURL=$(json_query "$RECOMMENDED" '[.connectors[] | select(.references) | .references | to_entries[] | select(.value.url == null) | .key] | join(" ")' \
  '" ".join(k for v in d["connectors"].values() for k,r in (v.get("references") or {}).items() if not r.get("url"))')
if [[ -z "$NOURL" ]]; then pass "recommended.json: every reference carries a url"
else fail "recommended.json: reference url" "missing url for:$NOURL"; fi

# IH-043: the marketplace-relative local hint pointed into <config-root>/plugins/,
# which SKILL.md forbids touching. It must not come back.
if ! grep -q '"local"' "$RECOMMENDED"; then pass "recommended.json: no 'local' path hint (IH-043)"
else fail "recommended.json: local hint" "'local' key is back; it pointed into <config-root>/plugins/"; fi

if ! grep -q 'fetched from the URL when it is not' "$RECOMMENDED"; then
  pass "recommended.json: no path-implies-fetch wording (IH-042)"
else fail "recommended.json: fetch wording" "a missing hint path must not imply a network fetch"; fi

# ============================================================ Agnosticism
HITS=$(grep -ril 'grilling\|mattpocock' "$PLUGIN_DIR/commands" "$PLUGIN_DIR/skills" 2>/dev/null || true)
if [[ -z "$HITS" ]]; then pass "agnosticism: no method named under commands/ or skills/"
else fail "agnosticism: method name leaked" "$HITS"; fi

# ============================================================ SKILL.md method resolution
if grep -q 'where you actually read it from' "$SKILL"; then
  pass "SKILL: IH-048 transparency rule survives"
else fail "SKILL: IH-048" "'where you actually read it from' is gone"; fi

if grep -qi 'name first' "$SKILL" && grep -qi 'built-in' "$SKILL"; then
  pass "SKILL: IH-041 name-first order with built-in fallback"
else fail "SKILL: IH-041" "resolution order not stated as name-first with a built-in fallback"; fi

if grep -qi 'matched exactly' "$SKILL" || grep -qi 'never match loosely' "$SKILL"; then
  pass "SKILL: IH-044 names matched exactly, never loosely"
else fail "SKILL: IH-044 exact match" "no rule against loose name matching"; fi

if grep -qi 'offer to settle it' "$SKILL"; then
  pass "SKILL: IH-051 one obvious method is taken and offered for settling"
else fail "SKILL: IH-051" "the take-say-offer rule is missing from the not-configured branch"; fi

if grep -qi 'The user picks' "$SKILL"; then
  pass "SKILL: IH-052 ambiguity still goes to the person"
else fail "SKILL: IH-052 ask branch" "'The user picks' is gone; ambiguity must not be decided for them"; fi

if grep -q 'references/interview-method.md' "$SKILL"; then
  pass "SKILL: IH-027 built-in method is named as the last fallback"
else fail "SKILL: IH-027" "references/interview-method.md not named in the skill"; fi

if grep -q 'never read to interpret a method already configured' "$SKILL"; then
  pass "SKILL: recommended.json is choose-time only"
else fail "SKILL: recommended.json scope" "the skill does not confine that file to the choosing branch"; fi

if grep -q 'Never touch `<config-root>/plugins/`' "$SKILL"; then
  pass "SKILL: <config-root>/plugins/ stays off limits"
else fail "SKILL: config-root" "the rule against touching <config-root>/plugins/ is gone"; fi

# ============================================================ config.md contract
if grep -q 'recommended.json' "$CONFIG_REF" && grep -q 'contributes nothing to the resolved config' "$CONFIG_REF"; then
  pass "config.md: recommended.json declared advisory, not a slot"
else fail "config.md: recommended.json" "not documented as outside the six slots"; fi

if grep -q '"name"' "$CONFIG_REF" && grep -q '"url"' "$CONFIG_REF" && grep -q '"path"' "$CONFIG_REF"; then
  pass "config.md: stored method binding documents name, path and url"
else fail "config.md: binding shape" "the stored value's shape is still undocumented (the 0.4.1 root cause)"; fi

if grep -q 'at the moment the value is written' "$CONFIG_REF"; then
  pass "config.md: url is copied in at write time"
else fail "config.md: url at write time" "nothing says the url is persisted when the value is written"; fi

SLOTS=$(grep -cE '^\| [1-6] \| ' "$CONFIG_REF" || true)
if [[ "$SLOTS" -eq 6 ]]; then pass "config.md: six config slots still declared"
else fail "config.md: slots" "expected 6 slot rows, found $SLOTS"; fi

# ============================================================ interviewer prompt (IH-031 + IH-046)
if grep -q '<method>' "$PROMPT_REF"; then pass "interviewer-prompt: <method> slot present (IH-046)"
else fail "interviewer-prompt: <method>" "the method slot is gone"; fi

if grep -qi 'inline the method' "$PROMPT_REF" || grep -qi "inline the method's text" "$PROMPT_REF"; then
  pass "interviewer-prompt: inline package carries the method (IH-031)"
else fail "interviewer-prompt: IH-031" "the inline block still omits the method"; fi

# ============================================================ Requirements (OpenSpec) freshness
SHAPE="$SPECS/plugin-shape/spec.md"
if grep -q 'declare two sources' "$SHAPE" && grep -q 'interview-method' "$SHAPE" && grep -q 'session-logs' "$SHAPE"; then
  pass "REQUIREMENTS: agnosticism requirement names the real sources"
else fail "REQUIREMENTS: agnosticism" "still stale (one source / transcripts)"; fi

for id in IH-041 IH-043 IH-044 IH-051 IH-052 IH-053; do
  if grep -q "^### Requirement: $id " "$SPECS/interview-method/spec.md"; then pass "REQUIREMENTS: $id recorded"
  else fail "REQUIREMENTS: $id" "method-resolution requirement not written down"; fi
done

if [[ ! -e "$PLUGIN_DIR/REQUIREMENTS.md" ]]; then pass "REQUIREMENTS.md: gone, requirements live only in openspec/"
else fail "REQUIREMENTS.md" "back in the plugin folder (two sources of truth)"; fi

# ============================================================ Manifest / registry
if json_valid "$MANIFEST"; then pass "plugin.json: valid JSON"
else fail "plugin.json: valid JSON" "does not parse"; fi

VER=$(json_query "$MANIFEST" '.version' 'd["version"]')
if [[ -n "$VER" ]]; then pass "plugin.json: version present ($VER)"
else fail "plugin.json: version" "no version field"; fi

if grep -q '"name": "interview-handoff"' "$MARKET"; then
  pass "marketplace.json: interview-handoff listed"
else fail "marketplace.json: listing" "plugin not in the marketplace registry"; fi

if grep -q 'interview-handoff' "$RUNALL"; then
  pass "run-all.sh: interview-handoff in the PLUGINS array"
else fail "run-all.sh: registration" "plugin not registered with the master runner"; fi

# ============================================================ Summary
TOTAL=$((PASS + FAIL))
echo
echo "=============================================================="
echo "/interview-handoff tests:  PASS=$PASS  FAIL=$FAIL  (TOTAL=$TOTAL)"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
