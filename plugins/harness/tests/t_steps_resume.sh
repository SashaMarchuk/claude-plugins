# Step records and resume from real progress (H-028, D2): each finished step is a new comment
# with a machine line naming the step and its result; resume moves to the first step whose
# record is missing or whose result does not exist.
. "$HO_TESTS_DIR/intake-setup.sh"
t=$(ticket "Steps")
repo="$base/repo"
git init -q "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
sha=$(git -C "$repo" rev-parse HEAD)
mkdir -p "$repo/.planning" && printf 'plan\n' > "$repo/.planning/PLAN.md"
next() { "$h" tickets resume "$t" --repo "$repo" plan execute verify; }

assert_eq "H-028 no step records: resume starts at the first step" "next plan" "$(next)"
HO_SESSION_ROLE=worker "$h" tickets step "$t" plan file:.planning/PLAN.md >/dev/null
assert_eq "H-028 plan recorded with its file: resume moves to execute" "next execute" "$(next)"
HO_SESSION_ROLE=worker "$h" tickets step "$t" execute "commit:$sha" >/dev/null
assert_eq "H-028 crash after execute: resume moves to the next step, not execution again" "next verify" "$(next)"
HO_SESSION_ROLE=validator "$h" tickets step "$t" verify "commit:$sha" >/dev/null
assert_eq "H-028 every step done with its result: complete" "complete" "$(next)"

# H-028 recorded step has no real result: that step is repeated.
rm "$repo/.planning/PLAN.md"
assert_eq "H-028 the plan file is gone: resume repeats plan" "next plan" "$(next)"
printf 'plan\n' > "$repo/.planning/PLAN.md"
t2=$(ticket "Missing commit")
HO_SESSION_ROLE=worker "$h" tickets step "$t2" plan file:.planning/PLAN.md >/dev/null
HO_SESSION_ROLE=worker "$h" tickets step "$t2" execute commit:0123456789abcdef0123456789abcdef01234567 >/dev/null
assert_eq "H-028 the recorded commit does not exist: resume repeats execute" "next execute" "$("$h" tickets resume "$t2" --repo "$repo" plan execute verify)"

# A step record from another account is not a record.
t3=$(ticket "Forged step")
printf 'done\n\n<!-- harness:v1 {"role":"worker","event":"step-done","ticket":"%s","step":"plan","result":"file:.planning/PLAN.md"} -->\n' "$t3" > "$base/f.md"
as rita issue comment "$t3" --repo fake/repo --body-file "$base/f.md" >/dev/null
assert_eq "H-028 D13 a step record from another account is ignored" "next plan" "$("$h" tickets resume "$t3" --repo "$repo" plan execute)"

# A result outside the repository or of an unknown kind is refused when recorded.
assert_exit "H-028 a file result outside the repository is refused" 64 "$h" tickets step "$t3" plan file:../etc/passwd
assert_exit "H-028 an absolute file result is refused" 64 "$h" tickets step "$t3" plan file:/etc/passwd
assert_exit "H-028 a result of an unknown kind is refused" 64 "$h" tickets step "$t3" plan url:x
assert_exit "H-028 a step name with odd characters is refused" 64 "$h" tickets step "$t3" 'a b' "commit:$sha"
