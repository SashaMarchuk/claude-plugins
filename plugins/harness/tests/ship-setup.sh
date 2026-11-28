# shellcheck shell=bash
# Shared setup for t_ship.sh and t_verify.sh (sourced; not a test file): a local bare remote, a
# project clone, the fake gh as a GitHub ticket source, and helpers that make a run with one ready
# lane and a validator verdict.
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
base=$(cd -P "$PWD" && pwd)
E="{}"
export HO_FAKE_GH_DIR="$base/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
git init -q --bare -b main "$base/remote.git"
git clone -q "$base/remote.git" "$base/proj" 2>/dev/null
proj="$base/proj"
mkdir -p "$proj/.harness" "$base/user"
printf '.harness/\n' >> "$proj/.git/info/exclude"
printf 'base\n' > "$proj/shared.txt"
git -C "$proj" add shared.txt && git -C "$proj" commit -qm base && git -C "$proj" push -q origin main
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$base/user"
cfg() { jq -n --arg p "$1" --argjson extra "${2:-$E}" '{schemaVersion: 2, autonomy: {profile: $p}} * $extra' > "$proj/.harness/config.json"; select_config "$proj"; }
user_cfg() { jq -n --argjson extra "${1:-$E}" '{schemaVersion: 2} * $extra' > "$base/user/config.json"; }
user_cfg
vsid=11111111-1111-4111-8111-111111111111
issue() { printf 'b\n' > "$base/ib"; gh issue create --repo fake/repo --title "$1" --body-file "$base/ib" --label harness:in-progress | sed 's#.*/##'; }
istate() { jq -r '"\(.state) \(.labels | map(select(startswith("harness:"))) | join(","))"' "$HO_FAKE_GH_DIR/issues/$1.json"; }
prf() { jq -r "$2" "$HO_FAKE_GH_DIR/prs/$1.json"; }
remote_sha() { git -C "$base/remote.git" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || echo none; }
n=0
# mkrun <profile> [config extra]: a run with its integration branch and one lane (one work commit
# and a finalize commit); sets run, lane, wt, sha.
mkrun() {
  n=$((n + 1))
  cfg "$1" "${2:-$E}"
  run=$("$h" run new)
  "$h" loop "$run" integration --repo "$proj" --base main --worktree "$base/int$n" >/dev/null
  lane=l$n wt="$base/w$n"
  git -C "$proj" fetch -q origin
  git -C "$proj" worktree add -q -b "lane-$n" "$wt" origin/main
  printf 'change %s\n' "$n" > "$wt/f$n.txt"
  git -C "$wt" add "f$n.txt" && git -C "$wt" commit -qm "work $n"
  git -C "$wt" commit -q --allow-empty -m "finalize($lane): done"
  sha=$(git -C "$wt" rev-parse HEAD)
  "$h" loop "$run" ready "$lane" --worktree "$wt" >/dev/null
  mkdir -p "$run/sessions"
  jq -n --arg run "$(basename "$run")" --arg sid "$vsid" '{schemaVersion: 2, run: $run, name: "val", role: "validator", session_id: $sid, status: "running"}' > "$run/sessions/val.json"
}
pass() { printf 'passed\nevidence\n' | HO_SESSION_NAME=val HO_SESSION_ID=$vsid "$h" loop "$run" verdict "$lane" --sha "$sha" >/dev/null; }
# pass_ok: the validator passes the lane and its tests are recorded as passed (what a PR needs).
pass_ok() { pass; "$h" verify "$run" tests "$lane" --total 1 --passed 1 --failed 0 --skipped 0 >/dev/null; }
ship() { "$h" ship "$run" "$@"; }
ship_rc() { local rc=0; "$h" ship "$run" "$@" >"$base/out" 2>&1 || rc=$?; echo "$rc"; }
# merge_into <branch> <how>: a person merges the lane on the remote (no-ff merge or squash).
merge_into() {
  local tmp="$base/m$n"
  git clone -q "$base/remote.git" "$tmp" 2>/dev/null
  git -C "$tmp" checkout -q "$1"
  git -C "$tmp" fetch -q origin "$(jq -r .branch "$run/ship/$lane.json")"
  if [ "$2" = squash ]; then git -C "$tmp" merge -q --squash FETCH_HEAD >/dev/null && git -C "$tmp" commit -qm "squash $lane"
  else git -C "$tmp" merge -q --no-ff -m "merge $lane" FETCH_HEAD; fi
  git -C "$tmp" push -q origin "$1"
  git -C "$tmp" rev-parse HEAD
}
pr_merged() { local f="$HO_FAKE_GH_DIR/prs/$1.json"; jq --arg m "$2" '.state = "MERGED" | .mergeCommit = {oid: $m}' "$f" > "$f.t" && mv "$f.t" "$f"; }

