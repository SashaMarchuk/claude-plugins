# Privacy rule of /harness:feedback (H-140, D43), loaded by lib/feedback.sh with
# `jq -L lib 'include "feedback"; ...'`. The cleaner and the send gate use this one rule set.
#
# The person's description is judged line by line, by where a private shape STARTS; no rule
# guesses where a path or a value ends. A line that holds one is replaced whole by
# "[line removed: path]", "[line removed: secret]" or "[line removed: account]"; a line is never
# cut. A path inside the plugin is first written as "plugin-root/...".
#
# The added context is never cleaned: lib/feedback.sh builds it from named fields only, and
# the gate checks each of its lines against the fixed field grammar (ctx_line).

def HEADER: "Technical context (added by the harness feedback command):";
def place($k): "[line removed: \($k)]";
def is_place: IN("[line removed: path]", "[line removed: secret]", "[line removed: account]");
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
# stays (plugins/harness/x, macOS/Linux, 3/1/0); after anything else it starts a path, and so
# does a "/" right after a flag (-I/, -isystem/, CFLAGS=-I/) or before a quote (/"a b"/c). A
# slash command (/harness:run) and a single lower-case word (/tmp) stay. Web links (http,
# https) without user info, and /dev/null, stdin, stdout and stderr, are masked first; a link
# ends at the first character a host or a plain link path cannot hold (",", "|", "(", ...).
def link_re: "(?i)(?<![A-Za-z0-9+.-])https?://[A-Za-z0-9.-]+(?::[0-9]+)?(?:[/?#][^\\s\"'`<>,|()\\\\]*)?";
def dev_re: "(?<![A-Za-z0-9_.-])/dev/(?:null|stdin|stdout|stderr)(?=[.,;:!?)\\]>\"'`]*(?:\\s|$))";
# Letters and digits of the common scripts as explicit ranges (\\p{L} is slow to compile in jq).
def L: "A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F\u0370-\u03FF\u0400-\u052F\u0590-\u06FF\u0900-\u0DFF\u0E00-\u0EFF\u1E00-\u1FFF\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF";
def LN: L + "0-9";
def relative: "[" + LN + "_.+*)\\]}-]";
def slash_cmd: "/[a-z][a-z0-9_-]*(?::[a-z0-9_-]+)*(?=[.,;:!?)\\]>\"'`]*(?:\\s|$))";
def path_list: [
  "(?<!" + relative + ")(?!" + slash_cmd + ")/{1,3}[^\\s/\"'`<>)\\]}]",
  "(?<!" + relative + ")/{1,3}[\"'`][^\\s\"'`/]",
  "(?<![" + LN + "_.-])--?[A-Za-z][A-Za-z0-9_]*/[^\\s/]",
  "(?<![" + LN + "_.-])~[A-Za-z0-9._-]*[/\\\\]",
  "(?<![A-Za-z0-9_.-])\\.\\./",
  # environment roots: $HOME, $VAR/, ${VAR}/, $(pwd)/, $env:HOME, %USERPROFILE%
  "\\$\\{?HOME(?![A-Za-z0-9_])", "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?[/\\\\]", "\\$\\([^)\\n]*\\)[/\\\\]",
  "(?i)\\$env:[A-Za-z_]", "(?i)%(?:userprofile|homepath|homedrive|appdata|localappdata|onedrive|temp|tmp)%",
  # Windows: X:\ and X:/, \\server and \\?\, \Users\x (two backslash parts)
  "(?<![A-Za-z0-9])[A-Za-z]:[\\\\/]", "(?<![A-Za-z0-9])\\\\\\\\[A-Za-z0-9?.]",
  "(?<![" + LN + "_.\\\\-])\\\\[A-Za-z0-9._$-]{2,}\\\\",
  "(?i)(?<![A-Za-z0-9])file:/", "(?i)%2F[^\\s%/]+%2F"
];
# blank(re): each match becomes spaces of the same length, so match offsets stay true.
def blank(re): gsub("(?<m>" + re + ")"; .m | gsub("."; " "));
def masked: blank(link_re);
def alt(list): list | map("(?:" + . + ")") | join("|");
def path_offsets: masked | blank(dev_re) | match(alt(path_list); "g").offset;

# ---- secret: a known token prefix, link credentials, a secret key with a value, a long key ---
# A known prefix needs only a few characters after it, so the first line of a token wrapped
# over two lines goes too. sk- and hf_ also need a digit or a capital soon after, so sk-learn
# and hf_hub_download stay.
def token_list: [
  "gh[pousr]_[A-Za-z0-9]{4,}", "github_pat_[A-Za-z0-9_]{4,}",
  "(?<![A-Za-z0-9])sk-(?=[A-Za-z0-9_-]{0,15}[0-9A-Z])[A-Za-z0-9_-]{4,}",
  "(?<![A-Za-z0-9])[spr]k_(?:live|test)_[A-Za-z0-9]", "(?<![A-Za-z0-9])glpat-[A-Za-z0-9_-]{4,}",
  "(?<![A-Za-z0-9])hf_(?=[A-Za-z0-9]{0,15}[0-9A-Z])[A-Za-z0-9]{4,}",
  "(?<![0-9])[0-9]{6,12}:(?:AA[A-Za-z0-9_-]{4,}|[A-Za-z0-9_-]{30,})", "xox[abposr]-[A-Za-z0-9-]{4,}",
  "(?:AKIA|ASIA)[0-9A-Z]{4,}", "AIza[0-9A-Za-z_-]{4,}", "ya29\\.[A-Za-z0-9_-]{4,}",
  "SG\\.[A-Za-z0-9_-]{8,}", "eyJ[A-Za-z0-9_-]{8,}",
  "-----BEGIN [A-Z ]*PRIVATE KEY", "hooks\\.slack\\.com/(?:services|workflows|triggers)/",
  "discord(?:app)?\\.com/api/webhooks/", "(?i)(?<![A-Za-z0-9])bearer[ \\t]+[A-Za-z0-9._~+/=-]{8,}",
  # user:pass@ with or without a scheme (a password may hold "/"); scheme://user@
  "(?i)[a-z][a-z0-9+.-]*://[^\\s/@]*@", "(?:^|[\\s\"'`(<\\[{=,;])[^\\s:@]{0,64}:(?!//)[^\\s:@]{0,128}@[^\\s@]",
  # curl -u name:pw, -uname:pw, --user name:pw, --user=name:pw
  "(?:^|\\s)(?:-u|--user)(?:[ \\t]+|=)?[^\\s:]{1,64}:\\S"
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
# Only a key that holds one of these words can be a secret key; the lookahead keeps the number
# of matches small (jq is slow on very many matches).
def key_word: "(?=[A-Za-z0-9_.-]*(?i:pass|pw|secret|token|key|credential|authorization|cookie))";
def key_re: "(?<![A-Za-z0-9_.-])(?<k>" + key_word + "[A-Za-z][A-Za-z0-9_.-]*)[\"']?[ \\t]*[:=][ \\t]*\\S";
def flag_re: "(?:^|[\\s\"'])--(?<k>" + key_word + "[A-Za-z][A-Za-z0-9_-]*)(?:=|[ \\t]+)[^\\s-]";
# A long key-like string: 24 or more letters and digits with both, or 40 or more of
# [A-Za-z0-9+/=_-] with upper case, lower case and a digit outside web links (base64 with
# "/"). Hyphens break the first kind, so UUIDs, run IDs and branch names stay; short hashes
# are under 24.
# Character checks without a regex (one regex per match would be slow on long input).
def has($lo; $hi): explode | any(. >= $lo and . <= $hi);
def secret_offsets:
  (token_list[] as $re | match($re; "g").offset),
  ([match(key_re; "g"), match(flag_re; "g") | [.captures[0].string, .offset]]
    | (map(.[0]) | unique | map({key: ., value: secret_key}) | from_entries) as $sk
    | .[] | select($sk[.[0]]) | .[1]),
  (match("[A-Za-z0-9]{24,}"; "g") | select(.string | has(48; 57) and (has(65; 90) or has(97; 122))) | .offset),
  (masked | match("[A-Za-z0-9+/=_-]{40,}"; "g") | select(.string | has(48; 57) and has(65; 90) and has(97; 122)) | .offset);

# ---- account: the local account name (3 or more characters) anywhere, any case; e-mail -----
# The name also counts with its "-", "." and "_" dropped on both sides (login a-b written as
# ab, a.b or a_b), and with zero-width characters dropped. An e-mail address needs only a
# domain that starts with a letter (zed@localhost, zed@host); pkg@1.2.3 stays.
def squash: explode | map(select(IN(45, 46, 95, 8203, 8204, 8205, 8288, 65279) | not)) | implode;
# account_line($acc): $acc = [[name, squashed name], ...] in lower case, made once.
def account_line($acc):
  length >= 3 and ($acc | length) > 0
  and ((split("plugin-root") | join("") | ascii_downcase) as $l | ($l | squash) as $q
       | any($acc[]; .[0] as $a | .[1] as $s | ($l | contains($a)) or (($s | length) >= 3 and ($q | contains($s)))));
def email_offsets: match("(?<![" + LN + "._%+-])[" + LN + "._%+-]+@[" + L + "][" + LN + "-]*"; "g").offset;

# reasons($accts): "path", "secret", "account" or null for each line of an array. Each rule is
# one regex run over the whole text (jq compiles a regex on every call, so a run per line is
# slow); match offsets are mapped back to lines. Placeholders are clean. A line of 16 or more
# token characters with a letter and a digit right after a secret line (or its placeholder) is
# the tail of a wrapped secret and goes too.
def is_tail: test("^\\s*[A-Za-z0-9_+/=.-]{16,}\\s*$") and test("[0-9]") and test("[A-Za-z]");
def reasons($accts):
  . as $ls
  | [$accts[] | ascii_downcase | select(length >= 3) | [., squash]] as $acc
  | ($ls | map(if is_place then "" else . end)) as $w | ($w | join("\n")) as $t
  | ([foreach $w[] as $x (0; . + ($x | length) + 1)] | [0] + .[:-1]) as $starts
  | def lines(offs):
      reduce (offs | . as $o | $starts | bsearch($o) | if . < 0 then -2 - . else . end) as $i
        ({}; .[$i | tostring] = true);
    ($t | lines(path_offsets)) as $p | ($t | lines(secret_offsets)) as $s | ($t | lines(email_offsets)) as $e
  | [foreach range(0; $ls | length) as $i ({prev: null};
      ($i | tostring) as $k | $ls[$i] as $x
      | (if ($x | is_place) then null elif $p[$k] then "path" elif $s[$k] then "secret"
         elif $e[$k] or ($x | account_line($acc)) then "account"
         elif .prev == "secret" and ($x | is_tail) then "secret" else null end) as $r
      | {r: $r, prev: (if ($x | is_place) then ($x | ltrimstr("[line removed: ") | rtrimstr("]")) else $r end)};
      .r)];
def reason($accts): [.] | reasons($accts) | .[0];

# ---- entry points -------------------------------------------------------------------------
# clean: the description, line by line.
def clean($roots; $accts):
  s_root($roots) | split("\n") as $ls | ($ls | reasons($accts)) as $rs
  | [range(0; $ls | length) | if $rs[.] then place($rs[.]) else $ls[.] end] | join("\n");

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
  | (if $h != null then [$l[: $h - 1], $l[$h - 1 :]] else [$l, []] end) as [$d, $c]
  | ([$d | reasons($accts)[] | select(. != null)]
     + [$c[] | select(ctx_line($fixed) | not) | reason($accts) // "outside"])
  | unique
  | map({path: "a path outside the plugin", secret: "a secret or token", account: "an account name or e-mail address",
         outside: "a line outside the fixed context fields"}[.])
  | join(", ");
