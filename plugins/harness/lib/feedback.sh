# shellcheck shell=bash
# Feedback (H-140, D43): file a problem with the harness as one issue in the plugin's own
# repository, with no labels, after the person's yes.
#
#   harness feedback preview <description-file>
#       Build the issue from the person's words plus the fixed technical context. Print the
#       full text, a draft folder and a confirm code. Sends nothing (with a GitHub ticket
#       source it reads ticket counts only).
#   harness feedback send --draft <dir> --code <code> --yes
#       Send exactly the draft that was shown. Refused without --yes, with a wrong code, or
#       when the draft holds a token or a path outside the plugin.
#
# The technical context is fixed (D43): plugin version, runtime version, operating system and
# a state summary of the last run. The summary is built from allow-listed facts only: the
# run's stop state, counts, the fixed role names of launched sessions, ticket counts per state
# and the engine's own failure event kinds from a fixed list. No ledger value (reason, name,
# path, account, title, session ID) is ever copied. The person's own words are cleaned too, by
# the steps in lib/feedback.jq: a path inside the plugin is made relative to the plugin root;
# any other path, token, secret value, e-mail address and the local account name are removed.
# The send refuses a draft that any of those steps would still change.
#
# Exit codes: 64 usage, 65 refused (no yes, wrong code, private data found), 66 no draft,
# 1 the tracker call failed. Requires lib/feedback.jq, lib/common.sh, lib/config.sh, lib/run.sh,
# lib/runtime.sh and lib/tickets.sh.

HO_FB_ROLES="orchestrator worker validator"
# The engine's own event kinds that report a failure or an owner step. Only these are copied.
HO_FB_ERROR_KINDS="deliver-failed marker-foreign owner-action pretrust-refused session-boot-failed
session-close-failed session-close-refused session-close-timeout session-dead session-launch-failed unreadable"

ho_fb_usage() {
  cat <<'USAGE'
usage: harness feedback <verb>

  preview <description-file>                  show the full issue text; sends nothing
  send --draft <dir> --code <code> --yes      file the shown draft as one issue, no labels
USAGE
}

ho_fb_err() { printf 'harness feedback: %s\n' "$*" >&2; }

# ho_fb_repo: owner/name of the plugin's own repository, from the manifest homepage.
ho_fb_repo() {
  jq -r '.homepage // ""' "$HO_ROOT/.claude-plugin/plugin.json" 2>/dev/null |
    sed -nE 's#^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(/.*)?$#\1/\2#p'
}

# ho_fb_sha <file>: the confirm code of a draft (first 16 hex digits of its SHA-256).
ho_fb_sha() {
  local s
  if command -v shasum >/dev/null 2>&1; then s=$(shasum -a 256 < "$1")
  elif command -v sha256sum >/dev/null 2>&1; then s=$(sha256sum < "$1")
  else return 1; fi
  printf '%s\n' "${s:0:16}"
}

# ho_fb_jq <jq-expr> [jq-options...]: run jq over stdin with the shared privacy steps of
# lib/feedback.jq loaded (one definition for the cleaner and the gate, so they cannot drift).
ho_fb_jq() {
  local expr=$1
  shift
  jq -L "$HO_ROOT/lib" "$@" "include \"feedback\"; $expr"
}

# ho_fb_clean <roots-json> <accounts-json> <private-paths-json>: stdin text -> cleaned text.
# The plugin root becomes "plugin-root" first, so a plugin path stays readable and relative.
ho_fb_clean() {
  # shellcheck disable=SC2016 # jq text, not shell
  ho_fb_jq 'clean($roots; $accts; $priv)' -Rrs --argjson roots "$1" --argjson accts "$2" --argjson priv "$3"
}

# ho_fb_gate <file> <accounts-json> <private-paths-json>: exit 0 when no cleaning step would
# change the text (no token, secret value, e-mail address, path outside the plugin or account
# name); else print the kinds found (never the text) and exit 65.
ho_fb_gate() {
  local found
  # shellcheck disable=SC2016 # jq text, not shell
  found=$(ho_fb_jq 'kinds($accts; $priv)' -Rrs --argjson accts "$2" --argjson priv "$3" < "$1") ||
    { echo "the privacy check could not run"; return 65; }
  [ -z "$found" ] && return 0
  printf '%s\n' "$found"
  return 65
}

# ho_fb_private_paths: home, the current folder and the project, as given and resolved.
ho_fb_private_paths() {
  local proj
  proj=$( (ho_project_root) 2>/dev/null) || proj=""
  jq -cn --arg h "${HOME:-}" --arg hp "$(cd -P "${HOME:-/nonexistent}" 2>/dev/null && pwd -P || true)" \
    --arg w "$PWD" --arg wp "$(pwd -P 2>/dev/null || true)" --arg p "$proj" \
    --arg pp "$( [ -n "$proj" ] && cd -P "$proj" 2>/dev/null && pwd -P || true)" \
    '[$h, $hp, $w, $wp, $p, $pp] | map(select(length >= 4 and . != "/")) | unique'
}

# ho_fb_accounts: the local account names to keep out, as a JSON array.
ho_fb_accounts() {
  local u h
  u=$(id -un 2>/dev/null || true)
  h=${HOME:+$(basename "$HOME")}
  jq -cn --arg u "$u" --arg h "$h" --arg l "${LOGNAME:-}" --arg s "${USER:-}" \
    '[$u, $h, $l, $s] | map(select(length > 0)) | unique'
}

# ho_fb_roots: the plugin root as given and with links resolved, as a JSON array.
ho_fb_roots() {
  local phys
  phys=$(cd -P "$HO_ROOT" 2>/dev/null && pwd -P) || phys=$HO_ROOT
  jq -cn --arg a "$HO_ROOT" --arg b "$phys" '[$a, $b] | unique'
}

# ho_fb_runtime_version: "<label> <version>", or a word saying why there is none. Never the
# raw output of the runtime: only a token shaped like a version is kept.
ho_fb_runtime_version() {
  local label prof cmd path out v="" rc=0
  label=$( (ho_cfg '.runtime.main' '') 2>/dev/null) || { echo "unknown (the config cannot be read)"; return 0; }
  case $label in
    '') echo "not set (config runtime.main is empty)"; return 0 ;;
    *[!a-z0-9-]*) echo "unknown (runtime.main is not a runtime name)"; return 0 ;;
  esac
  # A label with no shipped or user profile may be a private name: it is not copied.
  prof=$( (ho_rt_file "$label") 2>/dev/null) || { echo "unknown (no runtime profile has that name)"; return 0; }
  cmd=$(jq -r '.command // ""' "$prof" 2>/dev/null) || cmd=""
  case $cmd in ''|*/*|-*) echo "$label, version unknown"; return 0 ;; esac
  path=$(command -v "$cmd" 2>/dev/null) || { echo "$label, not installed"; return 0; }
  out=$(mktemp "${TMPDIR:-/tmp}/ho-fb-ver.XXXXXX") || { echo "$label, version unknown"; return 0; }
  ho_rt_probe 5 "$out" "$path" --version || rc=$?
  [ "$rc" -eq 0 ] && v=$(head -c 400 "$out" | tr ' \t\r' '\n\n\n' |
    grep -E '^v?[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.]{1,20})?$' | head -n 1)
  rm -f "$out"
  printf '%s %s\n' "$label" "${v:-version unknown}"
}

# ho_fb_last_run: print the run folder of the newest stamped run of this project, or fail.
ho_fb_last_run() {
  local proj d
  proj=$( (ho_project_root) 2>/dev/null) || return 1
  [ -d "$proj/.harness/runs" ] || return 1
  # Run IDs start with the UTC time, so name order is age order; newest first.
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    (ho_run_open "$proj/.harness/runs/$d") >/dev/null 2>&1 && { printf '%s\n' "$proj/.harness/runs/$d"; return 0; }
  done < <(find "$proj/.harness/runs" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | LC_ALL=C sort -r)
  return 1
}

# ho_fb_tickets <project>: "ready 2, in-progress 1, ..." from the ticket verbs, or "unavailable".
# Only counts leave this function; the verbs' error text (it may name a repository) is dropped.
ho_fb_tickets() {
  local proj=$1 s n out=""
  for s in $HO_STATES; do
    n=$( (cd "$proj" && HO_TICKETS_DIR=${HO_TICKETS_DIR:-$proj/.harness/tickets} ho_tickets ids "$s") 2>/dev/null) ||
      { echo "unavailable"; return 0; }
    n=$(printf '%s\n' "$n" | grep -cE '^[0-9]+$' || true)
    out="${out:+$out, }$s $n"
  done
  printf '%s\n' "$out"
}

# ho_fb_summary: the state summary of the last run, one line per fact.
ho_fb_summary() {
  local run proj
  if ! run=$(ho_fb_last_run); then
    echo "- Last run: there is no last run of this engine in this project"
    return 0
  fi
  proj=$(dirname "$(dirname "$(dirname "$run")")")
  (
    # shellcheck disable=SC2034 # read by ho_ledger_events
    HO_RUN_DIR=$run
    ho_ledger_events 2>/dev/null | jq -rs --arg roles "$HO_FB_ROLES" --arg errs "$HO_FB_ERROR_KINDS" '
      ($errs | split("\\s+"; null) | map(select(length > 0))) as $errkinds
      | ([.[] | select(.kind == "stop" or .kind == "resume") | .kind] | last) as $stop
      | ($roles | split(" ")) as $known
      | [.[] | select(.kind == "session-launch") | .role
          | if (type == "string") and IN($known[]) then . else "other" end] as $r
      | [.[] | .kind | select(type == "string" and IN($errkinds[]))] as $err
      | "- Last run: \(if $stop == "stop" then "stopped" else "not stopped" end), \(length) ledger events",
        "- Steps (session roles launched): \(if ($r | length) == 0 then "none"
            else ($r | group_by(.) | map("\(.[0]) \(length)") | join(", ")) end)",
        "- Engine error codes: \(if ($err | length) == 0 then "none"
            else ($err | group_by(.) | map("\(.[0]) x\(length)") | join(", ")) end)"'
  ) || echo "- Last run: found, but its ledger could not be read"
  printf -- '- Tickets per state: %s\n' "$(ho_fb_tickets "$proj")"
}

# ho_fb_preview <description-file>
ho_fb_preview() {
  local desc=${1-} repo roots accts priv draft first title os why
  [ -n "$desc" ] && [ $# -eq 1 ] || { ho_fb_usage >&2; return 64; }
  [ -f "$desc" ] && [ -r "$desc" ] || { ho_fb_err "cannot read the description file"; return 74; }
  [ -n "$(tr -d ' \t\r\n' < "$desc")" ] || { ho_fb_err "the description is empty; describe the problem first"; return 64; }
  repo=$(ho_fb_repo)
  [ -n "$repo" ] || { ho_fb_err "the plugin manifest names no repository"; return 78; }
  roots=$(ho_fb_roots)
  accts=$(ho_fb_accounts)
  priv=$(ho_fb_private_paths)
  draft=$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/ho-feedback.XXXXXX") || { ho_fb_err "cannot make a draft folder"; return 1; }
  # The person's words are cleaned on their own first, so a failed clean is never hidden.
  if ! head -c 20000 "$desc" | ho_fb_clean "$roots" "$accts" "$priv" > "$draft/desc.txt"; then
    ho_fb_err "cannot clean the description"; rm -rf "$draft"; return 1
  fi
  os="$(uname -s 2>/dev/null || echo unknown) $(uname -r 2>/dev/null || true)"
  if ! {
    awk '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print l[i] }' "$draft/desc.txt"
    printf '\n---\n'
    printf 'Technical context (added by the harness feedback command):\n'
    printf -- '- Plugin version: %s\n' "$( (ho_version) 2>/dev/null || echo unknown)"
    printf -- '- Runtime: %s\n' "$(ho_fb_runtime_version)"
    printf -- '- Operating system: %s %s\n' "$os" "$(uname -m 2>/dev/null || true)"
    ho_fb_summary
  } | ho_fb_clean "$roots" "$accts" "$priv" > "$draft/body.md"; then
    ho_fb_err "cannot build the draft"; rm -rf "$draft"; return 1
  fi
  first=$(awk 'NF { gsub(/[\t\r]/, " "); sub(/^ +/, ""); print substr($0, 1, 70); exit }' "$draft/desc.txt")
  title="Harness feedback: ${first:-problem report}"
  printf '%s\n' "$title" > "$draft/title.txt"
  printf '%s\n' "$repo" > "$draft/repo.txt"
  rm -f "$draft/desc.txt"
  if why=$(cat "$draft/title.txt" "$draft/body.md" > "$draft/all.txt" && ho_fb_gate "$draft/all.txt" "$accts" "$priv"); then :; else
    ho_fb_err "the draft still holds private data ($why); edit the description and preview again"
    rm -rf "$draft"
    return 65
  fi
  ho_fb_sha "$draft/all.txt" > "$draft/code.txt" || { ho_fb_err "no SHA-256 tool found"; return 1; }
  printf 'This issue will be filed in %s under your own GitHub login, with no labels.\n' "$repo"
  printf 'Nothing is sent until you say yes.\n\n'
  printf 'Title: %s\n\n' "$title"
  cat "$draft/body.md"
  printf '\nDRAFT %s\n' "$draft"
  printf 'CODE %s\n' "$(cat "$draft/code.txt")"
}

# ho_fb_send --draft <dir> --code <code> --yes
ho_fb_send() {
  local draft="" code="" yes=0 repo accts want why url
  while [ $# -gt 0 ]; do
    case $1 in
      --draft) [ $# -ge 2 ] || { ho_fb_usage >&2; return 64; }; draft=$2; shift 2 ;;
      --code) [ $# -ge 2 ] || { ho_fb_usage >&2; return 64; }; code=$2; shift 2 ;;
      --yes) yes=1; shift ;;
      *) ho_fb_err "unknown send argument: $1"; return 64 ;;
    esac
  done
  [ "$yes" -eq 1 ] || { ho_fb_err "nothing sent: the person did not say yes (pass --yes only after a yes)"; return 65; }
  [ -n "$draft" ] && [ -n "$code" ] || { ho_fb_usage >&2; return 64; }
  for f in title.txt body.md repo.txt; do
    [ -f "$draft/$f" ] && [ ! -L "$draft/$f" ] || { ho_fb_err "no draft at that folder; run preview first"; return 66; }
  done
  cat "$draft/title.txt" "$draft/body.md" > "$draft/all.txt" || { ho_fb_err "cannot read the draft"; return 66; }
  want=$(ho_fb_sha "$draft/all.txt") || { ho_fb_err "no SHA-256 tool found"; return 1; }
  [ "$code" = "$want" ] || { ho_fb_err "nothing sent: the draft is not the text that was shown (code mismatch); preview again"; return 65; }
  accts=$(ho_fb_accounts)
  why=$(ho_fb_gate "$draft/all.txt" "$accts" "$(ho_fb_private_paths)") || { ho_fb_err "nothing sent: the draft holds private data ($why)"; return 65; }
  repo=$(ho_fb_repo)
  [ -n "$repo" ] && [ "$repo" = "$(cat "$draft/repo.txt")" ] || { ho_fb_err "nothing sent: the draft names another repository"; return 65; }
  url=$(gh issue create --repo "$repo" --title "$(cat "$draft/title.txt")" --body-file "$draft/body.md") ||
    { ho_fb_err "the issue was not created (the tracker call failed); the draft is kept at $draft"; return 1; }
  rm -rf "$draft"
  printf 'OK filed %s\n' "$url"
}

ho_feedback_main() {
  local verb=${1-}
  [ $# -gt 0 ] && shift
  case $verb in
    preview) ho_fb_preview "$@" ;;
    send) ho_fb_send "$@" ;;
    help|-h|--help) ho_fb_usage ;;
    *) ho_fb_usage >&2; return 64 ;;
  esac
}
