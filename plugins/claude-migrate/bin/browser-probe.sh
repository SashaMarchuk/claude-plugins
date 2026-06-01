#!/usr/bin/env bash
# browser-probe.sh - detect a reachable, PRE-AUTHENTICATED browser transport for
# the optional browser sink, and record the winner in state.output.browser.
#
# Usage:
#   browser-probe.sh <run-path>
#
# SPEC §6.1 - detect, in PRIORITY order, the first reachable transport and write
# it to state.output.browser via state.sh (the only legal mutator of state.json):
#   1. DEFAULT - @playwright/mcp persistent profile
#                    (--user-data-dir /Users/sasha-marchuk/.playwright-profile).
#                    The user logs in once; cookies persist across runs.
#   2. FALLBACK - Playwright lib over CDP: connectOverCDP('http://127.0.0.1:9222').
#                    If the port is CLOSED, print the macOS launch command.
#   3. SITUATIONAL - browsermcp browser extension.
#   4. LAST RESORT - browser-use (agentic).
#   If none -> transport=null.
#
# This script only establishes REACHABILITY/transport. The authenticated marker
# (composer/avatar) is probed IN-SESSION by the SINK `prepare` op via the
# accessibility snapshot (SPEC §6.2), which captures dest_account_email_hash and
# flips authed=true. We therefore always write authed=false here and never script
# login (references/login-policy.md).
#
# Profile-transport reachability is a SETUP fact, not a runtime port probe, so the
# persistent profile is treated as available unless explicitly disabled via env.

set -uo pipefail

run_path="${1:?run-path required}"
bindir=$(cd "$(dirname "$0")" && pwd)
state_sh="$bindir/state.sh"
state_file="$run_path/state.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[browser-probe] FATAL: jq not installed" >&2
  exit 1
fi
if [[ ! -f "$state_file" ]]; then
  echo "[browser-probe] FATAL: no state.json at $state_file" >&2
  exit 2
fi
if [[ ! -x "$state_sh" && ! -f "$state_sh" ]]; then
  echo "[browser-probe] FATAL: state.sh not found at $state_sh" >&2
  exit 2
fi

# Configurable knobs (overridable via env for tests / non-default setups).
PROFILE_DIR="${CLAUDE_MIGRATE_PLAYWRIGHT_PROFILE:-/Users/sasha-marchuk/.playwright-profile}"
CDP_HOST="${CLAUDE_MIGRATE_CDP_HOST:-127.0.0.1}"
CDP_PORT="${CLAUDE_MIGRATE_CDP_PORT:-9222}"
CDP_ENDPOINT="http://${CDP_HOST}:${CDP_PORT}"

# Persistent profile is the DEFAULT transport. Treat it as available unless the
# operator explicitly opts out (CLAUDE_MIGRATE_NO_PROFILE=1) - it is a one-time
# login setup, not a live socket we can poll from a shell.
profile_available=1
if [[ "${CLAUDE_MIGRATE_NO_PROFILE:-0}" == "1" ]]; then
  profile_available=0
fi

# Probe whether the CDP debugging port is OPEN (open => a Chrome was launched
# with --remote-debugging-port). Prefer a real /json/version HTTP check; fall
# back to a raw TCP connect via bash's /dev/tcp.
cdp_open=0
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 2 "${CDP_ENDPOINT}/json/version" >/dev/null 2>&1; then
    cdp_open=1
  fi
else
  if (exec 3<>"/dev/tcp/${CDP_HOST}/${CDP_PORT}") 2>/dev/null; then
    cdp_open=1
    exec 3>&- 2>/dev/null || true
  fi
fi

# The macOS command to launch Chrome with the CDP debugging port, printed when
# the user needs the CDP fallback but the port is closed.
cdp_launch_cmd='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome \
  --remote-debugging-port='"${CDP_PORT}"' \
  --user-data-dir="$HOME/.claude-migrate-chrome"'

# Resolve the winning transport in strict priority order.
transport="null"
endpoint="null"

if [[ "$profile_available" == "1" ]]; then
  transport="profile"
  endpoint="$PROFILE_DIR"
elif [[ "$cdp_open" == "1" ]]; then
  transport="cdp"
  endpoint="$CDP_ENDPOINT"
else
  # No profile (opted out) and CDP port closed. Surface the situational/last-resort
  # transports as guidance, but record transport=null so the controller knows the
  # default and fallback are both unavailable and can demote to the copy-page floor
  # or block per the G-BROWSER rules (SPEC §6.6).
  transport="null"
  endpoint="null"
fi

# Persist the winner. Each field goes through state.sh (locked, atomic,
# injection-defended). authed always starts false - the in-session prepare op
# owns the auth marker.
write_state() {
  local jq_path="$1" value="$2"
  bash "$state_sh" set "$run_path" "$jq_path" "$value"
}

write_state '.output.browser.transport' "$transport"
write_state '.output.browser.endpoint' "$endpoint"
write_state '.output.browser.authed' "false"

# Human-readable report + the CDP launch command when relevant.
echo "[browser-probe] transport=$transport endpoint=$endpoint authed=false"
case "$transport" in
  profile)
    echo "[browser-probe] Using the @playwright/mcp persistent profile (default)."
    echo "[browser-probe] Profile dir: $PROFILE_DIR"
    echo "[browser-probe] If you are not logged into the NEW account yet: open the"
    echo "[browser-probe] connected browser, log in once, then /claude-migrate:resume."
    ;;
  cdp)
    echo "[browser-probe] Using Playwright-over-CDP at $CDP_ENDPOINT (fallback)."
    ;;
  null)
    echo "[browser-probe] No default profile and CDP port ${CDP_PORT} is closed."
    echo "[browser-probe] To enable the CDP fallback, launch Chrome with debugging on (macOS):"
    echo
    echo "    $cdp_launch_cmd"
    echo
    echo "[browser-probe] Then log into the NEW account in that window and re-run the probe,"
    echo "[browser-probe] or /claude-migrate:resume. Situational/last-resort transports"
    echo "[browser-probe] (browsermcp extension, browser-use) may also be configured in"
    echo "[browser-probe] selectors.json. Otherwise the byte-exact copy page (out/index.html)"
    echo "[browser-probe] remains the reliable migration floor."
    ;;
esac
