#!/usr/bin/env bash
# run.sh — WS-2 regression tests for /ultra-analyzer state.sh / claim.sh /
# release.sh / requeue.sh + set-profile + analyze-unit cross-model rule.
#
# Exercises acceptance criteria 1..7 for WS-2 (C-1, C-2, C-3, H-2, H-3, H-7).
# Exits non-zero on any failure. Writes a concise PASS/FAIL summary to stdout.
#
# Usage:  bash plugins/ultra-analyzer/tests/run.sh

set -uo pipefail

# Locate plugin root from this file's dir: plugins/ultra-analyzer/tests/run.sh
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BIN_DIR="$PLUGIN_DIR/bin"
STATE_SH="$BIN_DIR/state.sh"
CLAIM_SH="$BIN_DIR/claim.sh"
RELEASE_SH="$BIN_DIR/release.sh"
REQUEUE_SH="$BIN_DIR/requeue.sh"

SANDBOX=$(mktemp -d -t ultra-analyzer-tests-XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
FAIL_MSGS=()

report_pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
report_fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    report_pass "$name"
  else
    report_fail "$name" "expected=[$expected] actual=[$actual]"
  fi
}

assert_nonzero_exit() {
  # $1 name, rest is command; expect non-zero exit.
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    report_fail "$name" "expected non-zero exit, got 0"
  else
    report_pass "$name"
  fi
}

assert_exit_code() {
  local name="$1" expected="$2"; shift 2
  set +e
  "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq "$expected" ]]; then
    report_pass "$name"
  else
    report_fail "$name" "expected exit $expected, got $rc"
  fi
}

fresh_run() {
  # $1 = run name. cd into a clean subsandbox and init. Echoes run_path.
  local name="$1"
  local dir="$SANDBOX/$name"
  mkdir -p "$dir"
  (cd "$dir" && bash "$STATE_SH" init "$name" mongo >/dev/null)
  echo "$dir/.planning/ultra-analyzer/$name"
}

# ------------------------------------------------------------------ AC 1
# topics_in_progress exists + invariant holds across claim / release / requeue.

RUN=$(fresh_run t1-ac1)

# init: topics_in_progress must be present and == 0
v=$(jq -r '.counters.topics_in_progress' "$RUN/state.json")
assert_eq "AC1.init: topics_in_progress present" "0" "$v"

# Seed 3 pending topics
bash "$STATE_SH" set "$RUN" .counters.topics_total 3 >/dev/null
bash "$STATE_SH" set "$RUN" .counters.topics_pending 3 >/dev/null
for i in 1 2 3; do
  echo "T" > "$RUN/topics/pending/T00${i}__p1__x.md"
done

# Claim all three
bash "$CLAIM_SH" "$RUN" >/dev/null
bash "$CLAIM_SH" "$RUN" >/dev/null
bash "$CLAIM_SH" "$RUN" >/dev/null
invariant=$(jq -r '.counters | (.topics_total == (.topics_done + .topics_failed + .topics_pending + .topics_in_progress)) | tostring' "$RUN/state.json")
assert_eq "AC1.after-3-claims: invariant holds" "true" "$invariant"
in_prog=$(jq -r '.counters.topics_in_progress' "$RUN/state.json")
assert_eq "AC1.after-3-claims: in_progress==3" "3" "$in_prog"

# Release one done, one failed, one requeue
bash "$RELEASE_SH" "$RUN/topics/in-progress/T001__p1__x.md" done >/dev/null
bash "$RELEASE_SH" "$RUN/topics/in-progress/T002__p1__x.md" failed >/dev/null
bash "$RELEASE_SH" "$RUN/topics/in-progress/T003__p1__x.md" requeue tests >/dev/null
invariant=$(jq -r '.counters | (.topics_total == (.topics_done + .topics_failed + .topics_pending + .topics_in_progress)) | tostring' "$RUN/state.json")
assert_eq "AC1.after-release-mix: invariant holds" "true" "$invariant"
counters_line=$(jq -r '.counters | "\(.topics_total) \(.topics_done) \(.topics_failed) \(.topics_pending) \(.topics_in_progress)"' "$RUN/state.json")
assert_eq "AC1.after-release-mix: counters match" "3 1 1 1 0" "$counters_line"

# requeue.sh: done -> pending (the done one)
bash "$REQUEUE_SH" "$RUN" T001__p1__x.md gate2 >/dev/null
invariant=$(jq -r '.counters | (.topics_total == (.topics_done + .topics_failed + .topics_pending + .topics_in_progress)) | tostring' "$RUN/state.json")
assert_eq "AC1.after-requeue-from-done: invariant holds" "true" "$invariant"
counters_line=$(jq -r '.counters | "\(.topics_total) \(.topics_done) \(.topics_failed) \(.topics_pending) \(.topics_in_progress)"' "$RUN/state.json")
assert_eq "AC1.after-requeue-from-done: counters match" "3 0 1 2 0" "$counters_line"

# ------------------------------------------------------------------ AC 2
# Run-name sanitization rejects ../../tmp/evil with exit 6.
(
  cd "$SANDBOX"
  set +e
  bash "$STATE_SH" init "../../tmp/evil" mongo >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 6 ]]; then
    exit 0
  else
    exit "$rc"
  fi
)
rc=$?
if [[ "$rc" -eq 0 ]]; then
  report_pass "AC2: run-name '../../tmp/evil' rejected exit 6"
else
  report_fail "AC2: run-name '../../tmp/evil' rejected exit 6" "got exit $rc"
fi

# Valid names still work
(cd "$SANDBOX" && bash "$STATE_SH" init "ok-run_1" mongo >/dev/null)
[[ -f "$SANDBOX/.planning/ultra-analyzer/ok-run_1/state.json" ]] && \
  report_pass "AC2: valid run-name accepted" || \
  report_fail "AC2: valid run-name accepted" "state.json not created"

# ------------------------------------------------------------------ AC 3
# .current_step enum enforced.
RUN=$(fresh_run t3-ac3)
assert_exit_code "AC3: .current_step 'badvalue' refused with exit 7" 7 \
  bash "$STATE_SH" set "$RUN" .current_step '"badvalue"'
# Value should not have been written
step=$(jq -r '.current_step' "$RUN/state.json")
assert_eq "AC3: .current_step unchanged after reject" "init" "$step"

# ------------------------------------------------------------------ AC 4 (was AC 3 second half, tracked as gate-consult)
# FAIL gate blocks forward transition.
RUN=$(fresh_run t4-ac4)
assert_exit_code "AC4: discover blocked while pre-discover is 'pending'" 8 \
  bash "$STATE_SH" set "$RUN" .current_step '"discover"'
# Flip pre-discover to FAIL explicitly
bash "$STATE_SH" set "$RUN" '.ultra_gates."pre-discover".verdict' '"FAIL"' >/dev/null
assert_exit_code "AC4: discover blocked while pre-discover is 'FAIL'" 8 \
  bash "$STATE_SH" set "$RUN" .current_step '"discover"'
# Flip to PASS — transition succeeds
bash "$STATE_SH" set "$RUN" '.ultra_gates."pre-discover".verdict' '"PASS"' >/dev/null
bash "$STATE_SH" set "$RUN" .current_step '"discover"' >/dev/null
step=$(jq -r '.current_step' "$RUN/state.json")
assert_eq "AC4: discover allowed after pre-discover PASS" "discover" "$step"
# synthesize still blocked — pre-synthesize pending
bash "$STATE_SH" set "$RUN" '.ultra_gates."pre-synthesize".verdict' '"FAIL"' >/dev/null
assert_exit_code "AC4: synthesize blocked while pre-synthesize is 'FAIL'" 8 \
  bash "$STATE_SH" set "$RUN" .current_step '"synthesize"'
# failed always allowed
bash "$STATE_SH" set "$RUN" .current_step '"failed"' >/dev/null
step=$(jq -r '.current_step' "$RUN/state.json")
assert_eq "AC4: failed always allowed" "failed" "$step"

# ------------------------------------------------------------------ AC 5 (was task 5, jq-injection)
RUN=$(fresh_run t5-ac5)
orig_status=$(jq -r '.status' "$RUN/state.json")
assert_eq "AC5: baseline status" "pending" "$orig_status"
set +e
bash "$STATE_SH" set "$RUN" '.counters.topics_done = 100 | .status = "passed"' 1 >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  report_pass "AC5: jq-injection path rejected (exit $rc)"
else
  report_fail "AC5: jq-injection path rejected" "unexpected exit 0"
fi
post_status=$(jq -r '.status' "$RUN/state.json")
assert_eq "AC5: .status untouched after injection attempt" "pending" "$post_status"
post_done=$(jq -r '.counters.topics_done' "$RUN/state.json")
assert_eq "AC5: .counters.topics_done untouched" "0" "$post_done"

# Also assert inc rejects injection
RUN=$(fresh_run t5-ac5b)
assert_nonzero_exit "AC5: inc with injection path rejected" \
  bash "$STATE_SH" inc "$RUN" '.counters.topics_done += 100 | .status'

# ------------------------------------------------------------------ AC 6 (was task 6, set takes lock)
RUN=$(fresh_run t6-ac6)
# Concurrent 10 inc + 10 set: topics_done must end at exactly 10.
for i in 1 2 3 4 5 6 7 8 9 10; do
  bash "$STATE_SH" inc "$RUN" .counters.topics_done &
  bash "$STATE_SH" set "$RUN" .status "busy-$i" &
done
wait
post_done=$(jq -r '.counters.topics_done' "$RUN/state.json")
assert_eq "AC6: concurrent inc+set preserves inc count" "10" "$post_done"

# ------------------------------------------------------------------ AC 7 (small-profile validator + cross-model separation)
# Validate the default init profile (large) has cross-model separation.
RUN=$(fresh_run t7-ac7)
profile_check=$(jq -r '
  .profile as $p
  | ($p.validator_model != $p.worker_model)
    and ($p.validator_model_complexity_S != $p.worker_model_complexity_S)
  | tostring
' "$RUN/state.json")
assert_eq "AC7.large: validator != worker (both bands)" "true" "$profile_check"

# Grep the set-profile SKILL for each tier to confirm separation is documented.
SETPROFILE="$PLUGIN_DIR/skills/set-profile/SKILL.md"
# small should declare validator_model: sonnet (closes original AC-6)
if grep -q '^validator_model: sonnet$' <(awk '/^### small$/,/^### medium$/' "$SETPROFILE"); then
  report_pass "AC7.small: validator_model declared sonnet"
else
  report_fail "AC7.small: validator_model declared sonnet" "not found in small block"
fi
# medium: validator_model != worker_model. Check for opus validator there.
if grep -q '^validator_model: opus$' <(awk '/^### medium$/,/^### large/' "$SETPROFILE"); then
  report_pass "AC7.medium: validator_model declared opus"
else
  report_fail "AC7.medium: validator_model declared opus" "not found in medium block"
fi
# large: validator_model opus.
if grep -q '^validator_model: opus$' <(awk '/^### large \(DEFAULT\)$/,/^### xl/' "$SETPROFILE"); then
  report_pass "AC7.large: validator_model declared opus"
else
  report_fail "AC7.large: validator_model declared opus" "not found in large block"
fi
# xl: validator_model sonnet + validator_model_complexity_S haiku.
xl_block=$(awk '/^### xl$/,/^### Cross-model/' "$SETPROFILE")
if echo "$xl_block" | grep -q '^validator_model: sonnet$' && echo "$xl_block" | grep -q '^validator_model_complexity_S: haiku$'; then
  report_pass "AC7.xl: validator_model=sonnet, validator_S=haiku"
else
  report_fail "AC7.xl: validator_model=sonnet, validator_S=haiku" "missing entries in xl block"
fi

# analyze-unit/SKILL.md contains the mechanical refusal block.
ANALYZEUNIT="$PLUGIN_DIR/skills/analyze-unit/SKILL.md"
if grep -q 'VALIDATOR_MODEL == "\$model"\|VALIDATOR_MODEL" == "\$model"' "$ANALYZEUNIT" \
   && grep -q 'falling back' "$ANALYZEUNIT"; then
  report_pass "AC7: analyze-unit SKILL enforces VALIDATOR_MODEL != worker"
else
  report_fail "AC7: analyze-unit SKILL enforces VALIDATOR_MODEL != worker" \
    "refusal block missing"
fi

# ------------------------------------------------------------------ Summary
echo
echo "=============================================================="
echo "WS-2 tests:  PASS=$PASS  FAIL=$FAIL"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
