#!/usr/bin/env python3
"""
gevent pre-flight (mechanical, prose-as-code mitigation — see L-19).

Runs three invariants before SKILL.md step 1:
  1. detect_shadow_dirs() — broad glob for legacy create-call directories
     (canonical + ~/.claude.backup-*, ~/.claude.bak/, ~/.claude.old*/,
     ~/.claude-backup-*, ~/.claude-plugins-backup-*).
  2. validate_schema() — type/shape checks on identity.json + gevent/config.json
     (schemaVersion int, behavior.notes_bot_decided strict bool,
     always_include array, defaults.calendar matches CALENDAR_ID_RE,
     defaults.send_updates / duration_minutes / conference_type type-checked).
  3. auth_probe() — runs the Google Workspace CLI against `calendars get
     --params {"calendarId":"primary"}` and applies the SKILL.md step 5
     classifier (schema-check-not-substring, broadened error regex).

Exit codes:
  0 — all three invariants pass.
  1 — shadow dir(s) detected (banner — non-fatal in SKILL.md prose, but the
      script exits non-zero so callers can decide).
  2 — schema validation failed (HALT — config corrupt or wrong type).
  3 — auth probe failed (HALT — re-auth required).
  4 — preflight crashed (uncaught exception — bug in the script).

Usage:
  python plugins/gevent/scripts/preflight.py
  # or, from SKILL.md step 1 prose:
  #   ! python plugins/gevent/scripts/preflight.py
"""
from __future__ import annotations

import glob
import json
import os
import pathlib
import re
import subprocess
import sys
import traceback
from typing import Any

HOME = pathlib.Path.home()

IDENTITY_PATH = HOME / ".claude" / "shared" / "identity.json"
CONFIG_PATH = HOME / ".claude" / "gevent" / "config.json"

SHADOW_PATTERNS = [
    str(HOME / ".claude/skills/create-call"),
    str(HOME / ".claude.backup-*/skills/create-call"),
    str(HOME / ".claude.backup-*/skills-create-call"),
    str(HOME / ".claude.bak/skills/create-call"),
    str(HOME / ".claude.bak/skills-create-call"),
    str(HOME / ".claude.old*/skills/create-call"),
    str(HOME / ".claude.old*/skills-create-call"),
    str(HOME / ".claude-backup-*/skills/create-call"),
    str(HOME / ".claude-backup-*/skills-create-call"),
    str(HOME / ".claude-plugins-backup-*/skills-create-call"),
    str(HOME / ".claude-plugins-backup-*/skills/create-call"),
]

CALENDAR_ID_RE = re.compile(
    r"^[a-zA-Z0-9._\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$"
    r"|^primary$"
    r"|^[a-f0-9]{24,}@group\.calendar\.google\.com$"
)

VALID_SEND_UPDATES = {"all", "externalOnly", "none"}
VALID_CONFERENCE_TYPES = {"hangoutsMeet"}

CURRENT_SCHEMA_VERSION = 2
PREVIOUS_SCHEMA_VERSION = 1

AUTH_OK_REQUIRED_KEYS = ("id",)
AUTH_OK_FORBIDDEN_KEYS = ("error",)

REAUTH_REGEX = re.compile(
    r"\b(401|403|407|5\d\d)\b"
    r"|invalid.*credential|token.*expired|login required|unauthorized"
    r"|forbidden|proxy authentication|ENOTFOUND|ECONNREFUSED|ECONNRESET"
    r"|ETIMEDOUT|ENETUNREACH|EAI_AGAIN|certificate|self.signed|SSL|TLS"
    r"|Fehler|ошибка",  # Russian "ошибка"
    re.IGNORECASE,
)

SETUP_REGEX = re.compile(
    r"command not found|npm ERR!|MODULE_NOT_FOUND|Cannot find module|E404|npx: not found",
    re.IGNORECASE,
)


def _eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def detect_shadow_dirs() -> list[str]:
    """Return the list of legacy create-call directories shadowing the plugin.

    Empty list = no shadowing detected. Non-empty list = banner-worthy hits.
    """
    hits: list[str] = []
    for pat in SHADOW_PATTERNS:
        for p in glob.glob(pat):
            path = pathlib.Path(p)
            # Reject symlinks defensively — match SKILL.md step 1 prose.
            if path.is_dir() and not path.is_symlink():
                hits.append(str(path))
    # Dedupe (a backup dir matching multiple patterns counted once).
    return sorted(set(hits))


def _load_json(path: pathlib.Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        with path.open() as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        _eprint(f"[preflight] schema: cannot parse {path}: {e}")
        return None


def _is_strict_bool_true(v: Any) -> bool:
    return isinstance(v, bool) and v is True


def validate_schema() -> list[str]:
    """Return list of validation failures (empty list = pass).

    Mirrors SKILL.md step 3a + step 4 + M-4 calendarId regex + L-6 type checks.
    """
    failures: list[str] = []

    identity = _load_json(IDENTITY_PATH)
    config = _load_json(CONFIG_PATH)

    if identity is None:
        failures.append(
            f"identity.json missing or unparseable at {IDENTITY_PATH}; "
            "run `/gevent:onboard identity` first."
        )
    else:
        sv = identity.get("schemaVersion")
        if not isinstance(sv, int) or isinstance(sv, bool):
            failures.append(
                f"identity.json: schemaVersion must be int, got "
                f"{type(sv).__name__}={sv!r}"
            )
        elif sv > CURRENT_SCHEMA_VERSION:
            failures.append(
                f"identity.json: schemaVersion={sv} exceeds supported "
                f"{CURRENT_SCHEMA_VERSION}; upgrade plugin."
            )
        if not _is_strict_bool_true(identity.get("onboarding_complete")):
            failures.append(
                "identity.json: onboarding_complete must be JSON boolean true; "
                "run `/gevent:onboard identity`."
            )

    if config is None:
        failures.append(
            f"gevent/config.json missing or unparseable at {CONFIG_PATH}; "
            "run `/gevent:onboard calendar` first."
        )
    else:
        sv = config.get("schemaVersion")
        if not isinstance(sv, int) or isinstance(sv, bool):
            failures.append(
                f"config.json: schemaVersion must be int, got "
                f"{type(sv).__name__}={sv!r}"
            )
        elif sv > CURRENT_SCHEMA_VERSION:
            failures.append(
                f"config.json: schemaVersion={sv} exceeds supported "
                f"{CURRENT_SCHEMA_VERSION}; upgrade plugin."
            )
        # M-1 strict-type gate.
        nbd = config.get("behavior", {}).get("notes_bot_decided")
        if not _is_strict_bool_true(nbd):
            failures.append(
                "config.json: behavior.notes_bot_decided must be JSON "
                f"boolean true (M-1 strict type), got {type(nbd).__name__}={nbd!r}"
            )
        ai = config.get("always_include")
        if not isinstance(ai, list):
            failures.append(
                "config.json: always_include must be JSON array (M-1), "
                f"got {type(ai).__name__}={ai!r}"
            )
        # M-4 calendarId regex.
        cal = config.get("defaults", {}).get("calendar")
        if not isinstance(cal, str) or not CALENDAR_ID_RE.match(cal):
            failures.append(
                f"config.json: defaults.calendar={cal!r} does not match "
                "CALENDAR_ID_RE (M-4); refusing — never enters JSON envelope."
            )
        # L-6 send_updates / duration_minutes / conference_type type checks.
        su = config.get("defaults", {}).get("send_updates")
        if su not in VALID_SEND_UPDATES:
            failures.append(
                f"config.json: defaults.send_updates={su!r} not in "
                f"{sorted(VALID_SEND_UPDATES)} (L-6)."
            )
        dm = config.get("defaults", {}).get("duration_minutes")
        if (
            not isinstance(dm, int)
            or isinstance(dm, bool)
            or not (1 <= dm <= 1440)
        ):
            failures.append(
                f"config.json: defaults.duration_minutes={dm!r} not int 1..1440 (L-6)."
            )
        ct = config.get("defaults", {}).get("conference_type")
        if ct is not None and ct not in VALID_CONFERENCE_TYPES:
            failures.append(
                f"config.json: defaults.conference_type={ct!r} not in "
                f"{sorted(VALID_CONFERENCE_TYPES)} (L-6)."
            )

    return failures


def auth_probe() -> list[str]:
    """Run npx googleworkspace CLI and apply SKILL.md step 5 classifier.

    Returns empty list on auth-OK; non-empty list = HALT with these reasons.
    """
    failures: list[str] = []
    cmd = [
        "npx",
        "@googleworkspace/cli",
        "calendar",
        "calendars",
        "get",
        "--params",
        '{"calendarId":"primary"}',
    ]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except FileNotFoundError:
        failures.append(
            "auth probe: `npx` not found on PATH. Install Node.js or run "
            "`! npm i -g @googleworkspace/cli`."
        )
        return failures
    except subprocess.TimeoutExpired:
        failures.append(
            "auth probe: CLI invocation timed out after 30s — likely "
            "network failure. Re-run when connectivity is restored."
        )
        return failures

    rc = proc.returncode
    out = proc.stdout or ""
    err = proc.stderr or ""
    combined = err + out

    # 1. Auth OK schema check (NOT substring).
    if rc == 0:
        try:
            parsed = json.loads(out)
            if (
                isinstance(parsed, dict)
                and all(k in parsed for k in AUTH_OK_REQUIRED_KEYS)
                and not any(k in parsed for k in AUTH_OK_FORBIDDEN_KEYS)
            ):
                return failures  # PASS
        except json.JSONDecodeError:
            pass

    # 2. Re-auth path.
    if REAUTH_REGEX.search(combined):
        failures.append(
            "auth probe: re-auth required. Run "
            "`! npx @googleworkspace/cli auth login --services calendar,people` "
            f"and retry. Raw: {(err or out).strip()[:400]}"
        )
        return failures

    # 3. Setup problem.
    if SETUP_REGEX.search(combined):
        failures.append(
            "auth probe: Google Workspace CLI not installed. Run "
            "`! npm i -g @googleworkspace/cli`."
        )
        return failures

    # 4. Fallthrough — never silent-pass.
    failures.append(
        "auth probe: unclassified CLI failure. If this persists, re-auth "
        "with `! npx @googleworkspace/cli auth login --services calendar,people`. "
        f"Raw: {(err or out).strip()[:400]}"
    )
    return failures


def main() -> int:
    try:
        shadow_hits = detect_shadow_dirs()
        schema_failures = validate_schema()
        auth_failures = auth_probe()
    except Exception:
        _eprint("[preflight] CRASHED — bug in preflight.py:")
        traceback.print_exc(file=sys.stderr)
        return 4

    if shadow_hits:
        _eprint(
            "[preflight] SHADOW: legacy create-call directories detected:"
        )
        for h in shadow_hits:
            _eprint(f"  - {h}")
        _eprint(
            "  Remove with: rm -rf "
            + " ".join(repr(h) for h in shadow_hits)
        )

    if schema_failures:
        _eprint("[preflight] SCHEMA: validation failed:")
        for f in schema_failures:
            _eprint(f"  - {f}")
        return 2

    if auth_failures:
        _eprint("[preflight] AUTH: probe failed:")
        for f in auth_failures:
            _eprint(f"  - {f}")
        return 3

    if shadow_hits:
        # Schema + auth passed but shadow exists; non-fatal in SKILL.md prose,
        # but exit non-zero so callers can react.
        return 1

    print("[preflight] OK: shadow + schema + auth all passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
