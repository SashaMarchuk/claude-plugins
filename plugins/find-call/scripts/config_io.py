#!/usr/bin/env python3
"""find-call config I/O — guarded read/write for ~/.claude/find-call/config.json.

This is the ONLY write path in the find-call plugin. The investigation flow is
read-only; only the `--config` wizard mutates state, and only this plugin-local
preferences file (never the shared identity.json or any other plugin's config).

The stored values are *preferences* (which provider to try first), not hard
restrictions — the skill's runtime always falls back to a working provider so
the data is retrieved. This script only validates and persists the values; the
preference + fallback semantics live in the skill prose.

Subcommands:
  --show                       print current config + provider availability as JSON
  --set k=v [k=v ...]          atomically write source preferences (calendar/docs/transcripts)

Writes are atomic (tmp + fsync + os.replace) under fcntl.flock on a sibling
sentinel file, mirroring the discipline the clickup/gevent shared-identity
helper uses. POSIX only (fcntl) — macOS + Linux, matching the rest of the
marketplace. The file is find-call-private, so there is no cross-plugin schema
contract to honor; unknown top-level keys are still preserved on rewrite.
"""
import argparse
import fcntl
import json
import os
import shutil
import sys
import tempfile
import time
from datetime import datetime, timezone

CONFIG_PATH = os.path.expanduser("~/.claude/find-call/config.json")
SCHEMA_VERSION = 1

CALENDAR_VALUES = {"auto", "cli", "mcp"}
DOCS_VALUES = {"auto", "cli", "mcp", "off"}
KNOWN_TRANSCRIPT_PROVIDERS = {"sembly"}


def _now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_config():
    """Return (data, error). Missing file -> ({}, None). Corrupt/wrong-shape -> ({}, message)."""
    try:
        with open(CONFIG_PATH) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}, None
    except json.JSONDecodeError as e:
        return {}, f"corrupt JSON: {e}"
    if not isinstance(data, dict):
        return {}, f"unexpected top-level JSON type: {type(data).__name__} (expected object)"
    return data, None


def _quarantine(path):
    """Move a corrupt/wrong-shape config aside so the user can inspect it.

    Uses nanosecond resolution so two quarantines in the same second never
    collide and silently overwrite each other.
    """
    os.replace(path, path + f".corrupt-{time.time_ns()}")


def atomic_write(mutate):
    """Read-modify-write CONFIG_PATH atomically under an exclusive flock."""
    path = os.path.realpath(os.path.expanduser(CONFIG_PATH))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lock_path = path + ".lock"
    dir_ = os.path.dirname(path)
    with open(lock_path, "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                data = json.load(f)
        except FileNotFoundError:
            data = {}
        except json.JSONDecodeError:
            _quarantine(path)
            data = {}
        # Structurally-valid but wrong-shape JSON (top level not an object —
        # e.g. a list or bare string from a hand-edit) is treated like
        # corruption: quarantine and start fresh, rather than crashing mutate().
        if not isinstance(data, dict):
            _quarantine(path)
            data = {}
        mutate(data)  # caller mutates in place; unknown keys are preserved
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile("w", dir=dir_, delete=False) as tmp:
                json.dump(data, tmp, indent=2, ensure_ascii=False, sort_keys=False)
                tmp.flush()
                os.fsync(tmp.fileno())
                tmp_path = tmp.name
            os.replace(tmp_path, path)
            tmp_path = None  # replaced successfully — nothing left to clean up
        finally:
            # If os.replace never ran (raised mid-way), don't orphan the temp file.
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
        try:
            dfd = os.open(dir_, os.O_RDONLY)
            os.fsync(dfd)
            os.close(dfd)
        except OSError:
            pass  # non-POSIX filesystems may not support dir fsync
    return data


def parse_transcripts(v):
    """'auto'|'off' pass through; anything else is a comma-list of providers."""
    if v in ("auto", "off"):
        return v
    providers = [p.strip().lower() for p in v.split(",") if p.strip()]
    if not providers:
        sys.exit("transcripts: empty provider list")
    unknown = [p for p in providers if p not in KNOWN_TRANSCRIPT_PROVIDERS]
    if unknown:
        # Allowed (forward-compat for new notetakers) but surfaced.
        print(f"warning: unknown transcript provider(s): {unknown}", file=sys.stderr)
    return providers


def cmd_set(pairs):
    updates = {}
    for pair in pairs:
        if "=" not in pair:
            sys.exit(f"bad --set arg (expected key=value): {pair!r}")
        k, v = (s.strip() for s in pair.split("=", 1))
        k = k.lower()  # normalize key+value case so calendar=CLI works like transcripts=SEMBLY
        if k == "calendar":
            v = v.lower()
            if v not in CALENDAR_VALUES:
                sys.exit(f"calendar must be one of {sorted(CALENDAR_VALUES)}, got {v!r}")
            updates[k] = v
        elif k == "docs":
            v = v.lower()
            if v not in DOCS_VALUES:
                sys.exit(f"docs must be one of {sorted(DOCS_VALUES)}, got {v!r}")
            updates[k] = v
        elif k == "transcripts":
            updates[k] = parse_transcripts(v)
        else:
            sys.exit(f"unknown source key: {k!r} (expected calendar|docs|transcripts)")

    def mutate(data):
        data["schemaVersion"] = SCHEMA_VERSION
        # Guard against a hand-edited non-dict `sources` (e.g. "sources": "x").
        src = data.get("sources")
        if not isinstance(src, dict):
            src = {}
            data["sources"] = src
        src.update(updates)
        data["updated_at"] = _now()

    data = atomic_write(mutate)
    json.dump(data, sys.stdout, indent=2, ensure_ascii=False)
    print()


def cmd_show():
    data, err = read_config()
    out = {
        "config_path": CONFIG_PATH,
        "exists": os.path.exists(CONFIG_PATH),
        "error": err,
        "sources": data.get("sources", {}),
        # Rough availability signal for the workspace CLI binary. Auth is NOT
        # probed here (that needs a live network call); the skill notes that.
        "cli_binary_available": shutil.which("npx") is not None,
    }
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    print()


def main():
    ap = argparse.ArgumentParser(prog="find-call config_io")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--show", action="store_true", help="print current config + availability")
    g.add_argument("--set", nargs="+", metavar="key=value", help="set source preferences")
    args = ap.parse_args()
    if args.show:
        cmd_show()
    else:
        cmd_set(args.set)


if __name__ == "__main__":
    main()
