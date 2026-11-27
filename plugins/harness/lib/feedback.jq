# Privacy rule of /harness:feedback (H-140, D43), loaded by lib/feedback.sh with
# `jq -L lib 'include "feedback"; ...'`. The cleaner and the send gate use this one rule set.
#
# The person's description is judged line by line, by where a private shape STARTS; no rule
# guesses where a path or a value ends. A line that holds one is replaced whole by
# "<line removed: path>", "<line removed: secret>" or "<line removed: account>"; a line is never
# cut. A path inside the plugin is first written as "plugin-root/...".
#
# The added context is never cleaned: lib/feedback.sh builds it from named fields only, and
# the gate checks each of its lines against the fixed field grammar (ctx_line).

def HEADER: "Technical context (added by the harness feedback command):";
def place($k): "<line removed: \($k)>";
def is_place: test("^<line removed: (?:path|secret|account)>$");
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

# ---- the plugin root ----------------------------------------------------------------------
# It counts only when "/", the end, a separator or end punctuation follows, so a sibling
# folder such as "<root>-private" stays a foreign path.
def s_root($roots):
  reduce ($roots | map(select(length > 1)) | sort_by(-length))[] as $r
    (.; gsub(($r | esc) + "(?=/|$|[\\s\"'`<>()\\[\\]{},;|]|[.:!?]+(?:\\s|$))"; "plugin-root"));

# ---- path: the start of an absolute, ~, ../, $HOME, drive, UNC or file: path ---------------
# A "/" after a letter, digit, "_", ".", "-", "+", "*" or a closing bracket is relative and
# stays (plugins/harness/x, macOS/Linux, 3/1/0); after anything else it starts a path. A slash
# command (/harness:run) and a single lower-case word (/tmp) stay. Web links (http, https)
# without user info, and /dev/null, stdin, stdout and stderr, are masked first.
def link_re: "(?i)(?<![A-Za-z0-9+.-])https?://[^\\s\"'`<>/@]+(?:[/?#][^\\s\"'`<>]*)?";
def dev_re: "(?<![A-Za-z0-9_.-])/dev/(?:null|stdin|stdout|stderr)(?=[.,;:!?)\\]>\"'`]*(?:\\s|$))";
def relative: "[\\p{L}\\p{N}_.+*)\\]}-]";
def slash_cmd: "/[a-z][a-z0-9_-]*(?::[a-z0-9_-]+)*(?=[.,;:!?)\\]>\"'`]*(?:\\s|$))";
def path_list: [
  "(?<!" + relative + ")(?!" + slash_cmd + ")/+[^\\s/\"'`<>)\\]}]",
  "(?:^|\\s)-[A-Za-z]/[^\\s/]",
  "(?<![\\p{L}\\p{N}_.-])~[A-Za-z0-9._-]*/",
  "(?<![A-Za-z0-9_.-])\\.\\./",
  "\\$\\{?HOME(?![A-Za-z0-9_])",
  "(?<![A-Za-z0-9])[A-Za-z]:[\\\\/]",
  "(?<![A-Za-z0-9])\\\\\\\\[A-Za-z0-9]",
  "(?i)(?<![A-Za-z0-9])file:/"
];
def masked: gsub(link_re; " L ");
def path_hit: masked | gsub(dev_re; " D ") as $l | any(path_list[]; . as $re | $l | test($re));

# ---- secret: a known token prefix, link credentials, a secret key with a value, a long key ---
def token_list: [
  "gh[pousr]_[A-Za-z0-9]{16,}", "github_pat_[A-Za-z0-9_]{16,}",
  "(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}", "(?<![A-Za-z0-9])[spr]k_(?:live|test)_[A-Za-z0-9]{8,}",
  "(?<![A-Za-z0-9])glpat-[A-Za-z0-9_-]{16,}", "(?<![A-Za-z0-9])hf_[A-Za-z0-9]{16,}",
  "(?<![0-9])[0-9]{6,12}:[A-Za-z0-9_-]{30,}", "xox[abposr]-[A-Za-z0-9-]{10,}",
  "(?:AKIA|ASIA)[0-9A-Z]{16}", "AIza[0-9A-Za-z_-]{30,}", "ya29\\.[A-Za-z0-9_-]{20,}",
  "SG\\.[A-Za-z0-9_-]{16,}\\.", "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.",
  "-----BEGIN [A-Z ]*PRIVATE KEY", "hooks\\.slack\\.com/(?:services|workflows|triggers)/",
  "discord(?:app)?\\.com/api/webhooks/", "(?i)(?<![A-Za-z0-9])bearer\\s+[A-Za-z0-9._~+/=-]{8,}",
  # scheme://user@ or user:pass@ (a password may hold "/"; host:8080/... is a port)
  "(?i)[a-z][a-z0-9+.-]*://[^\\s/@]*@", "(?i)[a-z][a-z0-9+.-]*://[^\\s/@:]*:(?![0-9]+(?:[/?#\\s]|$))[^\\s@]*@",
  "(?:^|\\s)(?:-u|--user)(?:\\s+|=)[^\\s:]+:\\S"
];
# A key names a secret when, in lower case, it ends with one of the words below, or its last
# "_", "-" or "." part is pwd or pw, or pass after another part (DB_PASS), or it ends with
# <api|access|private|secret|signing|encryption|master|client> key. So max_tokens, token_count,
# PASS, bypass and passed are not secret keys.
def secret_key:
  ascii_downcase as $k | ($k | [splits("[_.-]+")] | map(select(length > 0))) as $p
  | ($k | test("(?:password|passwd|passphrase|secret|token|apikey|credentials?|authorization|cookie|privatekey|accesskey|secretkey)$"))
    or ($p[-1] | IN("pwd", "pw")) or (($p | length) > 1 and $p[-1] == "pass")
    or (($p | length) > 1 and $p[-1] == "key"
        and ($p[-2] | IN("api", "access", "private", "secret", "signing", "encryption", "master", "client")));
def key_re: "(?<![A-Za-z0-9_.-])(?<k>[A-Za-z][A-Za-z0-9_.-]*)[\"']?[ \\t]*[:=][ \\t]*\\S";
def flag_re: "(?:^|[\\s\"'])--(?<k>[A-Za-z][A-Za-z0-9_-]*)(?:=|[ \\t]+)[^\\s-]";
# A long key-like string: 24 or more letters and digits with both, or 40 or more of
# [A-Za-z0-9+/=_-] with upper case, lower case and a digit outside web links (base64 with
# "/"). Hyphens break the first kind, so UUIDs, run IDs and branch names stay; short hashes
# are under 24.
def long_hit:
  any(match("[A-Za-z0-9]{24,}"; "g").string; test("[0-9]") and test("[A-Za-z]"))
  or any(masked | match("[A-Za-z0-9+/=_-]{40,}"; "g").string; test("[0-9]") and test("[a-z]") and test("[A-Z]"));
def secret_hit:
  . as $l
  | any(token_list[]; . as $re | $l | test($re))
    or any(($l | match(key_re; "g"), match(flag_re; "g")) | .captures[0].string; secret_key)
    or long_hit;

# ---- account: the local account name (3 or more characters) anywhere, any case; e-mail -----
def account_hit($accts):
  (gsub("plugin-root"; "") | ascii_downcase) as $l
  | any($accts[] | select(length >= 3) | ascii_downcase; . as $a | $l | contains($a))
    or test("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}");

# reason($accts): "path", "secret", "account" or null for one line. A placeholder is clean.
def reason($accts):
  if is_place then null
  elif path_hit then "path"
  elif secret_hit then "secret"
  elif account_hit($accts) then "account"
  else null end;

# ---- entry points -------------------------------------------------------------------------
# clean: the description, line by line.
def clean($roots; $accts):
  split("\n") | map(s_root($roots) | reason($accts) as $r | if $r then place($r) else . end) | join("\n");

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

# kinds($accts; $fixed): the kinds of private data in a draft (title text, then body), "" when
# none. Never the text itself. Lines from the last "---" + HEADER pair on are the context.
def kinds($accts; $fixed):
  split("\n") as $l
  | ([range(1; $l | length) | select($l[.] == HEADER and $l[. - 1] == "---")] | last) as $h
  | [range(0; $l | length) as $i | $l[$i]
      | if $h != null and $i >= $h - 1 then (if ctx_line($fixed) then empty else reason($accts) // "outside" end)
        else reason($accts) // empty end]
  | unique
  | map({path: "a path outside the plugin", secret: "a secret or token", account: "an account name or e-mail address",
         outside: "a line outside the fixed context fields"}[.])
  | join(", ");
