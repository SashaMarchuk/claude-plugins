# shellcheck shell=bash
# Pre-trust needs the person's consent (PR #97 review, the Codex security finding on the
# launch): a working folder is trusted for the runtime only when the person has already
# trusted the project folder there, and the project folder itself is never written. Reuse
# list: pre-trust inside the project only. H-099: nothing is ever answered on the screen.
# Also from that review: parallel pre-trusts keep every entry, a folder that is already
# trusted is not rewritten, and the worktree check holds against a hand-made .git file, a
# worktree of a repository nested in the project and a git variable in the environment.
. "$HO_TESTS_DIR/sessions-setup.sh"

tf="$HOME/.claude.json"
ledger="$run/ledger.jsonl"
pt() { "$h" screen "$run" pretrust "$@" >/dev/null 2>&1; }
# entry <folder>: 1 when the trust file names that folder (physical path), else 0.
entry() { jq --arg p "$(cd "$1" && pwd -P)" '[.projects // {} | to_entries[] | select(.key == $p)] | length' "$tf"; }
count() { jq -s --arg k "$1" '[.[] | select(.kind == $k)] | length' "$ledger"; }
inode() { ls -i "$tf" | awk '{ print $1 }'; }

git -C "$proj" init -q
git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$proj" worktree add -q "$base/lane" -b lane 2>/dev/null
mkdir -p "$base/lane/sub"

# ---- consent: the project folder must already be trusted ------------------------------
printf '{}\n' > "$tf"
rc=0; pt "$proj/src" || rc=$?
assert_eq "H-099 reuse list: with the project not trusted, pre-trust refuses (exit 77)" "77" "$rc"
assert_eq "H-099 reuse list: with the project not trusted, nothing is written for the folder" "0" "$(entry "$proj/src")"
rc=0; pt "$proj" || rc=$?
assert_eq "H-099 reuse list: the project folder itself is never trusted by the harness (exit 77)" "77" "$rc"
assert_eq "H-099 reuse list: no entry appears for the project folder" "0" "$(entry "$proj")"

rc=0; launch nc1 >/dev/null 2>&1 || rc=$?
assert_eq "H-099 reuse list: a launch in a project that is not trusted stops (exit 77)" "77" "$rc"
assert_eq "H-099 reuse list: that launch records one owner action" "1" "$(count owner-action)"
assert_eq "H-099 reuse list: the owner action asks to open the project once" "1" \
  "$(jq -s '[.[] | select(.kind == "owner-action" and .command == "open the project once in the runtime and accept its trust question")] | length' "$ledger")"
assert_eq "H-099 reuse list: that launch starts no runtime" "" "$(grep -F 'ho-worker-nc1' "$HO_FAKE_CLAUDE_LOG" 2>/dev/null || true)"
assert_eq "H-099 reuse list: that launch leaves no registry record" "no" "$([ -e "$run/sessions/nc1.json" ] && echo yes || echo no)"
assert_eq "H-099 reuse list: that launch writes no trust entry" "0" "$(entry "$proj/src")"

# ---- with consent ------------------------------------------------------------------------
trust_root
before=$(jq -c . "$tf")
assert_exit "H-099 reuse list: the project folder, already trusted, needs no write (exit 0)" 0 "$h" screen "$run" pretrust "$proj"
assert_eq "H-099 reuse list: the project's own entry is left as the person wrote it" "$before" "$(jq -c . "$tf")"
assert_exit "H-099 reuse list: a folder inside a trusted project is pre-trusted" 0 "$h" screen "$run" pretrust "$proj/src"
assert_eq "H-099 reuse list: its entry is written" "1" "$(entry "$proj/src")"
assert_exit "H-099 reuse list: a folder in a genuine worktree of the project is pre-trusted" 0 "$h" screen "$run" pretrust "$base/lane/sub"
assert_eq "H-099 reuse list: the worktree entry is written" "1" "$(entry "$base/lane/sub")"

# Already trusted: no rewrite of the runtime's state file (the move would change its inode).
ino=$(inode)
assert_exit "H-099 reuse list: pre-trust of a folder already trusted succeeds" 0 "$h" screen "$run" pretrust "$proj/src"
assert_eq "H-099 reuse list: a folder already trusted is not rewritten" "$ino" "$(inode)"

# ---- parallel launches keep every entry ---------------------------------------------------
pids=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  mkdir -p "$proj/par/p$i"
  "$h" screen "$run" pretrust "$proj/par/p$i" >/dev/null 2>&1 &
  pids="$pids $!"
done
fails=0
for p in $pids; do wait "$p" || fails=$((fails + 1)); done
assert_eq "H-099 reuse list: 12 parallel pre-trusts all succeed" "0" "$fails"
n=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do n=$((n + $(entry "$proj/par/p$i"))); done
assert_eq "H-099 reuse list: all 12 parallel entries survive" "12" "$n"

# ---- the worktree check cannot be steered from outside -----------------------------------
admin=$(cd "$(git -C "$base/lane" rev-parse --git-dir)" && pwd -P)
mkdir -p "$base/fake"
printf 'gitdir: %s\n' "$admin" > "$base/fake/.git"
rc=0; pt "$base/fake" || rc=$?
assert_eq "H-099 reuse list: a hand-made .git file outside the project is refused (exit 65)" "65" "$rc"
assert_eq "H-099 reuse list: nothing is written for the hand-made .git folder" "0" "$(entry "$base/fake")"

mkdir -p "$proj/nested"
git -C "$proj/nested" init -q
git -C "$proj/nested" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$proj/nested" worktree add -q "$base/nested-lane" -b nl 2>/dev/null
rc=0; pt "$base/nested-lane" || rc=$?
assert_eq "H-099 reuse list: a worktree of a repository nested in the project is refused (exit 65)" "65" "$rc"
assert_eq "H-099 reuse list: nothing is written for that worktree" "0" "$(entry "$base/nested-lane")"

mkdir -p "$base/plain"
rc=0; GIT_DIR="$admin" GIT_WORK_TREE="$base/plain" "$h" screen "$run" pretrust "$base/plain" >/dev/null 2>&1 || rc=$?
assert_eq "H-099 reuse list: a git variable in the environment does not make a worktree (exit 65)" "65" "$rc"
assert_eq "H-099 reuse list: nothing is written for that folder" "0" "$(entry "$base/plain")"
