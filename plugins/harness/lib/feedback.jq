# Privacy cleaner of /harness:feedback (H-140, D43), loaded by lib/feedback.sh with
# `jq -L lib 'include "feedback"; ...'`. The cleaner and the send gate use these same steps:
# the gate refuses a text when any step would still change it, so the two cannot drift.
#
# Order of the steps (clean):
#   s_url_creds  scheme://user:pass@host loses user and password (before the e-mail rule)
#   s_email      e-mail addresses
#   s_root       the plugin root becomes "plugin-root", only when "/" or the end of the path follows
#   s_tokens     known token families, then any long run that looks random (before paths, so a
#                secret with "/" is never cut in half)
#   s_secrets    the value after a key or flag that names a secret (quoted values whole)
#   s_paths      home, project and current folder; then, strictly, any absolute path of two or more
#                parts wherever it starts, any ~ path, ../ path and drive path
#   s_accounts   the local account names as whole words
# Web links (http/https without user info) and plugin-root/... paths are shielded from the path
# rules and the "/" token rule: their "/" stands in as SHIELD while those rules run.

def SHIELD: "\u0002";
# Stands for "[token removed]" while the path rules run, so a removed token counts as a path
# part ("/srv/<token>/x.md" goes whole) and a token glued to a path tail goes with it.
def TOKEN_PART: "\u0003";
def esc: gsub("(?<c>[.^$*+?()\\[\\]{}|\\\\/-])"; "\\\(.c)");
def word($a): "(?i)(?<![A-Za-z0-9_.-])" + ($a | esc) + "(?![A-Za-z0-9_-])";

# One path part (no space, quote, bracket, separator or "/"), and a word of a part with spaces.
def seg: "[^\\s\"'`<>()\\[\\]{},;/\u0002]";
def word_seg: "[^\\s\"'`<>()\\[\\]{},;/:\u0002]";
# "/part"; a part after the first may hold spaces when another "/" follows
# ("/Users/x/My Folder/y"), so "read/write and and/or" is not a path.
def first_part: "/" + seg + "+";
def part: "/" + seg + "+(?:(?:[ ]" + word_seg + "+)+(?=/))?";

# ---- shield -----------------------------------------------------------------------------
def shield_re:
  "(?<u>https?://(?:\\[credentials removed\\]@)?(?![^\\s/@]*@)[^\\s\"'`<>()\\[\\]{}]+)"
  + "|(?<![A-Za-z0-9_./~-])(?<p>plugin-root(?:/(?!\\.\\.?(?:/|\\s|$))" + seg + "+)*)";
def shield: gsub(SHIELD; "") | gsub(shield_re; (.u // .p) | gsub("/"; SHIELD));
def unshield: gsub(SHIELD; "/");
def outside_links(f): shield | f | unshield;

# ---- steps ------------------------------------------------------------------------------
def s_url_creds: gsub("(?i)(?<s>[a-z][a-z0-9+.-]*://)[^\\s/@\"'<>]*@"; "\(.s)[credentials removed]@");

def email_re: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}";
def s_email: gsub(email_re; "[e-mail removed]");

def s_root($roots):
  reduce ($roots | map(select(length > 1)) | sort_by(-length))[] as $r
    (.; gsub(($r | esc) + "(?:(?!" + seg + ")|(?=[.:!?]+(?:\\s|$)))"; "plugin-root"));

# Known families; they run first, so a later generic rule never cuts one in half.
def token_list: [
  "gh[pousr]_[A-Za-z0-9]{20,}", "github_pat_[A-Za-z0-9_]{20,}",
  "(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}", "(?<![A-Za-z0-9])[spr]k_(?:live|test)_[A-Za-z0-9]{8,}",
  "(?<![A-Za-z0-9])glpat-[A-Za-z0-9_-]{16,}", "(?<![A-Za-z0-9])hf_[A-Za-z0-9]{16,}",
  "(?<![0-9])[0-9]{6,12}:[A-Za-z0-9_-]{30,}",
  "xox[abposr]-[A-Za-z0-9-]{10,}", "AKIA[0-9A-Z]{16}", "AIza[0-9A-Za-z_-]{30,}",
  "ya29\\.[A-Za-z0-9_-]{20,}", "SG\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}",
  "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]+",
  "-----BEGIN [A-Z ]*PRIVATE KEY-----",
  "(?<=hooks\\.slack\\.com/)(?:services|workflows|triggers)/[A-Za-z0-9/_-]+",
  "(?<=discord\\.com/api/webhooks/)[0-9]+/[A-Za-z0-9_-]+",
  "(?<=discordapp\\.com/api/webhooks/)[0-9]+/[A-Za-z0-9_-]+",
  "(?i)(?<![A-Za-z0-9])bearer\\s+[A-Za-z0-9._~+/=-]{8,}"
];
# Generic runs that look random; they run after the "/" run rule.
def generic_list: [
  "(?<![A-Za-z0-9])[A-Fa-f0-9]{32,}(?![A-Za-z0-9])",
  # 40 or more token characters with a letter and a digit, also after a dot (ya29.x, SG.x.y)
  "(?<![A-Za-z0-9_+=-])(?=[A-Za-z0-9_+=-]*[0-9])(?=[A-Za-z0-9_+=-]*[A-Za-z])[A-Za-z0-9_+=-]{40,}",
  # 24 or more with lower case, upper case and a digit: an unknown token family
  "(?<![A-Za-z0-9_-])(?=[A-Za-z0-9_-]*[0-9])(?=[A-Za-z0-9_-]*[a-z])(?=[A-Za-z0-9_-]*[A-Z])[A-Za-z0-9_-]{24,}={0,2}"
];
# Outside web links, a long base64 run may hold "/" (an AWS secret key).
def slash_run: "(?<![A-Za-z0-9_+/=-])(?=[A-Za-z0-9_+/=-]*[0-9])(?=[A-Za-z0-9_+/=-]*[A-Za-z])[A-Za-z0-9_+/=-]{40,}";
def s_tokens:
  reduce token_list[] as $t (.; gsub($t; "[token removed]"))
  | outside_links(gsub(slash_run; "[token removed]"))
  | reduce generic_list[] as $t (.; gsub($t; "[token removed]"));

# A key or flag that names a secret: DB_PASSWORD, client_secret, GITHUB_TOKEN, DB_PASS,
# passphrase, Authorization; "pass", "pwd" and "pw" count only as a whole _ or - part.
def secret_name:
  "(?:[A-Za-z0-9_-]*(?:password|passwd|passphrase|token|secret|api[_-]?key|access[_-]?key|private[_-]?key|credential|authorization)[A-Za-z0-9_-]*"
  + "|(?:[A-Za-z0-9]+[_-])*(?:pass|pwd|pw)(?:[_-][A-Za-z0-9]+)*)";
def secret_val:
  "(?:\"(?!\\[)[^\"\\n]*\"|'(?!\\[)[^'\\n]*'"
  + "|(?:(?:basic|bearer|digest|token)[ \\t]+)?(?:\\[token removed\\]|[^\\s\"'\\[][^\\s\"']*))";
def secret_kv: "(?i)(?<k>(?<![A-Za-z0-9_-])" + secret_name + "[\"']?[ \\t]*[:=][ \\t]*)" + secret_val;
def secret_flag: "(?i)(?<k>(?<![A-Za-z0-9_-])--" + secret_name + "(?:=|[ \\t]+))" + secret_val;
def s_secrets: gsub(secret_kv; "\(.k)[token removed]") | gsub(secret_flag; "\(.k)[token removed]");

def abs_re: first_part + "(?:" + part + ")+/?";
def home_re: "(?:~|\\$HOME|\\$\\{HOME\\})(?:" + part + ")+/?";
def rel_re: "(?<![A-Za-z0-9_])(?:\\.\\.?/)+" + seg + "+(?:/" + seg + "+)*";
def win_re: "(?<![A-Za-z0-9])[A-Za-z]:\\\\[^\\s]+";
def glued_re: seg + "*" + TOKEN_PART + seg + "*(?:" + part + ")+/?";
def s_paths($priv):
  gsub(TOKEN_PART; "") | gsub("\\[token removed\\]"; TOKEN_PART)
  | reduce ($priv | map(select(length >= 4)) | sort_by(-length))[] as $q
    (.; gsub("(?i)" + ($q | esc); "[path removed]"))
  | outside_links(gsub(home_re; "[path removed]") | gsub(abs_re; "[path removed]")
      | gsub(glued_re; "[path removed]") | gsub(rel_re; "[path removed]") | gsub(win_re; "[path removed]"))
  | gsub(TOKEN_PART; "[token removed]");

def s_accounts($accts):
  reduce ($accts[] | select(length >= 3)) as $a (.; gsub(word($a); "[account removed]"));

# ---- entry points -----------------------------------------------------------------------
def clean($roots; $accts; $priv):
  s_url_creds | s_email | s_root($roots) | s_tokens | s_secrets | s_paths($priv) | s_accounts($accts);

# The kinds of private data still in a text, "" when none. Never the text itself.
def kinds($accts; $priv):
  . as $s
  | def changed(f): ($s | f) != $s;
  [ (if changed(s_url_creds) or changed(s_tokens) then "a token" else empty end),
    (if changed(s_secrets) then "a secret value" else empty end),
    (if changed(s_email) then "an e-mail address" else empty end),
    (if changed(s_paths($priv)) then "a path outside the plugin" else empty end),
    (if changed(s_accounts($accts)) then "an account name" else empty end) ] as $k
  | if ($k | length) == 0 and changed(clean([]; $accts; $priv)) then "private data" else $k | join(", ") end;
