#!/usr/bin/env bash
# Regression harness for the /ig-dm-export-analyzer plugin.
#
# Two layers:
#   1. Contract assertions over the published files — the plugin stays
#      config-driven, path-portable (${CLAUDE_PLUGIN_ROOT}), and free of any
#      trace of the private export it was originally built against.
#   2. A live end-to-end pipeline run in a sandboxed temp dir against a
#      synthetic Instagram DYI export fixture (mojibake, message_N pagination,
#      date filtering, manual exclusion, ordering, labeling, verification).
#      No network, no credentials, no ffmpeg: the fixture carries no media and
#      the run uses stt.provider = none.
#
# Exits 0 on all-pass, 1 on any FAIL. Final line matches the master-runner
# grep: "PASS=<N>  FAIL=<M>".
#
# Usage:  bash plugins/ig-dm-export-analyzer/tests/run.sh
# Deps:   POSIX shell + grep + python3 (functional layer is skipped without it).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$PLUGIN_DIR/../.." && pwd)

SKILL="$PLUGIN_DIR/skills/run/SKILL.md"
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"
CONFIG_TPL="$PLUGIN_DIR/templates/config.example.yaml"
SCRIPTS="$PLUGIN_DIR/scripts"
README_P="$PLUGIN_DIR/README.md"
CHANGELOG="$PLUGIN_DIR/CHANGELOG.md"
LICENSE_P="$PLUGIN_DIR/LICENSE"
MARKET="$REPO_ROOT/.claude-plugin/marketplace.json"
README="$REPO_ROOT/README.md"
RUNALL="$REPO_ROOT/tests/run-all.sh"

PY_FILES=(igdm_common.py build_manifest.py transcribe.py build_chats.py verify.py
          run_pipeline.py fix_mojibake.py)

PASS=0
FAIL=0
FAIL_MSGS=()

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

json_valid() {
  local f="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; return $?
  fi
  if command -v jq >/dev/null 2>&1; then jq -e . "$f" >/dev/null 2>&1; return $?; fi
  return 0
}

# ============================================================ Files exist

for f in "$SKILL" "$MANIFEST" "$CONFIG_TPL" "$README_P" "$CHANGELOG" "$LICENSE_P"; do
  if [[ -f "$f" ]]; then pass "FILE: exists ${f#$PLUGIN_DIR/}"
  else fail "FILE: ${f#$PLUGIN_DIR/}" "missing"; fi
done

for f in "${PY_FILES[@]}"; do
  if [[ -f "$SCRIPTS/$f" ]]; then pass "FILE: exists scripts/$f"
  else fail "FILE: scripts/$f" "missing"; fi
done

# ============================================================ Manifest

if json_valid "$MANIFEST"; then pass "MANIFEST: plugin.json is valid JSON"
else fail "MANIFEST: plugin.json" "invalid JSON"; fi

if grep -q '"name": *"ig-dm-export-analyzer"' "$MANIFEST"; then
  pass "MANIFEST: name == ig-dm-export-analyzer (matches dir + marketplace entry)"
else fail "MANIFEST: name" "name is not ig-dm-export-analyzer"; fi

if grep -q '"version": *"0\.' "$MANIFEST" && grep -q '"description": *"(beta)' "$MANIFEST"; then
  pass "MANIFEST: 0.x version carries the (beta) description prefix"
else fail "MANIFEST: beta" "0.x version without a (beta) description prefix"; fi

if grep -q '"license": *"MIT"' "$MANIFEST" && grep -q "MIT License" "$LICENSE_P"; then
  pass "MANIFEST: MIT license declared and shipped"
else fail "MANIFEST: license" "MIT license missing from plugin.json or LICENSE"; fi

# ============================================================ Skill frontmatter

if grep -q "^name: run" "$SKILL"; then
  pass "SKILL: frontmatter name == run (invoked as /ig-dm-export-analyzer:run)"
else fail "SKILL: name" "frontmatter name does not match the skills/run/ directory"; fi

if grep -q "^description:.*Instagram" "$SKILL" \
   && grep -q "^description:.*Use when the user types /ig-dm-export-analyzer:run" "$SKILL"; then
  pass "SKILL: description leads with WHAT, then an explicit trigger list"
else fail "SKILL: description" "description missing the WHAT-then-trigger shape"; fi

# ============================================================ Path portability

if grep -q '\${CLAUDE_PLUGIN_ROOT}' "$SKILL"; then
  pass "SKILL: references plugin files via \${CLAUDE_PLUGIN_ROOT}"
else fail "SKILL: plugin root" "no \${CLAUDE_PLUGIN_ROOT} reference"; fi

HARDCODED=$(grep -rn "/Users/\|/home/[a-z]" "$SKILL" "$CONFIG_TPL" "$SCRIPTS"/*.py "$README_P" 2>/dev/null || true)
if [[ -z "$HARDCODED" ]]; then
  pass "PATHS: no hardcoded absolute home paths anywhere in the plugin"
else fail "PATHS: hardcoded" "$(echo "$HARDCODED" | head -3 | tr '\n' '|')"; fi

# ============================================================ User state lives outside the plugin

if grep -qE '^output:' "$CONFIG_TPL" && grep -q 'cfg\["output"\]\["dir"\]' "$SCRIPTS/igdm_common.py" \
   && grep -q "output.dir" "$SKILL"; then
  pass "STATE: results go to the user-chosen output.dir, never inside the plugin"
else fail "STATE: output dir" "output.dir is not the single configured result location"; fi

if grep -q "Destination must be outside the source tree" "$SCRIPTS/fix_mojibake.py"; then
  pass "STATE: fix_mojibake.py refuses to write inside the export"
else fail "STATE: export write guard" "fix_mojibake.py missing the in-tree write guard"; fi

# ============================================================ Credentials are config-resolved, never embedded

if grep -q "env_var" "$SCRIPTS/igdm_common.py" && grep -q "env_file" "$SCRIPTS/igdm_common.py" \
   && grep -q "key_file" "$SCRIPTS/igdm_common.py"; then
  pass "CREDS: resolved from env var -> .env file -> key file, all named in config"
else fail "CREDS: resolution" "credential resolution chain missing from igdm_common.py"; fi

SECRETS=$(grep -rniE "sk-[a-z0-9]{16}|api[_-]?key *[:=] *[\"'][a-z0-9]{12}" \
          "$SKILL" "$CONFIG_TPL" "$SCRIPTS"/*.py "$README_P" 2>/dev/null || true)
if [[ -z "$SECRETS" ]]; then pass "CREDS: no credential values committed"
else fail "CREDS: secret value" "$(echo "$SECRETS" | head -2 | tr '\n' '|')"; fi

# ============================================================ Dependency honesty

if grep -q "^## Dependencies" "$SKILL" && grep -q "requests" "$SKILL" && grep -q "pyyaml\|PyYAML" "$SKILL"; then
  pass "SKILL: documents the requests (soniox-only) / pyyaml (YAML-only) dependencies"
else fail "SKILL: dependencies" "no Dependencies note naming requests + pyyaml"; fi

if grep -q "except ImportError" "$SCRIPTS/transcribe.py" && grep -q "pip install requests" "$SCRIPTS/transcribe.py"; then
  pass "SCRIPT: soniox provider fails with an actionable message when requests is absent"
else fail "SCRIPT: requests guard" "transcribe.py imports requests without an actionable guard"; fi

if grep -q "pip install pyyaml" "$SCRIPTS/igdm_common.py"; then
  pass "SCRIPT: YAML config without PyYAML fails with an actionable message"
else fail "SCRIPT: pyyaml guard" "igdm_common.py missing the actionable PyYAML message"; fi

# ============================================================ Labeling contract (load-bearing, do not weaken)

if grep -q "THE PERSON DID NOT WRITE THIS" "$SCRIPTS/build_chats.py" \
   && grep -q "⟦" "$SCRIPTS/build_chats.py" \
   && grep -q "_legend" "$SCRIPTS/build_chats.py" \
   && grep -q '"generated"' "$SCRIPTS/build_chats.py"; then
  pass "LABELING: all four redundant markers emitted (header, ⟦⟧, generated, _legend)"
else fail "LABELING: markers" "one of the four redundant markers is missing from build_chats.py"; fi

if grep -q 'm\["generated"\] != has_marker' "$SCRIPTS/verify.py"; then
  pass "LABELING: verify.py enforces generated == true <=> ⟦ marker, both directions"
else fail "LABELING: invariant" "verify.py no longer enforces the generated/marker invariant"; fi

if grep -q "never translated" "$SCRIPTS/build_chats.py" && grep -q "never translated" "$SKILL"; then
  pass "LABELING: content-is-never-translated rule documented in code and skill"
else fail "LABELING: translation rule" "missing the never-translate-content rule"; fi

# ============================================================ NO PERSONAL DATA LEAK
# The plugin was generalized from a one-off run over a private export. These two
# scans are the gate that no trace of that run (or of any local machine) came
# along. plugin.json / LICENSE author attribution is legitimate and not scanned.

LEAK_FILES=("$SKILL" "$CONFIG_TPL" "$README_P" "$CHANGELOG" "$SCRIPTS"/*.py)

IDENTITY_HITS=$(grep -rniE "sasha-marchuk|sashko|speedandfunction|NasAnanas|/Users/|spikes/voice-transcription" \
                "${LEAK_FILES[@]}" 2>/dev/null || true)
if [[ -z "$IDENTITY_HITS" ]]; then
  pass "NO-LEAK: no personal identifiers, local paths, or private-repo references"
else fail "NO-LEAK: identity" "$(echo "$IDENTITY_HITS" | head -3 | tr '\n' '|')"; fi

# Exact counts / dates from the owner's real export would fingerprint whose data
# this was tested on. Qualitative claims only.
RUN_HITS=$(grep -rniE "1,?495|16,?278|58 STT jobs|2026-08-03|2026-07-30" \
           "$SKILL" "$CONFIG_TPL" "$README_P" "$SCRIPTS"/*.py 2>/dev/null || true)
if [[ -z "$RUN_HITS" ]]; then
  pass "NO-LEAK: no exact counts or dates from the private export it was tested on"
else fail "NO-LEAK: private run" "$(echo "$RUN_HITS" | head -3 | tr '\n' '|')"; fi

# ============================================================ Python syntax

if command -v python3 >/dev/null 2>&1; then
  for f in "${PY_FILES[@]}"; do
    if python3 -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$SCRIPTS/$f" 2>/dev/null; then
      pass "SYNTAX: scripts/$f parses as valid Python"
    else fail "SYNTAX: scripts/$f" "ast.parse failed"; fi
  done
else
  echo "NOTE: python3 not found — skipping the functional layer"
fi

# ============================================================ Functional layer

if command -v python3 >/dev/null 2>&1; then
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---- config validation: bad configs are rejected loudly, never guessed at ----
VALIDATION=$(python3 - "$SCRIPTS" "$TMP" <<'PY' 2>&1
import json, sys
from pathlib import Path

scripts, tmp = sys.argv[1], Path(sys.argv[2])
sys.path.insert(0, scripts)
from igdm_common import load_config, resolve_credential, unmojibake, walk

export = tmp / "vexport" / "your_instagram_activity" / "messages" / "inbox" / "t_1"
export.mkdir(parents=True, exist_ok=True)
(export / "message_1.json").write_text('{"messages": []}', encoding="utf-8")
text_root = str(tmp / "vexport")

def expect_exit(name, cfg, needle):
    p = tmp / f"cfg_{name}.json"
    p.write_text(json.dumps(cfg), encoding="utf-8")
    try:
        load_config(p)
    except SystemExit as e:
        print(f"{'OK' if needle in str(e) else 'BAD'} {name} :: {e}")
    else:
        print(f"BAD {name} :: no SystemExit")

expect_exit("no_text_root", {"output": {"dir": str(tmp / "o")}},
            "export.text_root is required")
expect_exit("no_output", {"export": {"text_root": text_root}},
            "output.dir is required")
expect_exit("bad_provider", {"export": {"text_root": text_root},
                             "output": {"dir": str(tmp / "o")},
                             "stt": {"provider": "gpt-ears"}},
            "unknown stt.provider")
expect_exit("photos_analyze", {"export": {"text_root": text_root},
                               "output": {"dir": str(tmp / "o")},
                               "photos": {"analyze": True}},
            "not implemented")
expect_exit("range_inverted", {"export": {"text_root": text_root},
                               "output": {"dir": str(tmp / "o")},
                               "filter": {"start": "2026-02-01T00:00:00Z",
                                          "end": "2026-01-01T00:00:00Z"}},
            "must be earlier than")
expect_exit("not_an_export", {"export": {"text_root": str(tmp)},
                              "output": {"dir": str(tmp / "o")}},
            "does not look like an Instagram messages export")

# credential resolution order: env var wins, nothing configured fails loudly
import os
os.environ["IGDM_TEST_KEY"] = "from-env"
got = resolve_credential({"env_var": "IGDM_TEST_KEY"})
print(("OK" if got == "from-env" else "BAD") + " cred_env")
try:
    resolve_credential({"env_var": "IGDM_TEST_ABSENT"})
except SystemExit as e:
    print(("OK" if "not found" in str(e) else "BAD") + " cred_missing")
else:
    print("BAD cred_missing :: no SystemExit")

# mojibake fix: repairs, is idempotent, and is a no-op on clean ASCII
broken = "привіт".encode("utf-8").decode("latin-1")
print(("OK" if unmojibake(broken) == "привіт" else "BAD") + " mojibake_repair")
print(("OK" if unmojibake(unmojibake(broken)) == "привіт" else "BAD") + " mojibake_idempotent")
print(("OK" if unmojibake("plain ascii") == "plain ascii" else "BAD") + " mojibake_noop")
print(("OK" if walk({broken: [broken]}) == {"привіт": ["привіт"]} else "BAD") + " mojibake_walk")
PY
)
val_rc=$?
val_bad=$(echo "$VALIDATION" | grep -c '^BAD')
if [[ "$val_rc" -eq 0 && "$val_bad" -eq 0 ]] && [[ $(echo "$VALIDATION" | grep -c '^OK') -eq 12 ]]; then
  pass "FUNC: config validation, credential resolution, and mojibake fix all behave (12 checks)"
else
  fail "FUNC: unit checks" "rc=$val_rc bad=$val_bad :: $(echo "$VALIDATION" | grep '^BAD' | head -2 | tr '\n' '|')"
fi

# ---- build the synthetic export fixture ----
python3 - "$TMP" <<'PY' >/dev/null 2>&1
import json, sys
from pathlib import Path

tmp = Path(sys.argv[1])
msgs = tmp / "export" / "your_instagram_activity" / "messages"

def moji(s):
    """Write text the way Meta's DYI export does: UTF-8 bytes read as Latin-1."""
    return s.encode("utf-8").decode("latin-1")

def thread(source, slug, pages, title, participants):
    d = msgs / source / slug
    d.mkdir(parents=True, exist_ok=True)
    for n, messages in enumerate(pages, start=1):
        (d / f"message_{n}.json").write_text(json.dumps({
            "participants": [{"name": moji(p)} for p in participants],
            "messages": messages,
            "title": moji(title),
            "is_still_participant": True,
        }, ensure_ascii=False), encoding="utf-8")

OWNER = "Export Owner"
# Raw export order is newest-first, split across message_N.json pages.
thread("inbox", "alice_1a2b3c", [
    [  # page 1 — newest
        {"sender_name": moji("Alice Example"), "timestamp_ms": 1767484800000},
        {"sender_name": moji(OWNER), "timestamp_ms": 1767398400000,
         "content": moji("reply from the owner")},
        {"sender_name": moji("Alice Example"), "timestamp_ms": 1767312000000,
         "content": moji("привіт, як справи?"),
         "reactions": [{"reaction": moji("❤"), "actor": moji(OWNER)}]},
    ],
    [  # page 2 — older
        {"sender_name": moji("Alice Example"), "timestamp_ms": 1767225600000,
         "content": moji("first message inside the range")},
        {"sender_name": moji(OWNER), "timestamp_ms": 1767139200000,
         "content": moji("this one predates the filter")},
    ],
], "Alice Example", ["Alice Example", OWNER])

thread("inbox", "spam_9z8y7x", [[
    {"sender_name": moji("Promo Account"), "timestamp_ms": 1767312000000,
     "content": moji("buy now")},
    {"sender_name": moji(OWNER), "timestamp_ms": 1767398400000, "content": moji("no")},
]], "Promo Account", ["Promo Account", OWNER])

thread("message_requests", "olduser_5f6g", [[
    {"sender_name": moji("Old Contact"), "timestamp_ms": 1700000000000,
     "content": moji("hello from 2023")},
]], "Old Contact", ["Old Contact", OWNER])

(tmp / "run.json").write_text(json.dumps({
    "export": {"text_root": str(msgs), "owner_name": OWNER, "fix_mojibake": True},
    "filter": {"start": "2026-01-01T00:00:00Z", "end": None,
               "exclude_thread_slugs": ["spam_9z8y7x"]},
    "stt": {"provider": "none"},
    "output": {"dir": str(tmp / "out")},
    "verify": {"expect": {"kept_threads": 1, "total_threads": 3,
                          "messages_written": 4, "stt_jobs": 0}},
}), encoding="utf-8")
PY
fixture_rc=$?
if [[ "$fixture_rc" -eq 0 && -f "$TMP/run.json" ]]; then
  pass "E2E: synthetic DYI export fixture built (3 threads, paginated, mojibake-encoded)"
else fail "E2E: fixture" "could not build the fixture (rc=$fixture_rc)"; fi

# ---- run the whole pipeline against it ----
E2E_OUT=$(python3 "$SCRIPTS/run_pipeline.py" "$TMP/run.json" 2>&1)
e2e_rc=$?
if [[ "$e2e_rc" -eq 0 ]]; then
  pass "E2E: run_pipeline.py completes all four steps, exit 0 (no network, no ffmpeg)"
else fail "E2E: pipeline" "exit=$e2e_rc :: $(echo "$E2E_OUT" | tail -4 | tr '\n' '|')"; fi

if echo "$E2E_OUT" | grep -q "Reconciliation:.*OK"; then
  pass "E2E: Step 1 reconciles every scanned message (in-scope + excluded + tail)"
else fail "E2E: reconciliation" "no OK reconciliation line in Step 1 output"; fi

# ---- assert the output is what the contract promises ----
ASSERTS=$(python3 - "$TMP/out" <<'PY' 2>&1
import json, sys
from pathlib import Path

out = Path(sys.argv[1])
def ok(name, cond, detail=""):
    print(("OK " if cond else "BAD ") + name + (f" :: {detail}" if not cond and detail else ""))

chats = sorted((out / "chats").glob("*.json"))
ok("one_chat_file", len(chats) == 1, f"{[c.name for c in chats]}")
chat = json.loads(chats[0].read_text(encoding="utf-8"))
msgs = chat["messages"]

ok("kept_slug", chats[0].stem == "alice_1a2b3c", chats[0].stem)
ok("in_scope_only", len(msgs) == 4, f"{len(msgs)} messages")
ok("chronological", [m["ts_ms"] for m in msgs] == sorted(m["ts_ms"] for m in msgs))
ok("pagination_merged", {m["src_file"] for m in msgs} == {"message_1.json", "message_2.json"},
   f"{sorted({m['src_file'] for m in msgs})}")
ok("date_filter_strict", all(m["ts_iso"] >= "2026-01-01" for m in msgs))

# mojibake: repaired on the way in, and no residue on the way out
raw = chats[0].read_text(encoding="utf-8")
ok("mojibake_repaired", "привіт, як справи?" in raw)
ok("no_mojibake_residue", "Ð" not in raw and "Ñ" not in raw)
ok("no_unicode_escapes", "\\u04" not in raw)

# direction + roles derive from the configured owner
by_dir = {m["dir"] for m in msgs}
ok("both_directions", by_dir == {"in", "out"}, f"{by_dir}")
ok("owner_role", all((m["role"] == "owner") == (m["dir"] == "out") for m in msgs))

# labeling contract: nothing here is machine-generated, so no message carries the
# marker (the _legend block always explains it, so only `text` is checked)
ok("no_false_generated", not any(m["generated"] for m in msgs))
ok("no_stray_marker", not any("⟦" in m["text"] for m in msgs))
ok("legend_explains_marker", "⟦" in chat["_legend"]["marker"])
ok("headers_present", all(m["header"] and m["text"] for m in msgs))
ok("legend_complete",
   set(chat["_legend"]) >= {"marker", "generated", "reliability", "language"})

# a message with no content is an explicit placeholder, never silently dropped
types = {m["type"] for m in msgs}
ok("unavailable_placeholder", "unavailable" in types, f"{sorted(types)}")
ok("reactions_kept", any(m.get("reactions") for m in msgs))

index = json.loads((out / "index.json").read_text(encoding="utf-8"))
rows = {r["slug"]: r for r in index["threads"]}
ok("index_covers_all", len(rows) == 3, f"{sorted(rows)}")
ok("manual_exclusion_traceable",
   rows["spam_9z8y7x"]["reason"] == "excluded_manual_thread",
   f"{rows['spam_9z8y7x']}")
ok("out_of_range_traceable",
   rows["olduser_5f6g"]["reason"] == "no_messages_in_date_range",
   f"{rows['olduser_5f6g']}")
ok("excluded_have_no_chat_file",
   rows["spam_9z8y7x"]["chat_file"] is None and rows["olduser_5f6g"]["chat_file"] is None)
ok("index_is_filterable",
   all(k in rows["alice_1a2b3c"] for k in
       ("first_ts_iso", "last_ts_iso", "in_scope_message_count", "counts_by_type")))
ok("stt_provider_recorded", index["stt_provider"] == "none")

ver = json.loads((out / "verification_results.json").read_text(encoding="utf-8"))
ok("verification_all_green", ver["passed"] == ver["total"],
   f"{ver['passed']}/{ver['total']}")
ok("verify_expect_asserted",
   any(c["check"].startswith("expect.kept_threads") for c in ver["checks"]))
resolved = json.loads((out / "config.resolved.json").read_text(encoding="utf-8"))
ok("resolved_config_written", resolved["_resolved"]["owner_name"] == "Export Owner")
PY
)
assert_rc=$?
assert_bad=$(echo "$ASSERTS" | grep -c '^BAD')
assert_ok=$(echo "$ASSERTS" | grep -c '^OK')
if [[ "$assert_rc" -eq 0 && "$assert_bad" -eq 0 && "$assert_ok" -eq 27 ]]; then
  pass "E2E: output honors the full contract (27 assertions: filtering, ordering, provenance, labeling, index)"
else
  fail "E2E: output contract" "rc=$assert_rc ok=$assert_ok bad=$assert_bad :: $(echo "$ASSERTS" | grep '^BAD' | head -3 | tr '\n' '|')"
fi

# ---- Steps 3-4 are free to re-run and deterministic ----
RERUN=$(python3 "$SCRIPTS/run_pipeline.py" "$TMP/run.json" --from 3 2>&1)
rerun_rc=$?
if [[ "$rerun_rc" -eq 0 ]]; then
  pass "E2E: --from 3 re-assembles and re-verifies from cached state, exit 0"
else fail "E2E: re-run" "exit=$rerun_rc :: $(echo "$RERUN" | tail -3 | tr '\n' '|')"; fi

# ---- a dry run stops after Step 1 (nothing uploaded, nothing assembled) ----
python3 - "$TMP" <<'PY' >/dev/null 2>&1
import json, sys
from pathlib import Path
tmp = Path(sys.argv[1])
cfg = json.loads((tmp / "run.json").read_text(encoding="utf-8"))
cfg["output"]["dir"] = str(tmp / "dry")
cfg["verify"] = {"expect": {}}
(tmp / "dry.json").write_text(json.dumps(cfg), encoding="utf-8")
PY
python3 "$SCRIPTS/run_pipeline.py" "$TMP/dry.json" --dry-run >/dev/null 2>&1
dry_rc=$?
if [[ "$dry_rc" -eq 0 && -f "$TMP/dry/threads.json" && ! -d "$TMP/dry/chats" ]]; then
  pass "E2E: --dry-run stops after Step 1 (scan only, no chats assembled)"
else fail "E2E: dry-run" "rc=$dry_rc threads=$([[ -f "$TMP/dry/threads.json" ]] && echo y || echo n) chats=$([[ -d "$TMP/dry/chats" ]] && echo y || echo n)"; fi

# ---- fix_mojibake.py: repairs a copy, never the original, never in-tree ----
python3 "$SCRIPTS/fix_mojibake.py" "$TMP/run.json" >/dev/null 2>&1
fixm_rc=$?
python3 "$SCRIPTS/fix_mojibake.py" "$TMP/run.json" \
  "$TMP/export/your_instagram_activity/messages/inbox/nested" >/dev/null 2>&1
intree_rc=$?
FIXED="$TMP/export/your_instagram_activity/messages_fixed/inbox/alice_1a2b3c/message_1.json"
ORIG="$TMP/export/your_instagram_activity/messages/inbox/alice_1a2b3c/message_1.json"
if [[ "$fixm_rc" -eq 0 ]] && grep -q "привіт" "$FIXED" 2>/dev/null && ! grep -q "привіт" "$ORIG" 2>/dev/null; then
  pass "FIXER: fix_mojibake.py writes a repaired sibling tree and leaves the export untouched"
else fail "FIXER: repaired copy" "rc=$fixm_rc (repaired=$FIXED)"; fi

if [[ "$intree_rc" -ne 0 ]]; then
  pass "FIXER: refuses a destination inside the source tree (never edits the export)"
else fail "FIXER: in-tree guard" "in-tree destination was accepted"; fi

# ---- soniox without requests: actionable error, not ModuleNotFoundError ----
REQ_OUT=$(python3 - "$SCRIPTS" <<'PY' 2>&1
import importlib.abc, sys
sys.path.insert(0, sys.argv[1])
sys.modules.pop("requests", None)

class Block(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname == "requests":
            raise ImportError("blocked by test")
        return None

sys.meta_path.insert(0, Block())
import transcribe

cfg = {"stt": {"provider": "soniox", "delete_remote": "skip",
               "soniox": {"base_url": "https://example.invalid",
                          "credentials": {"env_var": "IGDM_NEVER_SET"}}}}
try:
    transcribe.Soniox(cfg)
except SystemExit as e:
    msg = str(e)
    print("OK" if ("requests" in msg and "pip install requests" in msg
                   and "whisper_cpp" in msg) else f"BAD :: {msg}")
except ModuleNotFoundError as e:
    print(f"BAD :: raw ModuleNotFoundError leaked: {e}")
else:
    print("BAD :: no error raised")
PY
)
req_rc=$?
if [[ "$req_rc" -eq 0 ]] && echo "$REQ_OUT" | grep -q '^OK'; then
  pass "FUNC: missing requests yields a named, actionable error (not ModuleNotFoundError)"
else fail "FUNC: requests guard" "rc=$req_rc :: $(echo "$REQ_OUT" | head -2 | tr '\n' '|')"; fi

rm -rf "$TMP"
trap - EXIT
fi  # python3 available

# ============================================================ Marketplace + repo wiring

if json_valid "$MARKET" && grep -q '"name": *"ig-dm-export-analyzer"' "$MARKET" \
   && grep -q '"\./plugins/ig-dm-export-analyzer"' "$MARKET"; then
  pass "MARKET: marketplace.json registers ig-dm-export-analyzer with the correct source"
else fail "MARKET: registration" "not registered (or invalid JSON / wrong source)"; fi

if grep -qE "PLUGINS=\(.*ig-dm-export-analyzer.*\)" "$RUNALL"; then
  pass "RUNALL: ig-dm-export-analyzer added to the master runner PLUGINS array"
else fail "RUNALL: wiring" "not in tests/run-all.sh PLUGINS"; fi

if grep -q "plugins/ig-dm-export-analyzer" "$README"; then
  pass "README: ig-dm-export-analyzer listed in the root plugins table"
else fail "README: listing" "not in the root README plugins table"; fi

# ============================================================ Summary
TOTAL=$((PASS + FAIL))
echo
echo "=============================================================="
echo "/ig-dm-export-analyzer tests:  PASS=$PASS  FAIL=$FAIL  (TOTAL=$TOTAL)"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
