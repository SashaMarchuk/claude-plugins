#!/usr/bin/env bash
# run.sh - self-contained DETERMINISTIC integration test for the claude-migrate
# RUNNABLE SPINE, with ZERO LLM calls:
#
#     bin/parse-export.cjs  ->  deterministic copy-page assembly from
#     templates/copy-page.html.template  ->  bin/verify-copy-page.cjs
#
# It exercises the SPEC §10 acceptance IDs that are reachable without a model:
#   AC-PARSE     parse-export reproduces every fixture edge; starter project
#                dropped; empty chat flagged; raw </script> preserved faithfully
#                in unit content (F1); est_tokens a positive integer; UNNN
#                sorted-uuid + stable across two runs.
#   AC-DEDUP     dedup representative = lowest idx (no false clusters here).
#   AC-PII       NONE of the users.json PII strings leak into ANY file the
#                parser writes under the run dir (grep -r).
#   AC-ESCAPE    a kept unit carrying </SCRIPT >, </script\n>, <!-- assembles
#                into the page and copies byte-exact.
#   AC-VERIFY    verify-copy-page.cjs exits 0 on the assembled page (all cards
#                byte-exact + counter/progress/persistence/reset/name/search).
#   AC-COPYFAIL  covered inside verify-copy-page.cjs (file:// non-granted branch).
#
# NOTE ON GOLDEN HTML: we do NOT hand-author a byte-golden index.html. A pinned
# HTML string is brittle (any whitespace / attribute-order drift in the shipped
# template breaks it for no real reason). Verification is BEHAVIORAL instead:
# the real bin/verify-copy-page.cjs drives the assembled page in headless
# Chromium and asserts the copied text === payloads/<id>.json byte-for-byte,
# plus structural asserts here (page written, #data parses, every payload
# present). golden-copy-page.html is intentionally omitted in favor of this.
#
# Playwright is OPTIONAL: if `node -e "require('playwright')"` fails we print
# SKIP for the browser step and still assert the page + payloads were written
# and the embedded data block parses. A missing optional runtime never fails
# the suite.
#
# Usage:  bash plugins/claude-migrate/tests/run.sh   (invokable from any cwd)

set -uo pipefail

# ------------------------------------------------------------------ locate root
# Resolve the plugin root from THIS file's location (robust to any cwd):
#   plugins/claude-migrate/tests/run.sh  ->  plugins/claude-migrate
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BIN_DIR="$PLUGIN_DIR/bin"
PARSE_CJS="$BIN_DIR/parse-export.cjs"
VERIFY_CJS="$BIN_DIR/verify-copy-page.cjs"
TEMPLATE="$PLUGIN_DIR/templates/copy-page.html.template"
FIXTURES="$SCRIPT_DIR/fixtures"

# ------------------------------------------------------------------ sandbox
SANDBOX=$(mktemp -d -t claude-migrate-tests-XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
FAIL_MSGS=()

report_pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
report_fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s -- %s\n' "$1" "$2"; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    report_pass "$name"
  else
    report_fail "$name" "expected=[$expected] actual=[$actual]"
  fi
}

assert_true() {
  # $1 name, $2 condition-string ("true"/"false" or non-empty)
  local name="$1" cond="$2" detail="${3:-}"
  if [[ "$cond" == "true" || ( "$cond" != "false" && -n "$cond" ) ]]; then
    report_pass "$name"
  else
    report_fail "$name" "$detail"
  fi
}

# ------------------------------------------------------------------ preflight
command -v node >/dev/null 2>&1 || { echo "FATAL: node not on PATH"; exit 2; }
command -v jq   >/dev/null 2>&1 || { echo "FATAL: jq not on PATH"; exit 2; }
[[ -f "$PARSE_CJS" ]]  || { echo "FATAL: missing $PARSE_CJS"; exit 2; }
[[ -f "$VERIFY_CJS" ]] || { echo "FATAL: missing $VERIFY_CJS"; exit 2; }
[[ -f "$TEMPLATE" ]]   || { echo "FATAL: missing $TEMPLATE"; exit 2; }
[[ -d "$FIXTURES" ]]   || { echo "FATAL: missing $FIXTURES"; exit 2; }

# ------------------------------------------------------------------ stage export
# Copy fixtures into a temp <export> dir; the real run NEVER touches anything but
# the sandbox. Layout matches what parse-export's export-file connector reads:
#   <export>/conversations.json
#   <export>/projects/*.json
#   <export>/memories.json
#   <export>/users.json
EXPORT="$SANDBOX/export"
mkdir -p "$EXPORT/projects"
cp "$FIXTURES/conversations.json" "$EXPORT/conversations.json"
cp "$FIXTURES/projects/P01__alpha.json" "$EXPORT/projects/P01__alpha.json"
cp "$FIXTURES/projects/P00__starter.json" "$EXPORT/projects/P00__starter.json"
cp "$FIXTURES/memories.json" "$EXPORT/memories.json"
cp "$FIXTURES/users.json" "$EXPORT/users.json"

# parse-export requires the run dir to already exist (init-first contract).
RUN="$SANDBOX/run"
mkdir -p "$RUN"

# ==================================================================== AC-PARSE
# Run the parser; capture stdout summary + exit code.
set +e
SUMMARY=$(node "$PARSE_CJS" "$EXPORT" "$RUN" 2>"$SANDBOX/parse.err")
PARSE_RC=$?
set -e
assert_eq "AC-PARSE: parse-export exits 0" "0" "$PARSE_RC"
if [[ "$PARSE_RC" -ne 0 ]]; then
  echo "---- parse stderr ----"; cat "$SANDBOX/parse.err" || true
fi

MANIFEST="$RUN/parse-manifest.json"
[[ -f "$MANIFEST" ]] \
  && report_pass "AC-PARSE: parse-manifest.json written" \
  || report_fail "AC-PARSE: parse-manifest.json written" "missing $MANIFEST"

# 4 chats in fixture; the empty chat is still a unit (it is FLAGGED looks_empty,
# not removed from the unit set), so chats_total == 4.
chats_total=$(jq -r '.chats_total' "$MANIFEST")
assert_eq "AC-PARSE: chats_total == 4" "4" "$chats_total"

# Sorted-uuid order (M1): 1111->U000, 2222->U001, 3333->U002, 4444->U003.
u000_uuid=$(jq -r '.units[0].uuid' "$MANIFEST")
u003_uuid=$(jq -r '.units[3].uuid' "$MANIFEST")
assert_eq "AC-PARSE: U000 == lowest uuid (sorted)" "11111111-1111-4111-8111-111111111111" "$u000_uuid"
assert_eq "AC-PARSE: U003 == highest uuid (sorted)" "44444444-4444-4444-8444-444444444444" "$u003_uuid"

# Starter project DROPPED, Project Alpha KEPT (projects_total == 1).
projects_total=$(jq -r '.projects_total' "$MANIFEST")
assert_eq "AC-PARSE: starter dropped, 1 project kept" "1" "$projects_total"
kept_proj_name=$(jq -r '.projects[0].name' "$MANIFEST")
assert_eq "AC-PARSE: kept project is Project Alpha" "Project Alpha" "$kept_proj_name"
# The starter project's source.json / knowledge must NOT exist anywhere.
if grep -rIl "must be dropped by the parser" "$RUN" >/dev/null 2>&1; then
  report_fail "AC-PARSE: starter project content not emitted" "starter prompt found under run dir"
else
  report_pass "AC-PARSE: starter project content not emitted"
fi
# The kept project's source.json + knowledge docs exist (PNN by sorted uuid -> P00).
PROJ_DIR=$(find "$RUN/project" -maxdepth 1 -type d -name 'P*' | sort | head -1)
[[ -n "$PROJ_DIR" && -f "$PROJ_DIR/source.json" ]] \
  && report_pass "AC-PARSE: kept project source.json staged" \
  || report_fail "AC-PARSE: kept project source.json staged" "no P*/source.json"

# Empty chat (uuid 2222 -> U001) flagged looks_empty:true in its value scaffold.
empty_flag=$(jq -r '.looks_empty' "$RUN/value/U001.value.json")
assert_eq "AC-PARSE: empty chat U001 flagged looks_empty" "true" "$empty_flag"
# Non-empty chats must NOT be flagged empty.
normal_flag=$(jq -r '.looks_empty' "$RUN/value/U000.value.json")
assert_eq "AC-PARSE: normal chat U000 not looks_empty" "false" "$normal_flag"

# est_tokens is a POSITIVE INTEGER for the long chat (uuid 4444 -> U003).
long_tokens=$(jq -r '.est_tokens' "$RUN/value/U003.value.json")
if [[ "$long_tokens" =~ ^[0-9]+$ && "$long_tokens" -gt 0 ]]; then
  report_pass "AC-PARSE: long chat U003 est_tokens positive integer ($long_tokens)"
else
  report_fail "AC-PARSE: long chat U003 est_tokens positive integer" "got [$long_tokens]"
fi
# The long chat should dominate token count (sanity: > the normal chat's).
norm_tokens=$(jq -r '.est_tokens' "$RUN/value/U000.value.json")
if [[ "$long_tokens" -gt "$norm_tokens" ]]; then
  report_pass "AC-PARSE: long chat est_tokens > normal chat est_tokens"
else
  report_fail "AC-PARSE: long chat est_tokens > normal chat est_tokens" "long=$long_tokens norm=$norm_tokens"
fi

# total_est_tokens is a positive integer.
total_tokens=$(jq -r '.total_est_tokens' "$MANIFEST")
if [[ "$total_tokens" =~ ^[0-9]+$ && "$total_tokens" -gt 0 ]]; then
  report_pass "AC-PARSE: total_est_tokens positive integer ($total_tokens)"
else
  report_fail "AC-PARSE: total_est_tokens positive integer" "got [$total_tokens]"
fi

# The </script> content unit (uuid 3333 -> U002): the parser must have folded the
# content[] text block (thinking/tool_* SKIPPED) AND preserved the raw closing-
# script sequence verbatim in the rendered unit markdown (F1 - no content escape).
U002_MD=$(find "$RUN/units/pending" -name 'U002__*.md' | head -1)
[[ -n "$U002_MD" ]] \
  && report_pass "AC-PARSE: U002 unit markdown written" \
  || report_fail "AC-PARSE: U002 unit markdown written" "no U002 md"
if [[ -n "$U002_MD" ]]; then
  # tool noise must be skipped.
  if grep -q "tool noise that must be skipped" "$U002_MD"; then
    report_fail "AC-PARSE: tool_result text skipped" "tool noise leaked into unit"
  else
    report_pass "AC-PARSE: tool_result text skipped"
  fi
  # thinking block must be skipped.
  if grep -q "be careful with the closing tag" "$U002_MD"; then
    report_fail "AC-PARSE: thinking block skipped" "thinking text leaked into unit"
  else
    report_pass "AC-PARSE: thinking block skipped"
  fi
  # attachment extracted_content folded in.
  if grep -q "prefer textContent plus JSON.parse over innerHTML" "$U002_MD"; then
    report_pass "AC-PARSE: attachment extracted_content folded in"
  else
    report_fail "AC-PARSE: attachment extracted_content folded in" "missing attachment text"
  fi
  # image ref noted (files[].file_name) as an [image existed ...] line.
  if grep -q "image existed" "$U002_MD" && grep -q "diagram.png" "$U002_MD"; then
    report_pass "AC-PARSE: image ref noted (not invented)"
  else
    report_fail "AC-PARSE: image ref noted" "missing image-existed note"
  fi
  # </script> PRESERVED RAW (F1): the unit markdown is faithful CONTENT consumed
  # downstream by distill-brief, so the parser must NOT escape it. The literal
  # "</script>" must be present, and the backslash-escaped "<\/script" form must
  # be ABSENT (escaping is the HTML-embed layer's job, applied at embed time).
  if grep -qF '</script>' "$U002_MD"; then
    report_pass "AC-PARSE: raw </script> preserved faithfully in unit md (F1)"
  else
    report_fail "AC-PARSE: raw </script> preserved in unit md" "no literal </script> in unit md"
  fi
  if grep -qF '<\/script' "$U002_MD"; then
    report_fail "AC-PARSE: no backslash-escaped <\\/script in unit md" "parser escaped content (F1 regression)"
  else
    report_pass "AC-PARSE: no backslash-escaped <\\/script in unit md (F1)"
  fi
fi

# ============================================================ AC-PARSE (stable)
# Run the parser a SECOND time into a fresh run dir and assert byte-identical
# unit markdown + value scaffolds (UNNN order + est_tokens deterministic, M1/H2).
RUN2="$SANDBOX/run2"
mkdir -p "$RUN2"
set +e
node "$PARSE_CJS" "$EXPORT" "$RUN2" >/dev/null 2>&1
RC2=$?
set -e
assert_eq "AC-PARSE: second parse exits 0" "0" "$RC2"
if diff -r "$RUN/units" "$RUN2/units" >/dev/null 2>&1 \
   && diff -r "$RUN/value" "$RUN2/value" >/dev/null 2>&1; then
  report_pass "AC-PARSE: units/ + value/ byte-identical across two runs (M1/H2)"
else
  report_fail "AC-PARSE: units/ + value/ byte-identical across two runs" "diff found"
fi

# ==================================================================== AC-DEDUP
# No two fixture chats share a normalized first-human + name, so NO unit should
# carry a duplicate representative (duplicate_representative_idx == null for all,
# is_duplicate_representative == false for all). Stable + lowest-idx contract.
dup_count=$(jq -s '[.[] | select(.duplicate_representative_idx != null)] | length' "$RUN"/value/U*.value.json)
assert_eq "AC-DEDUP: no false duplicate clusters in distinct fixtures" "0" "$dup_count"
dup_clusters=$(echo "$SUMMARY" | jq -r '.duplicate_clusters')
assert_eq "AC-DEDUP: summary duplicate_clusters == 0" "0" "$dup_clusters"

# ==================================================================== AC-PII
# users.json is read ONLY for the email hash; NONE of its clear PII may appear in
# any file the parser wrote under the run dir. Assert each PII string is absent
# (grep -r), and that the email HASH is present in the manifest (proving the
# parser DID read users.json but stored only the digest).
PII_EMAIL="casey.fixture.pii@example-fixture.test"
PII_PHONE="+1-555-0100-9999"
PII_TOKEN_PREFIX="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
PII_TOKEN_SIG="s3cr3tSignatureFixturePIIzzz"
PII_LEAK=0
for needle in "$PII_EMAIL" "$PII_PHONE" "$PII_TOKEN_PREFIX" "$PII_TOKEN_SIG" "Casey Fixture"; do
  if grep -rIF -- "$needle" "$RUN" >/dev/null 2>&1; then
    report_fail "AC-PII: PII string absent under run dir" "leaked: $needle"
    PII_LEAK=1
  fi
done
[[ "$PII_LEAK" -eq 0 ]] && report_pass "AC-PII: no users.json PII (email/phone/JWT/name) under run dir"
# The email hash IS recorded (parser read users.json but only the digest leaves).
src_hash=$(jq -r '.source_account_email_hash' "$MANIFEST")
EXPECT_HASH=$(node -e 'const c=require("crypto");process.stdout.write(c.createHash("sha256").update("casey.fixture.pii@example-fixture.test").digest("hex"))')
assert_eq "AC-PII: manifest stores ONLY the email sha256 (no clear value)" "$EXPECT_HASH" "$src_hash"

# ============================================ deterministic copy-page assembly
# Replicate the build-copy-page INLINE branch (SKILL.md §3/§5) with NO LLM:
#   - kept units = every unit NOT flagged looks_empty (the empty chat is dropped
#     from the card set, mirroring the DROP rule for empty chats).
#   - for each kept unit write out/payloads/<id>.json = {id,group,kind,num,name,body}.
#   - body  = the unit's normalized text (the parser's rendered RAW unit markdown,
#             which may contain </script>) -> stands in for the resume brief,
#             deterministically; escaped at embed time, not by the parser (F1).
#   - name  = the chat title from the manifest.
#   - group = STANDALONE (every kept chat unassigned to a project -> STANDALONE).
#   - DATA_JSON = JSON array of the card objects, with /<\/(script)/gi -> "<\/$1"
#     applied to the SERIALIZED json before injection (H-4).
#   - substitute {{DATA_JSON}} {{RUN}} {{GROUP_LABEL_*}} in the shipped template.
# The injection is done by a small inline node script (robust JSON + escaping),
# never sed.
OUT="$RUN/out"
mkdir -p "$OUT/payloads"

node - "$MANIFEST" "$RUN" "$TEMPLATE" "$OUT" <<'NODE'
"use strict";
const fs = require("fs");
const path = require("path");
const [, , manifestPath, runDir, templatePath, outDir] = process.argv;

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const RUN_ID = manifest.run || "copy-page-test";

// Same closing-script escape the page generator uses (SPEC §5.6, H-4).
function escapeScriptClose(s) {
  return String(s).replace(/<\/(script)/gi, "<\\/$1");
}

// Find the rendered unit markdown for a UNNN under units/pending/.
function unitBody(unnn) {
  const dir = path.join(runDir, "units", "pending");
  const f = fs.readdirSync(dir).find((n) => n.startsWith(unnn + "__") && n.endsWith(".md"));
  if (!f) throw new Error("no unit markdown for " + unnn);
  return fs.readFileSync(path.join(dir, f), "utf8");
}

// Kept = NOT looks_empty. Mirrors dropping the empty chat from the card set.
const cards = [];
let num = 0;
for (const u of manifest.units) {
  const value = JSON.parse(fs.readFileSync(path.join(runDir, "value", u.unnn + ".value.json"), "utf8"));
  if (value.looks_empty === true) continue; // empty chat -> DROP from cards
  num += 1;
  const card = {
    id: u.unnn,
    group: "STANDALONE",
    kind: "chat",
    num: num,
    name: u.name,
    body: unitBody(u.unnn) // verbatim RAW content (may contain </script>); the
                           // embed step below escapes it at embed time (H-4)
  };
  cards.push(card);
}

// Per-card payloads (byte-exact body the verifier compares against).
const payloadDir = path.join(outDir, "payloads");
fs.mkdirSync(payloadDir, { recursive: true });
for (const c of cards) {
  fs.writeFileSync(path.join(payloadDir, c.id + ".json"), JSON.stringify(c, null, 2) + "\n", "utf8");
}

// INLINE branch: every card carries its body inline in the #data block.
const dataJson = escapeScriptClose(JSON.stringify(cards));

let html = fs.readFileSync(templatePath, "utf8");
// Each token appears exactly once in a live slot; replace deterministically.
html = html.replace("{{DATA_JSON}}", dataJson);
html = html.replace("{{RUN}}", RUN_ID);
html = html.replace("{{GROUP_LABEL_GROUPED}}", "Grouped chats");
html = html.replace("{{GROUP_LABEL_STANDALONE}}", "Standalone chats");
html = html.replace("{{GROUP_LABEL_REFERENCE}}", "Reference chats");

fs.writeFileSync(path.join(outDir, "index.html"), html, "utf8");
process.stdout.write(String(cards.length));
NODE
ASSEMBLE_RC=$?
assert_eq "ASSEMBLE: inline copy-page built" "0" "$ASSEMBLE_RC"

# Structural asserts (independent of Playwright).
INDEX="$OUT/index.html"
[[ -f "$INDEX" ]] \
  && report_pass "ASSEMBLE: out/index.html written" \
  || report_fail "ASSEMBLE: out/index.html written" "missing"

# Expect 3 kept cards: U000 (trip), U002 (</script>), U003 (long). U001 dropped.
PAYLOAD_N=$(find "$OUT/payloads" -name '*.json' | wc -l | tr -d ' ')
assert_eq "ASSEMBLE: 3 payloads written (empty chat dropped)" "3" "$PAYLOAD_N"
[[ -f "$OUT/payloads/U001.json" ]] \
  && report_fail "ASSEMBLE: empty chat U001 not carded" "U001 payload exists" \
  || report_pass "ASSEMBLE: empty chat U001 not carded"

# No leftover {{...}} placeholders remain in the assembled page.
if grep -qE '\{\{[A-Z_]+\}\}' "$INDEX"; then
  report_fail "ASSEMBLE: all template placeholders substituted" "stray {{TOKEN}} remains"
else
  report_pass "ASSEMBLE: all template placeholders substituted"
fi

# AC-ESCAPE structural: the </script> card's body, embedded in #data, is escaped.
# The raw, unescaped closing tag must NOT appear inside the #data block; the safe
# "<\/script" form must. (verify-copy-page.cjs then proves it copies byte-exact.)
set +e
node - "$INDEX" <<'NODE'
"use strict";
const fs = require("fs");
const html = fs.readFileSync(process.argv[2], "utf8");
// Extract the #data block contents.
const m = html.match(/<script id="data"[^>]*>([\s\S]*?)<\/script>/);
if (!m) { console.error("NO_DATA_BLOCK"); process.exit(3); }
const block = m[1];
// The data block must parse as JSON (page does JSON.parse(textContent)).
let arr;
try { arr = JSON.parse(block); } catch (e) { console.error("DATA_PARSE_FAIL: " + e.message); process.exit(4); }
if (!Array.isArray(arr) || arr.length !== 3) { console.error("BAD_LEN: " + (arr && arr.length)); process.exit(5); }
// Tokenizer-safety: no RAW closing </script tag may appear inside #data (any
// closing-script sequence must be backslash-escaped so the HTML parser does not
// terminate the block early). JSON.parse above already proved restorability.
if (/<\/script/i.test(block)) { console.error("RAW_SCRIPT_CLOSE"); process.exit(6); }
process.exit(0);
NODE
ESC_RC=$?
set -e
case "$ESC_RC" in
  0) report_pass "AC-ESCAPE: #data parses + </script> embedded in safe escaped form" ;;
  3) report_fail "AC-ESCAPE: #data block present" "no <script id=data> block" ;;
  4) report_fail "AC-ESCAPE: #data parses as JSON" "JSON.parse failed" ;;
  5) report_fail "AC-ESCAPE: #data has 3 cards" "wrong array length" ;;
  6) report_fail "AC-ESCAPE: no raw </script close tag in #data" "raw closing tag present (tokenizer-unsafe)" ;;
  *) report_fail "AC-ESCAPE: #data structural check" "node exit $ESC_RC" ;;
esac

# ==================================================== AC-VERIFY / AC-COPYFAIL
# Drive the assembled page through the real verifier IF playwright is present.
if node -e "require('playwright')" >/dev/null 2>&1; then
  set +e
  VERIFY_OUT=$(node "$VERIFY_CJS" "$OUT" 2>"$SANDBOX/verify.err")
  VERIFY_RC=$?
  set -e
  if [[ "$VERIFY_RC" -eq 0 ]]; then
    report_pass "AC-VERIFY: verify-copy-page.cjs exits 0 on assembled page (+AC-COPYFAIL)"
  else
    report_fail "AC-VERIFY: verify-copy-page.cjs exits 0 on assembled page" "rc=$VERIFY_RC"
    echo "---- verify stdout ----"; echo "$VERIFY_OUT"
    echo "---- verify stderr ----"; cat "$SANDBOX/verify.err" 2>/dev/null || true
  fi
else
  echo "SKIP: playwright unavailable - browser verification (AC-VERIFY/AC-COPYFAIL) skipped"
  # The optional runtime is missing; the structural asserts above already proved
  # the page + payloads were written and the #data block parses. Do NOT fail.
fi

# ------------------------------------------------------------------ summary
echo
echo "=============================================================="
echo "claude-migrate spine tests:  PASS=$PASS  FAIL=$FAIL"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
