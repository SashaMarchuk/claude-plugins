# shellcheck shell=bash
# Isolation self-test (design "Rebuild", separate state).
# The new engine must never see the 0.6.0 engine's variables or scripts.
# This is the only file allowed to name them, and only as data.

# Variables the 0.6.0 engine (bin/*.sh on main) exports or reads.
HO_OLD_VARS="HARNESS_PROJECT HARNESS_USER_DIR HARNESS_USER_CONFIG HARNESS_ROLE"

# Script names of the 0.6.0 engine.
HO_OLD_SCRIPTS="harness-run.sh harness-tickets.sh harness-spawn.sh harness-term.sh harness-limits.sh harness-state.sh harness-model.sh harness-trust.sh harness-guide.sh harness-gsd.sh harness-validate.sh hlib.sh"

# Print one "ISOLATION FAIL:" line per problem. Exit 65 on any problem,
# else print "ISOLATION OK" and return 0.
ho_isolation_check() {
  local problems=0 var dir script
  for var in $HO_OLD_VARS; do
    if printenv "$var" >/dev/null 2>&1; then
      printf 'ISOLATION FAIL: old variable %s is set\n' "$var"
      problems=$((problems + 1))
    fi
  done
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    for script in $HO_OLD_SCRIPTS; do
      if [ -f "$dir/$script" ]; then
        printf 'ISOLATION FAIL: old script %s on PATH in %s\n' "$script" "$dir"
        problems=$((problems + 1))
      fi
    done
  done <<PATHS
$(printf '%s\n' "${PATH:-}" | tr ':' '\n')
PATHS
  if [ "$problems" -gt 0 ]; then
    exit 65
  fi
  echo "ISOLATION OK"
}
