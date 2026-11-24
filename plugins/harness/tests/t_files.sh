# Design Rebuild reuse list: the safe-file and path helpers.
HO_ROOT=$HO_PLUGIN_ROOT
. "$HO_PLUGIN_ROOT/lib/common.sh"
. "$HO_PLUGIN_ROOT/lib/files.sh"

# ho_atomic_write: whole content or nothing, no temp file left behind.
mkdir aw
printf 'old\n' > aw/f
printf 'new line 1\nnew line 2\n' | ho_atomic_write aw/f
assert_eq "Rebuild reuse files: atomic write replaces the content" "new line 1
new line 2" "$(cat aw/f)"
assert_eq "Rebuild reuse files: atomic write leaves no temp file" "f" "$(ls -A aw)"
rc=0; printf 'x' | ho_atomic_write "$PWD/no-such-dir/f" 2>/dev/null || rc=$?
assert_eq "Rebuild reuse files: atomic write into a missing folder fails" "1" "$rc"

# ho_assert_abs
assert_exit "Rebuild reuse files: an absolute path passes" 0 ho_assert_abs /tmp/x what
assert_exit "Rebuild reuse files: a relative path is refused" 65 ho_assert_abs rel/x what
assert_exit "Rebuild reuse files: an empty path is refused" 65 ho_assert_abs "" what

# ho_sanitize_path keeps only absolute components, in order, and never globs.
assert_eq "Rebuild reuse files: PATH keeps only absolute components" "/a:/b/c:/opt/*/bin" "$(ho_sanitize_path "/a::.:rel:/b/c:/opt/*/bin:")"
assert_eq "Rebuild reuse files: an empty PATH stays empty" "" "$(ho_sanitize_path "")"

# ho_assert_safe_cwd <dir> <project>
proj=$(cd -P "$PWD" && pwd)/proj
mkdir -p "$proj/sub" other
git -C "$proj" init -q
git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$proj" worktree add -q "$PWD/wt" -b lane 2>/dev/null
git init -q other
assert_exit "Rebuild reuse files: a folder inside the project is a safe cwd" 0 ho_assert_safe_cwd "$proj/sub" "$proj"
assert_exit "Rebuild reuse files: the project itself is a safe cwd" 0 ho_assert_safe_cwd "$proj" "$proj"
assert_exit "Rebuild reuse files: a linked worktree of the project repo is a safe cwd" 0 ho_assert_safe_cwd "$PWD/wt" "$proj"
assert_exit "Rebuild reuse files: an unrelated repo outside the project is refused" 65 ho_assert_safe_cwd "$PWD/other" "$proj"
assert_exit "Rebuild reuse files: / is refused" 65 ho_assert_safe_cwd / "$proj"
assert_exit "Rebuild reuse files: HOME is refused" 65 ho_assert_safe_cwd "$HOME" "$HOME"
assert_exit "Rebuild reuse files: a relative cwd is refused" 65 ho_assert_safe_cwd proj "$proj"
assert_exit "Rebuild reuse files: a missing cwd is refused" 65 ho_assert_safe_cwd "$PWD/missing" "$proj"
assert_exit "Rebuild reuse files: a .. escape from the project is refused" 65 ho_assert_safe_cwd "$proj/sub/../../other" "$proj"
ln -s "$PWD/other" "$proj/link-out"
assert_exit "Rebuild reuse files: a symlink out of the project is refused" 65 ho_assert_safe_cwd "$proj/link-out" "$proj"

# A separate git dir that points into the project is not a genuine worktree.
mkdir spoof
printf 'gitdir: %s\n' "$proj/.git" > spoof/.git
assert_exit "Rebuild reuse files: a spoofed git dir outside the project is refused" 65 ho_assert_safe_cwd "$PWD/spoof" "$proj"
