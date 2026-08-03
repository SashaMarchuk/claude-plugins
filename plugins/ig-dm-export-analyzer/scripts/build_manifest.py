#!/usr/bin/env python3
"""Step 1 — manifest builder.

Walks every conversation in the export (mojibake-fixed on load), applies the
config's date-range filter plus manual thread exclusions, resolves every
audio/video/photo URI to a real file, and emits:

  <output>/threads.json    one row per thread (kept or excluded, with reason)
  <output>/manifest.jsonl  one row per media file inside kept, in-scope messages

threads.json is the independent reconciliation source Step 4 checks the
assembled output against.

Usage: python3 build_manifest.py <config.yaml|.json>
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from igdm_common import (  # noqa: E402
    MediaResolver, RunLog, detect_owner_name, in_scope, iter_thread_dirs,
    load_config, load_thread, out_dir,
)


def ffprobe_audio_info(abs_path: Path):
    """Return (has_audio_track, duration_s) via ffprobe. Raises on failure."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error",
             "-select_streams", "a",
             "-show_entries", "stream=codec_type",
             "-show_entries", "format=duration",
             "-of", "json", str(abs_path)],
            capture_output=True, text=True, timeout=60, check=True,
        )
        data = json.loads(out.stdout)
        dur = data.get("format", {}).get("duration")
        return bool(data.get("streams")), (round(float(dur), 1) if dur is not None else None)
    except Exception as e:
        raise RuntimeError(f"ffprobe failed on {abs_path}: {e}")


def main(config_path: str) -> None:
    cfg = load_config(config_path)
    od = out_dir(cfg)
    log = RunLog(od)

    text_root = Path(cfg["export"]["text_root"])
    fix = bool(cfg["export"]["fix_mojibake"])
    start_ms, end_ms = cfg["filter"]["start_ms"], cfg["filter"]["end_ms"]
    excluded = set(cfg["filter"]["exclude_thread_slugs"])

    log(f"Step 1 manifest: text_root={text_root} fix_mojibake={fix} "
        f"range=[{cfg['filter']['start']} .. {cfg['filter']['end']}) "
        f"manual_exclusions={sorted(excluded) or 'none'}")

    thread_dirs = iter_thread_dirs(text_root, cfg["filter"]["include_sources"])
    loaded = [(source, td) + load_thread(td, fix) for source, td in thread_dirs]

    configured_owner = cfg["export"]["owner_name"]
    owner = configured_owner or detect_owner_name([(m, e) for _s, _d, m, e in loaded])
    cfg["export"]["owner_name"] = owner
    log(f"Account owner: {owner!r}" + ("" if configured_owner else " (auto-detected)"))

    resolver = MediaResolver(text_root, cfg["export"]["media_root"])

    manifest_rows, thread_rows = [], []
    totals = dict(messages=0, in_scope=0, excluded_out_of_range=0,
                  excluded_manual=0, dropped_tail=0)
    counts = dict(audio=0, video_audio=0, video_silent=0, photo=0)

    for source, thread_dir, meta, entries in loaded:
        slug = thread_dir.name
        totals["messages"] += len(entries)

        scoped = [k for k, (_p, _j, m) in enumerate(entries)
                  if in_scope(m.get("timestamp_ms"), start_ms, end_ms)]
        out_of_range = len(entries) - len(scoped)

        if slug in excluded:
            status = reason = "excluded_manual_thread"
            totals["excluded_manual"] += len(entries)
        elif not scoped:
            status, reason = "excluded_out_of_range", "no_messages_in_date_range"
            totals["excluded_out_of_range"] += len(entries)
        else:
            status, reason = "kept", None
            totals["in_scope"] += len(scoped)
            totals["dropped_tail"] += out_of_range

        all_ts = [m.get("timestamp_ms") for _p, _j, m in entries if m.get("timestamp_ms")]
        thread_rows.append({
            "slug": slug,
            "source": source,
            "source_path": str(thread_dir.relative_to(text_root)),
            "pages": sorted({p for p, _j, _m in entries}),
            "title": meta.get("title"),
            "participants": [p.get("name") for p in (meta.get("participants") or [])],
            "is_still_participant": meta.get("is_still_participant"),
            "status": status,
            "reason": reason,
            "total_message_count": len(entries),
            "in_scope_message_count": len(scoped) if status == "kept" else 0,
            "out_of_range_message_count": out_of_range,
            "first_ts_ms": min(all_ts) if all_ts else None,
            "last_ts_ms": max(all_ts) if all_ts else None,
        })

        if status != "kept":
            continue

        for k in scoped:
            _page, _j, m = entries[k]
            ts_ms = m.get("timestamp_ms")
            sender = m.get("sender_name")
            direction = "out" if sender == owner else "in"
            base = {"slug": slug, "src_i": k, "ts_ms": ts_ms,
                    "sender": sender, "dir": direction}

            for a in m.get("audio_files") or []:
                abs_path = resolver.resolve(a["uri"])
                _, dur = ffprobe_audio_info(abs_path)
                manifest_rows.append(dict(base, kind="audio", uri=a["uri"],
                                          abs_path=str(abs_path), duration_s=dur))
                counts["audio"] += 1

            for v in m.get("videos") or []:
                abs_path = resolver.resolve(v["uri"])
                has_audio, dur = ffprobe_audio_info(abs_path)
                manifest_rows.append(dict(
                    base, kind="video_audio" if has_audio else "video_silent",
                    uri=v["uri"], abs_path=str(abs_path),
                    has_audio_track=has_audio, duration_s=dur))
                counts["video_audio" if has_audio else "video_silent"] += 1

            for ph in m.get("photos") or []:
                abs_path = resolver.resolve(ph["uri"])
                manifest_rows.append(dict(base, kind="photo", uri=ph["uri"],
                                          abs_path=str(abs_path)))
                counts["photo"] += 1

    (od / "manifest.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in manifest_rows),
        encoding="utf-8")
    (od / "threads.json").write_text(
        json.dumps(thread_rows, ensure_ascii=False, indent=2), encoding="utf-8")

    resolved = dict(cfg)
    resolved.pop("_config_path", None)
    resolved["_resolved"] = {
        "config_path": cfg["_config_path"],
        "owner_name": owner,
        "media_root_used": str(resolver.winner) if resolver.winner else None,
        "media_export_label": resolver.label,
    }
    (od / "config.resolved.json").write_text(
        json.dumps(resolved, ensure_ascii=False, indent=2, default=str), encoding="utf-8")

    kept = sum(1 for t in thread_rows if t["status"] == "kept")
    recon = (totals["in_scope"] + totals["excluded_out_of_range"]
             + totals["excluded_manual"] + totals["dropped_tail"])
    stt_jobs = counts["audio"] + counts["video_audio"]
    owner_voice = sum(1 for r in manifest_rows if r["kind"] == "audio" and r["dir"] == "out")
    owner_video = sum(1 for r in manifest_rows if r["kind"] == "video_audio" and r["dir"] == "out")

    log(f"Threads: {len(thread_rows)} total / {kept} kept / "
        f"{sum(1 for t in thread_rows if t['status'] == 'excluded_out_of_range')} out-of-range / "
        f"{sum(1 for t in thread_rows if t['status'] == 'excluded_manual_thread')} manually excluded")
    log(f"Messages: {totals['messages']} total / {totals['in_scope']} in scope / "
        f"{totals['dropped_tail']} dropped out-of-range tail inside kept threads")
    log(f"Reconciliation: {totals['in_scope']} + {totals['excluded_out_of_range']} + "
        f"{totals['excluded_manual']} + {totals['dropped_tail']} = {recon} "
        f"(== {totals['messages']}: {'OK' if recon == totals['messages'] else 'MISMATCH'})")
    log(f"Media rows: audio={counts['audio']} video_audio={counts['video_audio']} "
        f"video_silent={counts['video_silent']} photo={counts['photo']} "
        f"-> {stt_jobs} STT jobs")
    log(f"Owner-sent media: {owner_voice} voice, {owner_video} video-with-audio")
    if resolver.winner:
        log(f"Media resolved against: {resolver.winner}")
    if recon != totals["messages"]:
        raise SystemExit("Manifest reconciliation failed — refusing to continue.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
