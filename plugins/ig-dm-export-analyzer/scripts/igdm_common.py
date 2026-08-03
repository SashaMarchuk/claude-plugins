#!/usr/bin/env python3
"""Shared helpers for the ig-dm-export-analyzer skill.

Config loading, the Meta DYI mojibake fix, export-layout resolution (incl.
paginated threads and split text/media exports), time helpers, run logging.

Pure stdlib. Python 3.9+.
"""
from __future__ import annotations

import datetime
import json
import os
import re
from pathlib import Path

# --------------------------------------------------------------------------
# Mojibake fix (Meta DYI export bug: UTF-8 bytes mis-decoded as Latin-1)
# --------------------------------------------------------------------------
# Verified byte-for-byte correct against a real export.
# Idempotent: ASCII is a fixed point, and already-repaired text raises
# UnicodeEncodeError on the latin-1 round-trip and is returned unchanged.


def unmojibake(s: str) -> str:
    try:
        return s.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s  # not double-encoded, leave alone — the safe no-op case


def walk(obj):
    """Recursively apply unmojibake to every string (keys and values)."""
    if isinstance(obj, str):
        return unmojibake(obj)
    if isinstance(obj, list):
        return [walk(x) for x in obj]
    if isinstance(obj, dict):
        return {unmojibake(k): walk(v) for k, v in obj.items()}
    return obj


# Canonical UTF-8-read-as-Latin-1 artifacts. Used by verify.py as a smell test
# that the fix actually ran; these sequences do not occur in natural uk/ru/en text.
MOJIBAKE_SMELLS = ("Ð°", "Ð¾", "Ð¸", "Ñ‚", "Ñ\x81", "â€™", "â€œ", "Ð¡", "Ð\x9c")


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------

DEFAULTS = {
    "export": {
        "text_root": None,          # required
        "media_root": None,         # null -> derived from text_root's ancestors
        "owner_name": None,         # null -> auto-detected, logged
        "fix_mojibake": True,
    },
    "filter": {
        "start": None,              # ISO-8601 UTC, inclusive. null -> unbounded
        "end": None,                # ISO-8601 UTC, exclusive. null -> unbounded
        "exclude_thread_slugs": [],
        "include_sources": ["inbox", "message_requests"],
    },
    "stt": {
        "provider": "soniox",       # soniox | whisper_cpp | none
        "concurrency": 4,
        "delete_remote": "required",  # required | best_effort | skip
        "soniox": {
            "base_url": "https://api.soniox.com",
            "model": "stt-async-v4",
            "language_hints": ["uk", "ru", "en"],
            "enable_speaker_diarization": True,
            "enable_language_identification": True,
            "poll_interval_sec": 5,
            "poll_timeout_sec": 600,
            "max_retries": 5,
            "credentials": {"env_var": "SONIOX_API_KEY", "env_file": None, "key_file": None},
        },
        "whisper_cpp": {
            "binary": "whisper-cli",
            "model_path": None,
            "language": "auto",
        },
    },
    "photos": {"analyze": False},
    "output": {"dir": None},        # required
    "verify": {"expect": {}},
}

_PATH_KEYS = [
    ("export", "text_root"),
    ("export", "media_root"),
    ("output", "dir"),
]


def _deep_merge(base: dict, override: dict) -> dict:
    out = dict(base)
    for k, v in (override or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def _abs(value, base: Path):
    if value in (None, ""):
        return None
    p = Path(str(value)).expanduser()
    return p if p.is_absolute() else (base / p).resolve()


def load_config(config_path) -> dict:
    """Load a YAML or JSON config, merge over DEFAULTS, validate, resolve paths.

    Relative paths inside the config are resolved against the config file's own
    directory, so a config travels with its export.
    """
    cfg_path = Path(config_path).expanduser().resolve()
    if not cfg_path.is_file():
        raise SystemExit(f"Config not found: {cfg_path}")
    raw_text = cfg_path.read_text(encoding="utf-8")

    if cfg_path.suffix.lower() in (".yaml", ".yml"):
        try:
            import yaml  # type: ignore
        except ImportError:
            raise SystemExit(
                f"{cfg_path.name} is YAML but PyYAML is not importable under this "
                f"interpreter. Either `pip install pyyaml` or convert the config to "
                f".json (same keys) — JSON needs no dependencies."
            )
        user = yaml.safe_load(raw_text) or {}
    else:
        user = json.loads(raw_text)

    cfg = _deep_merge(DEFAULTS, user)
    cfg["_config_path"] = str(cfg_path)

    for section, key in _PATH_KEYS:
        cfg[section][key] = _abs(cfg[section][key], cfg_path.parent)
    for spec_key in ("env_file", "key_file"):
        spec = cfg["stt"]["soniox"]["credentials"]
        spec[spec_key] = _abs(spec.get(spec_key), cfg_path.parent)
    cfg["stt"]["whisper_cpp"]["model_path"] = _abs(
        cfg["stt"]["whisper_cpp"]["model_path"], cfg_path.parent
    )

    # --- validation -------------------------------------------------------
    if not cfg["export"]["text_root"]:
        raise SystemExit("config: export.text_root is required")
    if not cfg["output"]["dir"]:
        raise SystemExit("config: output.dir is required")
    if cfg["stt"]["provider"] not in ("soniox", "whisper_cpp", "none"):
        raise SystemExit(f"config: unknown stt.provider {cfg['stt']['provider']!r} "
                         f"(expected soniox | whisper_cpp | none)")
    if cfg["stt"]["delete_remote"] not in ("required", "best_effort", "skip"):
        raise SystemExit("config: stt.delete_remote must be required | best_effort | skip")
    if cfg["photos"]["analyze"]:
        raise SystemExit(
            "config: photos.analyze=true is not implemented. Photo captioning is a "
            "separate pass by design; the schema already reserves media[].caption.status "
            "== 'not_analyzed' rows for it. Set photos.analyze=false."
        )

    cfg["export"]["text_root"] = resolve_text_root(cfg["export"]["text_root"])
    cfg["filter"]["start_ms"] = parse_iso_to_ms(cfg["filter"]["start"])
    cfg["filter"]["end_ms"] = parse_iso_to_ms(cfg["filter"]["end"])
    if (cfg["filter"]["start_ms"] is not None and cfg["filter"]["end_ms"] is not None
            and cfg["filter"]["start_ms"] >= cfg["filter"]["end_ms"]):
        raise SystemExit("config: filter.start must be earlier than filter.end")
    cfg["filter"]["exclude_thread_slugs"] = list(cfg["filter"]["exclude_thread_slugs"] or [])
    return cfg


def out_dir(cfg: dict) -> Path:
    d = Path(cfg["output"]["dir"])
    d.mkdir(parents=True, exist_ok=True)
    return d


def resolve_credential(spec: dict, label: str = "API key") -> str:
    """Resolve a credential from (in order) an env var, an .env file, a key file.

    The credential *source* is config, never hardcoded. Files are read-only.
    """
    env_var = spec.get("env_var")
    if env_var:
        v = os.environ.get(env_var, "").strip()
        if v:
            return v
    env_file = spec.get("env_file")
    if env_file and Path(env_file).is_file() and env_var:
        for line in Path(env_file).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith(f"{env_var}=") or line.startswith(f'{env_var}="'):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    key_file = spec.get("key_file")
    if key_file and Path(key_file).is_file():
        v = Path(key_file).read_text(encoding="utf-8").strip()
        if v:
            return v
    raise SystemExit(
        f"{label} not found. Tried: env var {env_var!r}, env_file {env_file}, "
        f"key_file {key_file}. Set one of them in stt.<provider>.credentials."
    )


# --------------------------------------------------------------------------
# Export layout
# --------------------------------------------------------------------------

def resolve_text_root(p) -> Path:
    """Accept either the messages dir itself or an export root, return the dir
    that directly contains inbox/ and/or message_requests/."""
    p = Path(p)
    candidates = [
        p,
        p / "your_instagram_activity" / "messages",
        p / "messages",
    ]
    for c in candidates:
        if (c / "inbox").is_dir() or (c / "message_requests").is_dir():
            return c
    raise SystemExit(
        f"export.text_root does not look like an Instagram messages export: {p}\n"
        f"Expected a directory containing inbox/ and/or message_requests/ "
        f"(tried: {', '.join(str(c) for c in candidates)})"
    )


_PAGE_RE = re.compile(r"^message_(\d+)\.json$")


def iter_thread_dirs(text_root: Path, sources) -> list:
    """Yield (source, thread_dir) for every conversation folder, sorted."""
    out = []
    for source in sources:
        src_dir = text_root / source
        if not src_dir.is_dir():
            continue
        for thread_dir in sorted(src_dir.iterdir()):
            if thread_dir.is_dir() and any(_PAGE_RE.match(f.name) for f in thread_dir.iterdir()):
                out.append((source, thread_dir))
    if not out:
        raise SystemExit(f"No thread folders found under {text_root} (sources={sources})")
    return out


def load_thread(thread_dir: Path, fix_mojibake: bool = True):
    """Load a conversation, merging Meta's message_N.json pagination.

    Returns (meta, entries) where entries is a list of (page_name, idx_in_page,
    message) in raw export order (newest-first, page 1 = newest).
    """
    pages = sorted(
        (f for f in thread_dir.iterdir() if _PAGE_RE.match(f.name)),
        key=lambda f: int(_PAGE_RE.match(f.name).group(1)),
    )
    if not pages:
        raise RuntimeError(f"Thread dir with no message_N.json: {thread_dir}")

    meta = None
    entries = []
    for page in pages:
        data = json.loads(page.read_text(encoding="utf-8"))
        if fix_mojibake:
            data = walk(data)
        if meta is None:
            meta = {k: v for k, v in data.items() if k != "messages"}
        for j, m in enumerate(data.get("messages") or []):
            entries.append((page.name, j, m))
    return meta or {}, entries


class MediaResolver:
    """Resolves export-relative media URIs against one or more export roots.

    Meta often splits a DYI export into a text archive and a media archive with
    different export ids; URIs in the text archive are relative to the *media*
    archive's root. Candidate roots are tried in order and the winner is cached.
    """

    def __init__(self, text_root: Path, media_root=None):
        candidates = []
        if media_root:
            candidates.append(Path(media_root))
        # walk up from the messages dir: .../<export>/your_instagram_activity/messages
        p = Path(text_root)
        for _ in range(4):
            p = p.parent
            candidates.append(p)
        # de-dupe, preserve order
        seen = set()
        self.candidates = []
        for c in candidates:
            if str(c) not in seen and c.is_dir():
                seen.add(str(c))
                self.candidates.append(c)
        self.winner = None

    def resolve(self, uri: str) -> Path:
        order = ([self.winner] if self.winner else []) + \
                [c for c in self.candidates if c is not self.winner]
        for root in order:
            candidate = root / uri
            if candidate.is_file():
                self.winner = root
                return candidate
        raise RuntimeError(
            f"Unresolvable media URI: {uri}\nTried roots: "
            + ", ".join(str(c) for c in self.candidates)
            + "\nIf the media lives in a separate export archive, set export.media_root."
        )

    @property
    def label(self) -> str:
        return self.winner.name if self.winner else ""


def detect_owner_name(threads_meta_and_entries) -> str:
    """Owner = the display name that sends in the most conversations.

    In an Instagram DYI export the account owner is a sender in the large
    majority of threads; every contact appears in exactly one.
    """
    per_name_threads = {}
    total = 0
    for _meta, entries in threads_meta_and_entries:
        total += 1
        senders = {m.get("sender_name") for _p, _j, m in entries if m.get("sender_name")}
        for s in senders:
            per_name_threads[s] = per_name_threads.get(s, 0) + 1
    if not per_name_threads:
        raise SystemExit("Could not auto-detect the owner: no sender_name found in any thread.")
    ranked = sorted(per_name_threads.items(), key=lambda kv: -kv[1])
    top_name, top_count = ranked[0]
    if total >= 2 and top_count <= total * 0.5:
        raise SystemExit(
            "Could not confidently auto-detect the account owner "
            f"(top candidate {top_name!r} sends in only {top_count}/{total} threads). "
            "Set export.owner_name explicitly in the config.\n"
            "Candidates: " + ", ".join(f"{n!r}={c}" for n, c in ranked[:5])
        )
    return top_name


# --------------------------------------------------------------------------
# Time helpers
# --------------------------------------------------------------------------

def parse_iso_to_ms(value):
    if value in (None, ""):
        return None
    s = str(value).strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return int(dt.timestamp() * 1000)


def ts_iso(ms) -> str:
    return datetime.datetime.fromtimestamp(
        ms / 1000, tz=datetime.timezone.utc
    ).strftime("%Y-%m-%dT%H:%M:%SZ")


def ts_display(ms) -> str:
    return datetime.datetime.fromtimestamp(
        ms / 1000, tz=datetime.timezone.utc
    ).strftime("%Y-%m-%d %H:%M UTC")


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fmt_dur(seconds) -> str:
    if seconds is None:
        seconds = 0
    m = int(seconds // 60)
    s = int(round(seconds % 60))
    if s == 60:
        m += 1
        s = 0
    return f"{m}:{s:02d}"


def in_scope(ts_ms, start_ms, end_ms) -> bool:
    if ts_ms is None:
        return False
    if start_ms is not None and ts_ms < start_ms:
        return False
    if end_ms is not None and ts_ms >= end_ms:
        return False
    return True


def scope_label(cfg: dict) -> dict:
    f = cfg["filter"]
    return {
        "filter": "date_range_strict" if (f["start_ms"] or f["end_ms"]) else "no_date_filter",
        "start_utc": f["start"],
        "end_utc_exclusive": f["end"],
        "excluded_thread_slugs": f["exclude_thread_slugs"],
    }


# --------------------------------------------------------------------------
# Run log
# --------------------------------------------------------------------------

class RunLog:
    def __init__(self, output_dir: Path):
        self.path = Path(output_dir) / "run.log"

    def __call__(self, msg: str) -> None:
        line = f"[{now_iso()}] {msg}"
        print(line, flush=True)
        with self.path.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
