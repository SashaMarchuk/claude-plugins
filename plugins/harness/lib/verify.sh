# shellcheck shell=bash
# Verification (tasks.md 15.1, 15.2; H-053, H-054, H-056 to H-063; design D15, D16,
# D37-VERIFICATION-1 to -7). `harness verify <run-dir> <verb> <lane> ...`.
#
# The Verification block is built from the results recorded during the run, never from a
# session's free text (D37-VERIFICATION-4). One record per check result goes to
# <run>/verify/<lane>.jsonl; the newest record of a check wins.
#
#   record <lane> --check NAME --result passed|failed|not-done [--reason R] [--proof P]
#   tests <lane> (--total N --passed P --failed F --skipped S | --unreadable | --no-tests)
#        the test rule (H-056, H-057, D37-VERIFICATION-3): no failed test, the counts add up
#        (passed + failed + skipped = total), and at least one test ran unless the profile sets
#        allow_zero_tests. Skipped tests are not tests run. An unreadable result is never zero.
#        Records the check "tests"; exit 0 passed, 72 failed.
#   block <lane> [--expect a,b,...] [--ui] [--flow NAME]
#        print the Verification block: ticket and session ID, verifier and verdict, checks done,
#        proof, gaps. The predefined list is --expect or verification.checks. With --ui the
#        browser check (flow step ui-check, H-059) is expected; switched off in the flow, it is
#        a gap "not done, switched off by the flow configuration".
#   comment <lane> [block options]   the same block as a ticket comment, so the two agree (H-053)
#   remarks <lane>   the reaction to the lane's verdict (H-058, D15, D37-VERIFICATION-6):
#        "passed with remarks" never merges; remarks: human sends the ticket to needs-review
#        (exit 76); remarks: fix allows up to remarks_max_fix_rounds (default 3) fix rounds,
#        each judged by a fresh validator session (exit 0 "fix round N"); then needs-review.
#        A clean "passed" from a validator not used in an earlier round: exit 0 "clean".
#   reviews <lane>   external review comments on the lane's PR (H-061 to H-063,
#        D37-VERIFICATION-5). external_review: react (default) | ask | ignore. Only a trusted
#        author (write access, or listed in external_review_bots) is acted on; anyone else is
#        recorded in the ticket thread and not applied. react falls back to ask when the flow has
#        no review-comments step or the profile allows no push. ask: shown to a human, the
#        ticket goes to needs-review (exit 76).
#
# Exit codes: 0 ok, 64 usage, 65 refused, 72 failed, 76 handed to a human, 78 config error.
# Requires lib/run.sh, lib/config.sh, lib/autonomy.sh, lib/loop.sh, lib/tickets.sh, lib/ship.sh.

ho_vf_err() { printf 'harness: verify: %s\n' "$*" >&2; }

ho_vf_usage() {
  cat >&2 <<'USAGE'
usage: harness verify <run-dir> record <lane> --check NAME --result passed|failed|not-done [--reason R] [--proof P]
       harness verify <run-dir> tests <lane> (--total N --passed P --failed F --skipped S | --unreadable | --no-tests)
       harness verify <run-dir> block <lane> [--expect a,b,...] [--ui] [--flow NAME]
       harness verify <run-dir> comment <lane> [--expect a,b,...] [--ui] [--flow NAME]
       harness verify <run-dir> remarks <lane>
       harness verify <run-dir> reviews <lane>
exit: 0 ok, 64 usage, 65 refused, 72 failed, 76 handed to a human, 78 config error
USAGE
}

ho_vf_file() { printf '%s/verify/%s.jsonl\n' "$HO_RUN_DIR" "$1"; }

# ho_vf_add <lane> <check> <result> <reason> <proof> [exception]
ho_vf_add() {
  mkdir -p "$HO_RUN_DIR/verify" || return 1
  jq -cn --arg c "$2" --arg r "$3" --arg why "$4" --arg p "$5" --arg e "${6-}" --arg ts "$(ho_now)" \
    '{check: $c, result: $r, reason: $why, proof: $p, exception: $e, ts: $ts}' >> "$(ho_vf_file "$1")" || return 1
  ho_ledger_append verify-check lane "$1" check "$2" result "$3"
}

ho_vf_check_ok() { printf '%s' "${1-}" | grep -Eq '^[a-z0-9][a-z0-9 -]{0,39}$'; }

ho_vf_record() {
  local lane=${1-} check="" result="" reason="" proof=""
  shift || true
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || { ho_vf_usage; return 64; }
    case $1 in
      --check) check=$2 ;; --result) result=$2 ;; --reason) reason=$2 ;; --proof) proof=$2 ;;
      *) ho_vf_usage; return 64 ;;
    esac
    shift 2
  done
  ho_loop_lane_ok "$lane" || return 65
  ho_vf_check_ok "$check" || { ho_vf_err "a check name is a-z 0-9, spaces and -, at most 40 characters"; return 64; }
  case $result in passed | failed | not-done) ;; *) ho_vf_usage; return 64 ;; esac
  [ "$result" != not-done ] || [ -n "$reason" ] || { ho_vf_err "a check that was not done needs --reason"; return 64; }
  ho_vf_add "$lane" "$check" "$result" "$reason" "$proof" || return 1
  printf 'recorded %s: %s\n' "$check" "$result"
}

ho_vf_int() { case ${1-} in '' | *[!0-9]*) return 1 ;; esac; [ "${#1}" -le 9 ]; }

ho_vf_tests() {
  local lane=${1-} total="" passed="" failed="" skipped="" mode=counts zero why="" exc=""
  shift || true
  while [ $# -gt 0 ]; do
    case $1 in
      --unreadable) mode=unreadable; shift ;;
      --no-tests) mode=none; shift ;;
      --total | --passed | --failed | --skipped)
        [ $# -ge 2 ] && ho_vf_int "$2" || { ho_vf_err "$1 needs a whole number"; return 64; }
        case $1 in --total) total=$((10#$2)) ;; --passed) passed=$((10#$2)) ;; --failed) failed=$((10#$2)) ;; *) skipped=$((10#$2)) ;; esac
        shift 2 ;;
      *) ho_vf_usage; return 64 ;;
    esac
  done
  ho_loop_lane_ok "$lane" || return 65
  zero=$(ho_au_profile | jq -r .allow_zero_tests) || return 78
  case $mode in
    unreadable) why="the test command did not run or its result cannot be read (never counted as zero tests)" ;;
    none)
      if [ "$zero" = true ]; then exc="the project has no tests; zero tests are allowed by the profile (allow_zero_tests)"
      else why="the project has no tests and the profile requires at least one test"; fi ;;
    counts)
      [ -n "$total" ] && [ -n "$passed" ] && [ -n "$failed" ] && [ -n "$skipped" ] || { ho_vf_err "tests needs --total, --passed, --failed and --skipped"; return 64; }
      if [ $((passed + failed + skipped)) -ne "$total" ]; then why="the counts do not add up: $passed passed + $failed failed + $skipped skipped is not $total"
      elif [ "$failed" -gt 0 ]; then why="$failed test(s) failed"
      elif [ "$passed" -eq 0 ]; then
        if [ "$zero" = true ]; then exc="zero tests ran; allowed by the profile (allow_zero_tests)"
        else why="zero tests ran (skipped tests do not count)"; fi
      fi ;;
  esac
  local proof=""
  [ "$mode" != counts ] || proof="$passed passed, $failed failed, $skipped skipped of $total"
  if [ -n "$why" ]; then
    ho_vf_add "$lane" tests failed "$why" "$proof" || return 1
    printf 'tests: failed (%s)\n' "$why"
    return "$HO_EXIT_GATE"
  fi
  ho_vf_add "$lane" tests passed "" "$proof" "$exc" || return 1
  printf 'tests: passed%s\n' "${exc:+ (exception: $exc)}"
}

# ho_vf_steps <flow>: the flow's switched-on step ids, one per line.
ho_vf_steps() { [ -z "${1-}" ] || "$HO_ROOT/bin/harness" flow steps "$1" 2>/dev/null | cut -f2; }

# ho_vf_flow: the flow of flow.use, or nothing. With no flow named, the browser check stays
# expected (it is on by default, D37-VERIFICATION-7) and no review-comments step is known.
ho_vf_flow() { ho_cfg '.flow.use' ''; }

# ho_vf_block <lane> [--expect L] [--ui] [--flow F]: print the block.
ho_vf_block() {
  local lane=${1-} expect="" ui=0 flow="" lj vf sha ticket worker vtext verdict verifier recs
  shift || true
  while [ $# -gt 0 ]; do
    case $1 in
      --expect) [ $# -ge 2 ] || { ho_vf_usage; return 64; }; expect=$2; shift 2 ;;
      --flow) [ $# -ge 2 ] || { ho_vf_usage; return 64; }; flow=$2; shift 2 ;;
      --ui) ui=1; shift ;;
      *) ho_vf_usage; return 64 ;;
    esac
  done
  ho_loop_lane_ok "$lane" || return 65
  lj="$HO_RUN_DIR/lanes/$lane.json"
  [ -f "$lj" ] || { ho_vf_err "lane $lane is not ready"; return 65; }
  sha=$(jq -r '.sha // ""' "$lj")
  worker=$(jq -r '.worker_session // "none"' "$lj")
  ticket=$(jq -r '.ticket // ""' "$(ho_ship_rec "$lane")" 2>/dev/null) || ticket=""
  [ -n "$ticket" ] || ticket=$(jq -r '.ticket // "none"' "$lj")
  [ -n "$expect" ] || expect=$(ho_cfg '.verification.checks | if type == "array" then map(strings) | join(",") else "" end' '') || return 78
  [ -n "$flow" ] || flow=$(ho_vf_flow) || return 78
  vf="$HO_RUN_DIR/verdicts/$lane/$sha.json"
  if [ -f "$vf" ] && [ ! -L "$vf" ]; then
    vtext=$(jq -r '.text // ""' "$vf")
    verdict=$(printf '%s\n' "$vtext" | head -n 1)
    verifier="independent validator, session $(jq -r '.session_name // "?"' "$vf") ($(jq -r '.session_id // "?"' "$vf"))"
  else
    verdict="no verdict recorded" verifier="none"
  fi
  recs="[]"
  [ ! -f "$(ho_vf_file "$lane")" ] || recs=$(jq -s 'group_by(.check) | map(max_by(.ts)) ' "$(ho_vf_file "$lane")")
  local browser_off=0
  if [ "$ui" -eq 1 ]; then
    if [ -z "$flow" ] || ho_vf_steps "$flow" | grep -qx ui-check; then expect="${expect:+$expect,}browser"; else browser_off=1; fi
  fi
  jq -rn --argjson recs "$recs" --arg expect "$expect" --arg ticket "$ticket" --arg sid "$worker" --arg sha "$sha" \
    --arg verdict "$verdict" --arg verifier "$verifier" --argjson off "$browser_off" '
    def none(l): if (l | length) == 0 then ["- none"] else l end;
    ($recs | map(select(.result != "not-done"))) as $done
    | ($expect | split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0)) | unique) as $exp
    | ([$recs[] | select(.result == "not-done") | "- \(.check): not done (\(.reason))"]
       + [$exp[] as $e | select(($recs | map(.check) | index($e)) == null) | "- \($e): not done (no result was recorded)"]
       + (if $off == 1 then ["- browser check: not done, switched off by the flow configuration"] else [] end)) as $gaps
    | ["## Verification", "",
       "**Verdict: \($verdict)**", "",
       "### Ticket and session", "- ticket: \($ticket)", "- worker session: \($sid)", "- commit: \($sha)", "",
       "### Verifier and verdict", "- verifier: \($verifier)", "- verdict: \($verdict)", "",
       "### Checks done"]
      + none([$done[] | "- \(.check): \(.result)" + (if .reason != "" then " (\(.reason))" else "" end)
              + (if .exception != "" then " — exception: \(.exception)" else "" end)])
      + ["", "### Proof"] + none([$done[] | select(.proof != "") | "- \(.check): \(.proof)"])
      + ["", "### Gaps"] + none($gaps)
    | .[]'
}

ho_vf_comment() {
  local lane=${1-} ticket f
  f="$HO_RUN_DIR/verify/$lane.comment.md"
  mkdir -p "$HO_RUN_DIR/verify"
  ho_vf_block "$@" > "$f" || return $?
  ticket=$(sed -n 's/^- ticket: //p' "$f" | head -n 1)
  ho_vf_int "$ticket" || { ho_vf_err "lane $lane names no ticket"; return 65; }
  ho_tickets comment "$ticket" "$f" --role orchestrator >/dev/null || return $?
  ho_ledger_append verify-comment lane "$lane" ticket "$ticket"
  printf 'Verification block posted on ticket %s\n' "$ticket"
}

ho_vf_ticket() { # <lane>: the lane's ticket or nothing
  local t
  t=$(jq -r '.ticket // ""' "$(ho_ship_rec "$1")" 2>/dev/null) || t=""
  [ -n "$t" ] || t=$(jq -r '.ticket // ""' "$HO_RUN_DIR/lanes/$1.json" 2>/dev/null) || t=""
  printf '%s\n' "$t"
}

ho_vf_human() { # <lane> <ticket> <why>: needs-review, one owner-action line, exit 76
  [ -z "$2" ] || ho_tickets review "$2" >/dev/null || true
  ho_ledger_append owner-action title "ticket ${2:-?} (lane $1) needs a human" why "$3" command "read the PR and its verdict" verify "a human decides"
  printf 'handed to a human: %s; ticket %s is needs-review\n' "$3" "${2:-?}"
  return "$HO_EXIT_HUMAN"
}

ho_vf_remarks() {
  local lane=${1-} lj sha vf first vsid prof mode max rounds ticket rf
  [ $# -eq 1 ] || { ho_vf_usage; return 64; }
  ho_loop_lane_ok "$lane" || return 65
  lj="$HO_RUN_DIR/lanes/$lane.json"
  [ -f "$lj" ] || { ho_vf_err "lane $lane is not ready"; return 65; }
  sha=$(jq -r '.sha // ""' "$lj")
  vf="$HO_RUN_DIR/verdicts/$lane/$sha.json"
  [ -f "$vf" ] && [ ! -L "$vf" ] || { ho_vf_err "no verdict for lane $lane at $sha"; return 65; }
  first=$(jq -r '.text | split("\n")[0]' "$vf")
  vsid=$(jq -r '.session_id // ""' "$vf")
  ticket=$(ho_vf_ticket "$lane")
  rf="$HO_RUN_DIR/verify/$lane.rounds.jsonl"
  rounds=0
  [ ! -f "$rf" ] || rounds=$(grep -c . "$rf")
  # D37-VERIFICATION-6: each round is judged by a fresh validator, never one used before.
  if [ "$rounds" -gt 0 ] && jq -e --arg s "$vsid" 'select(.validator == $s)' "$rf" >/dev/null 2>&1; then
    ho_ledger_append remarks-not-fresh lane "$lane" sha "$sha" validator "$vsid"
    ho_vf_err "the verdict for $sha comes from a validator session used in an earlier round; a fresh validator must check the new head"
    return 65
  fi
  case $first in
    passed) ho_ledger_append remarks-clean lane "$lane" sha "$sha" rounds "$rounds"; printf 'clean: a plain "passed" for %s\n' "$sha"; return 0 ;;
    "passed with remarks") ;;
    *) ho_ledger_append remarks-failed lane "$lane" sha "$sha"; printf 'the verdict for %s is not a pass (%s)\n' "$sha" "${first:0:60}"; return "$HO_EXIT_GATE" ;;
  esac
  prof=$(ho_au_profile) || return 78
  mode=$(printf '%s' "$prof" | jq -r .remarks)
  if [ "$mode" != fix ]; then
    ho_vf_human "$lane" "$ticket" "the verdict is \"passed with remarks\" and the profile sets remarks: human"
    return
  fi
  max=$(ho_cfg_int '.remarks_max_fix_rounds' 3) || return 78
  if [ "$rounds" -ge "$max" ]; then
    ho_vf_human "$lane" "$ticket" "$rounds fix round(s) ended without a clean \"passed\""
    return
  fi
  mkdir -p "$HO_RUN_DIR/verify"
  jq -cn --argjson n "$((rounds + 1))" --arg sha "$sha" --arg v "$vsid" '{round: $n, sha: $sha, validator: $v}' >> "$rf"
  ho_ledger_append remarks-fix-round lane "$lane" round "$((rounds + 1))" sha "$sha"
  printf 'fix round %s of %s: fix each remark or decline it with a written reason, finalize again, then a fresh validator checks the new head. The change merges only on a clean "passed".\n' "$((rounds + 1))" "$max"
}

ho_vf_reviews() {
  local lane=${1-} mode pr ticket repo reviews bots steps prof login body trusted=0 untrusted=0 act f
  [ $# -eq 1 ] || { ho_vf_usage; return 64; }
  ho_loop_lane_ok "$lane" || return 65
  mode=$(ho_cfg '.external_review' react) || return 78
  case $mode in react | ask | ignore) ;; *) ho_vf_err "external_review must be react, ask or ignore: $mode"; return 78 ;; esac
  if [ "$mode" = ignore ]; then
    ho_ledger_append reviews-ignored lane "$lane"
    printf 'external review is set to ignore; nothing is done\n'
    return 0
  fi
  pr=$(jq -r '.pr // ""' "$(ho_ship_rec "$lane")" 2>/dev/null) || pr=""
  [ -n "$pr" ] || { ho_vf_err "lane $lane has no PR"; return 65; }
  ticket=$(ho_vf_ticket "$lane")
  repo=${HO_TICKETS_REPO:-}
  reviews=$(gh pr view "$pr" --json reviews $(ho_ship_gh_repo) 2>/dev/null | jq -c '[.reviews // [] | .[] | {login: (.author.login // ""), body: (.body // "")}]' 2>/dev/null) \
    || { ho_vf_err "the reviews of PR #$pr cannot be read"; return 65; }
  bots=$(ho_cfg '.external_review_bots | if type == "array" then map(strings) | join(" ") else "" end' '') || return 78
  # react needs a step that can act and a profile that may push; otherwise it is ask.
  if [ "$mode" = react ]; then
    steps=$(ho_vf_steps "$(ho_vf_flow)")
    prof=$(ho_au_profile) || return 78
    if ! printf '%s\n' "$steps" | grep -qx review-comments || [ "$(printf '%s' "$prof" | jq -r .push)" != true ]; then
      mode=ask
      ho_ledger_append reviews-react-as-ask lane "$lane" reason "the flow has no review-comments step or the profile allows no push"
    fi
  fi
  act="$HO_RUN_DIR/verify/$lane.reviews.md"
  mkdir -p "$HO_RUN_DIR/verify"
  : > "$act"
  while IFS=$'\t' read -r login body; do
    [ -n "$login" ] || continue
    if case " $bots " in *" $login "*) true ;; *) false ;; esac || [ "$(ho_tk_access "$login" "$repo")" = writer ]; then
      trusted=$((trusted + 1))
      printf -- '- %s: %s\n' "$login" "$body" >> "$act"
    else
      untrusted=$((untrusted + 1))
      f="$HO_RUN_DIR/verify/$lane.untrusted.md"
      printf 'A review on PR #%s by %s was recorded and not applied: the author has no confirmed write access and is not a listed review bot.\n' "$pr" "$login" > "$f"
      [ -z "$ticket" ] || ho_tickets comment "$ticket" "$f" --role orchestrator >/dev/null || true
      ho_ledger_append review-untrusted lane "$lane" pr "$pr" author "$login"
    fi
  done < <(printf '%s' "$reviews" | jq -r '.[] | [.login, (.body | gsub("[\r\n\t]"; " "))] | @tsv')
  ho_ledger_append reviews-read lane "$lane" pr "$pr" trusted "$trusted" untrusted "$untrusted" mode "$mode"
  [ "$trusted" -gt 0 ] || { printf 'no review from a trusted author on PR #%s (%s recorded, not applied)\n' "$pr" "$untrusted"; return 0; }
  if [ "$mode" = ask ]; then
    [ -z "$ticket" ] || { printf 'Review comments arrived on PR #%s. Should the harness look at them or ignore them?\n' "$pr"; cat "$act"; } > "$HO_RUN_DIR/verify/$lane.ask.md"
    [ -z "$ticket" ] || ho_tickets comment "$ticket" "$HO_RUN_DIR/verify/$lane.ask.md" --role orchestrator >/dev/null || true
    ho_vf_human "$lane" "$ticket" "review comments on PR #$pr: look at them or ignore them"
    return
  fi
  printf 'react: %s trusted review comment(s) on PR #%s for the review-comments step; fix what you accept and record each declined one with a reason. A fix needs a fresh validator pass on the new commit.\n' "$trusted" "$pr"
  ho_tk_fence "reviews of PR #$pr" < "$act"
}

ho_verify_main() {
  [ $# -ge 2 ] || { ho_vf_usage; exit 64; }
  ho_run_open "$1"
  ho_session_bind_project || exit $?
  ho_tk_bind_project_dir
  local verb=$2 rc=0
  shift 2
  case $verb in
    record) ho_vf_record "$@" || rc=$? ;;
    tests) ho_vf_tests "$@" || rc=$? ;;
    block) ho_vf_block "$@" || rc=$? ;;
    comment) ho_vf_comment "$@" || rc=$? ;;
    remarks) ho_vf_remarks "$@" || rc=$? ;;
    reviews) ho_vf_reviews "$@" || rc=$? ;;
    *) ho_vf_usage; rc=64 ;;
  esac
  exit "$rc"
}
