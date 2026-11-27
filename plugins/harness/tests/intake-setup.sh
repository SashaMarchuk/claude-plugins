# shellcheck shell=bash
# Shared setup for the intake and tracker-comment tests (sourced; not a test file).
# A project on the GitHub backend against the fake gh, one stamped run in $run, and helpers
# that act as a named person on the fake tracker. The harness signs in as harness-bot.
h="$HO_PLUGIN_ROOT/bin/harness"
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
user="$base/user"
mkdir -p "$proj/.harness" "$user"
printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"}}\n' > "$proj/.harness/config.json"
printf '{"schemaVersion": 2}\n' > "$user/config.json"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$user"
export HO_FAKE_GH_DIR="$base/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
export HO_FAKE_CLAUDE_LOG="$base/claude.log"
mkdir -p "$HO_FAKE_GH_DIR"
# Who has which access on fake/repo. harness-bot is the harness's own account.
printf '{"harness-bot": "write", "alice": "write", "maya": "maintain", "olga": "admin", "tom": "triage", "rita": "read", "ci-bot[bot]": "write"}\n' > "$HO_FAKE_GH_DIR/perms.json"
run=$(cd "$proj" && "$h" run new)
# A ready verdict from the readiness judge unless a test says otherwise.
export HO_FAKE_CLAUDE_STDOUT='{"ready": true, "questions": []}'

# ticket <title> [state] [body]: a new ticket; prints its number. With no state on GitHub it is
# a plain issue without labels, as a person opens it; with a state it is added by the harness
# (as harness-bot) in that state. The local backend always uses "tickets add" (default blocked).
ticket() {
  local f="$base/body.$$.md"
  printf '%s\n' "${3:-## Outcome
Export reports as CSV.

## Scope
src/report.sh

## Acceptance criteria
A test exports one report.}" > "$f"
  if [ -z "${2:-}" ] && [ "${HO_TICKETS_SOURCE:-}" = github ]; then
    gh issue create --repo fake/repo --title "$1" --body-file "$f" | sed 's#.*/##'
  else
    "$h" tickets add "$1" "$f" "${2:-blocked}" | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p'
  fi
}
# as <login> <gh args...>: run the fake gh as that person.
as() { local who=$1; shift; HO_FAKE_GH_USER=$who gh "$@"; }
# label <login> <issue> <state>: that person sets the state label.
label() { as "$1" issue edit "$2" --repo fake/repo --add-label "harness:$3" >/dev/null; }
labels() { jq -c '[.labels[]] | sort' "$HO_FAKE_GH_DIR/issues/$1.json"; }
comments() { jq -c '[.comments[].body]' "$HO_FAKE_GH_DIR/issues/$1.json"; }
ncomments() { jq '.comments | length' "$HO_FAKE_GH_DIR/issues/$1.json"; }
ledger() { cat "$run/ledger.jsonl"; }
# age_poll: make the last poll look old (an hour and more ago), so the next tick is due.
age_poll() { [ ! -f "$run/intake/poll.json" ] || touch -t 200001010000 "$run/intake/poll.json"; }
tick() { age_poll; "$h" intake "$run" tick "$@"; }
