# Context check of /harness:feedback (H-140, D43, owner decision 2026-11-27 on #92), loaded by lib/feedback.sh with
# `jq -L lib 'include "feedback"; ...'`.
#
# The person's description is sent as written (owner decision 2026-11-27 on #92). The added context is built from named
# fields only; the send gate checks each of its lines against the fixed field grammar below.

def HEADER: "Technical context (added by the harness feedback command):";
def esc: gsub("(?<c>[.^$*+?()\\[\\]{}|\\\\/-])"; "\\\(.c)");

# ---- fixed fields -------------------------------------------------------------------------
def fb_roles: ["orchestrator", "worker", "validator"];
# The engine's own event kinds that report a failure or an owner step. Only these are copied.
def fb_error_kinds: ["deliver-failed", "marker-foreign", "owner-action", "pretrust-refused",
  "session-boot-failed", "session-close-failed", "session-close-refused", "session-close-timeout",
  "session-dead", "session-launch-failed", "unreadable"];
def shape_ver: "v?[0-9]+(?:\\.[0-9]+){1,3}(?:[-+][0-9A-Za-z.]{1,20})?";
def shape_os_s: "Darwin|Linux|FreeBSD|OpenBSD|NetBSD|SunOS|(?:CYGWIN|MINGW32|MINGW64|MSYS)_NT-[0-9.]+(?:-[0-9]+)?";
def shape_os_r: "[0-9][0-9A-Za-z._+-]{0,63}";
def shape_os_m: "x86_64|amd64|arm64|aarch64|i[3-6]86|armv[0-9a-z]{1,8}|riscv64|ppc64le|s390x";
# fit($re): the value when it has the shape, else "unknown".
def fit($re): if test("^(?:" + $re + ")$") then . else "unknown" end;

# ctx_line($fixed): the line is one of the fixed context fields. $fixed = {rts, states}.
def ctx_line($fixed):
  ((fb_roles + ["other"]) | join("|")) as $r | (fb_error_kinds | join("|")) as $e
  | ($fixed.states | join("|")) as $s | ($fixed.rts | join("|")) as $rt
  | test("^(?:|---|" + (HEADER | esc) + ")$")
    or test("^- Plugin version: (?:unknown|" + shape_ver + ")$")
    or test("^- Runtime: (?:unknown \\((?:the config cannot be read|runtime\\.main is not a runtime name|not a runtime the plugin ships)\\)"
      + "|not set \\(config runtime\\.main is empty\\)|(?:" + $rt + ")(?:, version unknown|, not installed| version unknown| (?:" + shape_ver + ")))$")
    or test("^- Operating system: (?:unknown|" + shape_os_s + ") (?:unknown|" + shape_os_r + ") (?:unknown|" + shape_os_m + ")$")
    or test("^- Last run: (?:there is no last run of this engine in this project|found, but its ledger could not be read|(?:not )?stopped, [0-9]+ ledger events)$")
    or test("^- Steps \\(session roles launched\\): (?:none|(?:" + $r + ") [0-9]+(?:, (?:" + $r + ") [0-9]+)*)$")
    or test("^- Engine error codes: (?:none|(?:" + $e + ") x[0-9]+(?:, (?:" + $e + ") x[0-9]+)*)$")
    or test("^- Tickets per state: (?:unavailable|(?:" + $s + ") [0-9]+(?:, (?:" + $s + ") [0-9]+)*)$");

# context_check($fixed): "" when the context (from the last "---" + HEADER pair on) holds only
# fixed fields; else what is wrong. Never the text itself.
def context_check($fixed):
  split("\n") as $l
  | ([range(1; $l | length) | select($l[.] == HEADER and $l[. - 1] == "---")] | last) as $h
  | if $h == null then "the fixed context is missing"
    elif any($l[$h - 1 :][]; ctx_line($fixed) | not) then "a line outside the fixed context fields"
    else "" end;
